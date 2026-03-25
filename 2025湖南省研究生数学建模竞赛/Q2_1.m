%% 问题2：基于贝叶斯更新与事件驱动的测试任务规划（题面对齐&稳健版）
% 重点对齐：
% 1) 起算点：装置已在位、设备已调试好（不计首日setup）；更换时才计setup
% 2) 每次换台：0.5h运出 + 0.5h运入；两台可并行
% 3) 故障：按使用工时阈值（0~120h 累计 r1；120~240h 累计到 r2；>=240h必须更换；>=120h可预防更换）
% 4) 测手差错：误判/漏判各占50% => α=0.5e、β=0.5e（固定），贝叶斯更新用固定αβ
% 5) 中断不得接续：清零本工序已用时间
% 6) 事件队列：时间有序；"无事件弹出则快进到班末"，防止卡住

clear; clc; close all;

%% 参数初始化
params = initialize_parameters_aligned();

%% 仿真配置
config = struct();
config.n_devices        = 100;
config.n_replications   = 100;
config.max_days         = 100;
config.hours_per_shift  = 12;
config.buffer_time      = 0.5;   % 班末缓冲
config.verbose          = true;

%% 运行蒙特卡洛仿真
fprintf('开始仿真（%d次重复）...\n', config.n_replications);
results = monte_carlo_simulation(params, config);

%% 结果统计与展示
stats = analyze_results(results);
display_results(stats);
visualize_results(results, stats);

%% 保存
save('problem2_results.mat', 'results', 'stats', 'params', 'config');

%% ================== 函数区 ==================

function params = initialize_parameters_aligned()
    % 题面给定：测试时长、首用调试时长、差错率、先验问题概率、运入/运出、故障分段
    params.test_time  = struct('A',2.5,'B',2.0,'C',2.5,'E',3.0);
    params.setup_time = struct('A',0.5,'B',20/60,'C',20/60,'E',40/60);   % 更换时计
    params.e          = struct('A',0.03,'B',0.04,'C',0.02,'E',0.02);     % 测手差错率
    params.p0         = struct('A',0.025,'B',0.030,'C',0.020,'D',0.001); % 先验问题概率
    params.t_in  = 0.5;     % 运入时间
    params.t_out = 0.5;     % 运出时间
    % 故障累计概率（Y1）
    params.failure.r1 = struct('A',0.03,'B',0.04,'C',0.02,'E',0.03);
    params.failure.r2 = struct('A',0.05,'B',0.07,'C',0.06,'E',0.05);
    % 误判/漏判各占50% => 固定αβ
    params.alpha = structfun(@(x)0.5*x, params.e, 'UniformOutput', false); % FN
    params.beta  = structfun(@(x)0.5*x, params.e, 'UniformOutput', false); % FP

    % 成本参数（预防更换用）
    stations = {'A','B','C','E'};
    for i=1:numel(stations)
        s = stations{i};
        params.cost.failure.(s) = params.setup_time.(s) + 0.5*params.test_time.(s);
        params.cost.replace.(s) = params.setup_time.(s);
    end
end

function results = monte_carlo_simulation(params, config)
    results = struct();
    results.T   = zeros(config.n_replications, 1);
    results.S   = zeros(config.n_replications, 1);
    results.PL  = zeros(config.n_replications, 1);
    results.PW  = zeros(config.n_replications, 1);
    results.YXB = zeros(config.n_replications, 4);
    for rep = 1:config.n_replications
        if config.verbose && mod(rep,10)==0
            fprintf('  完成 %d/%d\n', rep, config.n_replications);
        end
        sim = run_single_simulation(params, config);
        results.T(rep)      = sim.completion_days;
        results.S(rep)      = sim.n_passed;
        results.PL(rep)     = sim.miss_rate;
        results.PW(rep)     = sim.false_rate;
        results.YXB(rep, :) = sim.efficiency;
    end
end

function sim = run_single_simulation(params, config)
    devices = initialize_devices(config.n_devices, params);
    sys     = initialize_system(params);

    % 起算点：两台装置已在位（不计首日setup、不计首批运入）
    % 直接占据两个测试台并设为可调度
    initial_benches = min(2, numel(devices));
    for b=1:initial_benches
        sys.benches(b).occupied  = true;
        sys.benches(b).device_id = b;
        devices(b).status        = 'testing';
        devices(b).location      = sprintf('bench_%d', b);
    end

    while sys.n_completed < numel(devices) && sys.current_day <= config.max_days
        sys.shift_time = 0;  % 新班开始（首日不计setup）
        while sys.shift_time < config.hours_per_shift
            % 取下一可在本班内发生的事件（若时间在班后则不弹出）
            [sys, ev] = pop_event_if_within_shift(sys, config);

            if ~isempty(ev)
                [sys, devices] = process_event(sys, devices, ev, params);
            end

            % 调度：给在台且ready的装置分配工位；给空台安排下一台（含运出/运入门槛）
            [sys, devices] = schedule(sys, devices, params, config);

            % 空闲时的预防更换（只在空闲工位）
            sys = preventive_replacement(sys, params);

            % —— 防卡死：若本轮未弹出事件，且下一事件在班后或不存在，则直接结束本班 ——
            if isempty(ev)
                next_t = peek_next_event_time(sys);
                latest = sys.total_time + (config.hours_per_shift - sys.shift_time);
                if isempty(next_t) || next_t > latest
                    sys.shift_time = config.hours_per_shift;
                end
            end
        end
        % 班末：在测工序按"中断不得接续"清零
        [sys, devices] = end_of_shift_cleanup(sys, devices, params);
        sys.current_day = sys.current_day + 1;
    end

    % 输出指标
    sim = collect_metrics(devices, sys);
end

function devices = initialize_devices(n, params)
    devices = struct([]);
    for i=n:-1:1
        devices(i).id = i;
        % 真实缺陷
        devices(i).true_problems = struct();
        devices(i).true_problems.A = rand()<params.p0.A;
        devices(i).true_problems.B = rand()<params.p0.B;
        devices(i).true_problems.C = rand()<params.p0.C;
        devices(i).true_problems.D = rand()<params.p0.D;
        devices(i).has_any_problem = any(struct2array(devices(i).true_problems));
        % 先验
        devices(i).prob = params.p0; % 记录A/B/C/D的信念
        % 状态&统计
        devices(i).test_passed    = struct('A',false,'B',false,'C',false,'E',false);
        devices(i).test_attempts  = struct('A',0,'B',0,'C',0,'E',0);
        devices(i).test_time_used = struct('A',0,'B',0,'C',0,'E',0);
        devices(i).status         = 'waiting';
        devices(i).location       = 'queue';
        devices(i).current_test   = '';
    end
end

function sys = initialize_system(params)
    sys.current_day = 1;
    sys.shift_time  = 0;
    sys.total_time  = 0;
    sys.n_completed = 0;
    % 两个测试台
    sys.benches = struct('occupied',{false,false},'device_id',{0,0},'available_time',{0,0});
    % 四个工位
    stations = {'A','B','C','E'};
    for i=1:numel(stations)
        s = stations{i};
        sys.stations.(s).occupied           = false;
        sys.stations.(s).device_id          = 0;
        sys.stations.(s).equipment_life     = 0;      % 使用工时
        sys.stations.(s).next_failure_usage = sample_failure_usage(params, s);
        sys.stations.(s).test_start_time    = 0;
        sys.stations.(s).work_time          = 0;      % 有效工时统计
    end
    % 事件队列（有序，统一字段）
    sys.event_queue = struct('type',{},'time',{},'device_id',{},'station',{});
end

function th = sample_failure_usage(params, s)
    u = rand; r1 = params.failure.r1.(s); r2 = params.failure.r2.(s);
    if u < r1
        th = 120*rand;
    elseif u < r2
        th = 120 + 120*rand;
    else
        th = inf;
    end
end

function [sys, devices] = process_event(sys, devices, ev, params)
    switch ev.type
        case 'transport_complete'
            devices(ev.device_id).status = 'testing';

        case 'test_complete'
            [sys, devices] = on_test_complete(sys, devices, ev, params);

        case 'equipment_failure'
            [sys, devices] = on_equipment_failure(sys, devices, ev, params);
    end
end

function [sys, devices] = on_test_complete(sys, devices, ev, params)
    id = ev.device_id; s = ev.station;

    % 生成一次观测（固定αβ）
    if s == 'E'
        has_problem = devices(id).has_any_problem;
    else
        has_problem = devices(id).true_problems.(s);
    end
    if s=='E'; has_problem = devices(id).has_any_problem; end
    alpha = params.alpha.(s);  % 漏判：有问题仍通过
    beta  = params.beta.(s);   % 误判：无问题却失败
    if has_problem
        pass = rand()<alpha;   % 漏判 => 通过
    else
        pass = rand()>=beta;   % 正确或误判
    end

    % 贝叶斯更新（A/B/C；E不回灌到单项）
    if s~='E'
        p = devices(id).prob.(s);
        if pass
            p = (p*alpha) / (p*alpha + (1-p)*(1-beta));
        else
            p = (p*(1-alpha)) / (p*(1-alpha) + (1-p)*beta);
        end
        devices(id).prob.(s) = p;
    end

    % 尝试数+通过标记/淘汰逻辑
    devices(id).test_attempts.(s) = devices(id).test_attempts.(s) + 1;
    if pass
        devices(id).test_passed.(s) = true;
        if s=='E'
            devices(id).status = 'passed';
            sys.n_completed = sys.n_completed + 1;
            % 释放台：并设置运出门槛（0.5h）
            for b=1:2
                if sys.benches(b).device_id==id
                    sys.benches(b).occupied = false;
                    sys.benches(b).device_id = 0;
                    sys.benches(b).available_time = max(sys.benches(b).available_time, sys.total_time) + 0.5; % 运出
                    break;
                end
            end
        end
    else
        if devices(id).test_attempts.(s) >= 2
            devices(id).status = 'failed';
            sys.n_completed = sys.n_completed + 1;
            for b=1:2
                if sys.benches(b).device_id==id
                    sys.benches(b).occupied = false;
                    sys.benches(b).device_id = 0;
                    sys.benches(b).available_time = max(sys.benches(b).available_time, sys.total_time) + 0.5; % 运出
                    break;
                end
            end
        end
    end

    % 释放工位 & 统计有效工时
    tt = params.test_time.(s);
    sys.stations.(s).occupied       = false;
    sys.stations.(s).device_id      = 0;
    sys.stations.(s).work_time      = sys.stations.(s).work_time + tt;
    sys.stations.(s).equipment_life = sys.stations.(s).equipment_life + tt;

    % 清理
    devices(id).test_time_used.(s) = 0;
    devices(id).current_test       = '';
end

function [sys, devices] = on_equipment_failure(sys, devices, ev, params)
    s  = ev.station; id = sys.stations.(s).device_id;
    if id==0, return; end
    elapsed = sys.total_time - sys.stations.(s).test_start_time;
    elapsed = max(elapsed, 0);
    sys.stations.(s).work_time      = sys.stations.(s).work_time + elapsed;
    sys.stations.(s).equipment_life = sys.stations.(s).equipment_life + elapsed;

    % 中断不得接续：清零该工序已用时间
    devices(id).test_time_used.(s) = 0;
    devices(id).current_test       = '';

    % 释放工位并更换设备（含setup）
    sys.stations.(s).occupied  = false;
    sys.stations.(s).device_id = 0;

    % 更换：寿命清零、重采样阈值、加入setup时间
    sys.stations.(s).equipment_life     = 0;
    sys.stations.(s).next_failure_usage = sample_failure_usage(params, s);
    sys.shift_time = sys.shift_time + params.setup_time.(s);
end

function [sys, devices] = schedule(sys, devices, params, config)
    % 先给在台ready的装置开测
    for b=1:2
        if sys.benches(b).occupied
            id = sys.benches(b).device_id;
            if strcmp(devices(id).status,'testing') && isempty(devices(id).current_test)
                nxt = next_test_for(devices(id));
                if ~isempty(nxt) && ~sys.stations.(nxt).occupied
                    remaining = config.hours_per_shift - sys.shift_time;
                    required  = params.test_time.(nxt);
                    if remaining >= required + config.buffer_time
                        sys = start_test(sys, devices, id, nxt, params);
                        devices(id).current_test = nxt;
                    end
                end
            end
        end
    end

    % 给空台安排下一台（考虑 available_time：运出+运入门槛）
    for b=1:2
        if ~sys.benches(b).occupied
            % 找第一台 waiting
            id = 0;
            for i=1:numel(devices)
                if strcmp(devices(i).status,'waiting'), id=i; break; end
            end
            if id>0
                sys.benches(b).occupied  = true;
                sys.benches(b).device_id = id;
                devices(id).status       = 'arriving';
                devices(id).location     = sprintf('bench_%d', b);
                % 安排"运入完成"时间 = max(bench可用时刻, 现在) + 0.5h
                t_arrive = max(sys.benches(b).available_time, sys.total_time) + params.t_in;
                ev = make_event('transport_complete', t_arrive, id, '');
                sys = push_event(sys, ev);
            end
        end
    end
end

function nxt = next_test_for(dev)
    nxt = '';
    for s = ["A","B","C"]
        if ~dev.test_passed.(s) && dev.test_attempts.(s)<2
            nxt = char(s); return;
        end
    end
    if dev.test_passed.A && dev.test_passed.B && dev.test_passed.C
        if ~dev.test_passed.E && dev.test_attempts.E<2
            nxt = 'E';
        end
    end
end

function sys = start_test(sys, devices, id, s, params)
    sys.stations.(s).occupied        = true;
    sys.stations.(s).device_id       = id;
    sys.stations.(s).test_start_time = sys.total_time;

    life_used = sys.stations.(s).equipment_life;
    rem_to_fail = max(1e-9, sys.stations.(s).next_failure_usage - life_used);
    tt = params.test_time.(s);

    if tt > rem_to_fail
        ev = make_event('equipment_failure', sys.total_time + rem_to_fail, id, s);
    else
        ev = make_event('test_complete',      sys.total_time + tt,         id, s);
    end
    sys = push_event(sys, ev);
end

function [sys, devices] = end_of_shift_cleanup(sys, devices, params)
    for s = ["A","B","C","E"]
        s = char(s);
        if sys.stations.(s).occupied
            id = sys.stations.(s).device_id;
            % 按题面：中断不得接续 => 清零
            devices(id).test_time_used.(s) = 0;
            devices(id).current_test = '';
            sys.stations.(s).occupied  = false;
            sys.stations.(s).device_id = 0;
        end
    end
end

function sys = preventive_replacement(sys, params)
    for s = ["A","B","C","E"]
        s = char(s);
        L = sys.stations.(s).equipment_life;
        if L >= 240
            % 强制更换
            sys.stations.(s).equipment_life     = 0;
            sys.stations.(s).next_failure_usage = sample_failure_usage(params, s);
            sys.shift_time = sys.shift_time + params.setup_time.(s);
        elseif L>=120 && L<240 && ~sys.stations.(s).occupied
            r1 = params.failure.r1.(s); r2 = params.failure.r2.(s);
            C_failure = params.cost.failure.(s);
            C_replace = params.cost.replace.(s);
            dLdt = (r2 - r1)/120 * (C_failure - C_replace);
            if dLdt > 0
                sys.stations.(s).equipment_life     = 0;
                sys.stations.(s).next_failure_usage = sample_failure_usage(params, s);
                sys.shift_time = sys.shift_time + params.setup_time.(s);
            end
        end
    end
end

function [sys, ev] = pop_event_if_within_shift(sys, config)
    ev = [];
    if isempty(sys.event_queue), return; end
    nxt = sys.event_queue(1);
    latest = sys.total_time + (config.hours_per_shift - sys.shift_time);
    if nxt.time <= latest
        ev = nxt; sys.event_queue(1) = [];
        dt = ev.time - sys.total_time;
        sys.shift_time = sys.shift_time + dt;
        sys.total_time = ev.time;
    end
end

function t = peek_next_event_time(sys)
    if isempty(sys.event_queue), t=[]; else, t = sys.event_queue(1).time; end
end

function sys = push_event(sys, ev)
    if isempty(sys.event_queue), sys.event_queue = ev; return; end
    t = [sys.event_queue.time];
    k = find(ev.time < t, 1, 'first');
    if isempty(k), sys.event_queue(end+1) = ev;
    else,          sys.event_queue = [sys.event_queue(1:k-1) ev sys.event_queue(k:end)];
    end
end

function ev = make_event(type, time, id, s)
    ev = struct('type',type,'time',time,'device_id',id,'station',s);
end

function sim = collect_metrics(devices, sys)
    sim = struct();
    sim.completion_days = sys.current_day - 1;
    pass_idx = strcmp({devices.status}, 'passed');
    sim.n_passed = sum(pass_idx);

    % 漏判：通过集合中仍有真实问题的比例
    passed = devices(pass_idx);
    if ~isempty(passed)
        n_missed = sum([passed.has_any_problem]);
        sim.miss_rate = n_missed / numel(passed);
    else
        sim.miss_rate = 0;
    end

    % 误判：淘汰集合中其实无问题的比例
    fail_idx = strcmp({devices.status}, 'failed');
    failed = devices(fail_idx);
    if ~isempty(failed)
        n_false = sum(~[failed.has_any_problem]);
        sim.false_rate = n_false / numel(failed);
    else
        sim.false_rate = 0;
    end

    % 有效工时比
    stations = {'A','B','C','E'};
    total_hours = max(1, sim.completion_days)*12;
    sim.efficiency = zeros(1,4);
    for i=1:4
        sim.efficiency(i) = sys.stations.(stations{i}).work_time / total_hours;
    end
end

function stats = analyze_results(results)
    stats.T_mean   = mean(results.T);    stats.T_std   = std(results.T);
    stats.S_mean   = mean(results.S);    stats.S_std   = std(results.S);
    stats.PL_mean  = mean(results.PL);   stats.PL_std  = std(results.PL);
    stats.PW_mean  = mean(results.PW);   stats.PW_std  = std(results.PW);
    stats.YXB_mean = mean(results.YXB,1);
    stats.YXB_std  = std(results.YXB,0,1);
end

function display_results(s)
    fprintf('\n========== 仿真结果 ==========\n');
    fprintf('任务完成天数 T: %.2f ± %.2f\n', s.T_mean, s.T_std);
    fprintf('通过装置数 S: %.2f ± %.2f\n', s.S_mean, s.S_std);
    fprintf('总漏判概率 P_L: %.4f ± %.4f\n', s.PL_mean, s.PL_std);
    fprintf('总误判概率 P_W: %.4f ± %.4f\n', s.PW_mean, s.PW_std);
    fprintf('有效工时比 YXB:\n');
    fprintf('  A: %.3f ± %.3f\n', s.YXB_mean(1), s.YXB_std(1));
    fprintf('  B: %.3f ± %.3f\n', s.YXB_mean(2), s.YXB_std(2));
    fprintf('  C: %.3f ± %.3f\n', s.YXB_mean(3), s.YXB_std(3));
    fprintf('  E: %.3f ± %.3f\n', s.YXB_mean(4), s.YXB_std(4));
    fprintf('==============================\n');
end

function visualize_results(results, stats)
    figure('Position',[100,100,1200,800]);
    subplot(2,3,1); histogram(results.T,20);
    xlabel('完成天数'); ylabel('频数');
    title(sprintf('T分布 (μ=%.1f, σ=%.1f)', stats.T_mean, stats.T_std));
    subplot(2,3,2); histogram(results.S,15);
    xlabel('通过装置数'); ylabel('频数');
    title(sprintf('S分布 (μ=%.1f, σ=%.1f)', stats.S_mean, stats.S_std));
    subplot(2,3,3); histogram(results.PL,20);
    xlabel('漏判概率'); ylabel('频数');
    title(sprintf('P_L分布 (μ=%.3f)', stats.PL_mean));
    subplot(2,3,4); histogram(results.PW,20);
    xlabel('误判概率'); ylabel('频数');
    title(sprintf('P_W分布 (μ=%.3f)', stats.PW_mean));
    subplot(2,3,5); bar(stats.YXB_mean); hold on;
    errorbar(1:4, stats.YXB_mean, stats.YXB_std, 'k.');
    set(gca,'XTickLabel',{'A','B','C','E'});
    xlabel('工位'); ylabel('有效工时比'); title('YXB对比');
    subplot(2,3,6);
    plot(cumsum(results.T)./(1:length(results.T))'); grid on;
    xlabel('仿真次数'); ylabel('累积平均完成天数'); title('收敛性');
    sgtitle('问题2仿真结果分析');
end
