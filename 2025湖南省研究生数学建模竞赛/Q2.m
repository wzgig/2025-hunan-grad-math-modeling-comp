%% 问题2完整实现：基于贝叶斯更新的测试任务规划（整合优化版）
% - 新增：设备故障 equipment_failure（按使用工时触发，0~120h 累计 r1，0~240h 累计 r2）
% - 统一事件字段：type / time / device_id / station
% - 事件队列：按时间有序插入（减少反复 min 扫描）
% - 删除 run_single_simulation 内层循环的冗余运输事件
% - 班次空闲时直接快进到班末
% - 修正作用域传参与统计

clear; clc; close all;

%% 参数初始化
params = initialize_complete_parameters();

%% 仿真配置
config = struct();
config.n_devices = 100;
config.n_replications = 100;
config.max_days = 100;
config.hours_per_shift = 12;
config.buffer_time = 0.5;  % 班末缓冲时间
config.verbose = true;

%% 运行蒙特卡洛仿真
fprintf('开始仿真（%d次重复）...\n', config.n_replications);
results = monte_carlo_simulation(params, config);

%% 结果分析
stats = analyze_results(results);
display_results(stats);
visualize_results(results, stats);

%% 保存结果
save('problem2_complete_results.mat', 'results', 'stats', 'params', 'config');


%% ============ 核心函数实现 ============

function params = initialize_complete_parameters()
    % 初始化所有参数
    
    % 子系统固有问题概率
    params.p0 = struct();
    params.p0.A = 0.025;
    params.p0.B = 0.030;
    params.p0.C = 0.020;
    params.p0.D = 0.001;
    
    % 测手差错率
    params.e = struct();
    params.e.A = 0.03;
    params.e.B = 0.04;
    params.e.C = 0.02;
    params.e.E = 0.02;
    
    % 测试时间（小时）
    params.test_time = struct();
    params.test_time.A = 2.5;
    params.test_time.B = 2.0;
    params.test_time.C = 2.5;
    params.test_time.E = 3.0;
    
    % 调试时间（小时）
    params.setup_time = struct();
    params.setup_time.A = 0.5;
    params.setup_time.B = 20/60;
    params.setup_time.C = 20/60;
    params.setup_time.E = 40/60;
    
    % 运输时间
    params.transport_time = 0.5;
    
    % 设备故障参数（累计概率）
    params.failure = struct();
    params.failure.r1 = struct('A', 0.03, 'B', 0.04, 'C', 0.02, 'E', 0.03);
    params.failure.r2 = struct('A', 0.05, 'B', 0.07, 'C', 0.06, 'E', 0.05);
    
    % 成本参数（用于设备更换决策）
    stations = {'A', 'B', 'C', 'E'};
    for i = 1:length(stations)
        s = stations{i};
        params.cost.failure.(s)  = params.setup_time.(s) + 0.5 * params.test_time.(s);
        params.cost.replace.(s)  = params.setup_time.(s);
    end
end

function results = monte_carlo_simulation(params, config)
    % 蒙特卡洛仿真主函数
    
    results = struct();
    results.T   = zeros(config.n_replications, 1);
    results.S   = zeros(config.n_replications, 1);
    results.PL  = zeros(config.n_replications, 1);
    results.PW  = zeros(config.n_replications, 1);
    results.YXB = zeros(config.n_replications, 4);
    
    for rep = 1:config.n_replications
        if config.verbose && mod(rep, 10) == 0
            fprintf('  完成 %d/%d\n', rep, config.n_replications);
        end
        sim_result = run_single_simulation(params, config);
        results.T(rep)      = sim_result.completion_days;
        results.S(rep)      = sim_result.n_passed;
        results.PL(rep)     = sim_result.miss_rate;
        results.PW(rep)     = sim_result.false_rate;
        results.YXB(rep, :) = sim_result.efficiency;
    end
end

function result = run_single_simulation(params, config)
    % 单次仿真实现
    
    devices = initialize_devices(config.n_devices, params);
    sys     = initialize_system(params, config);
    
    while sys.n_completed < config.n_devices && sys.current_day <= config.max_days
        % 新的一天开始
        sys = start_new_shift(sys, params);
        
        % 班次内仿真
        while sys.shift_time < config.hours_per_shift
            % 取下一事件（若事件发生时间超过本班剩余时间，则本班内无事件）
            [sys, event] = get_next_event(sys, config);
            
            if ~isempty(event)
                [sys, devices] = process_event(sys, devices, event, params);
            end
            
            % 调度新测试（分配工位/决定是否开测）
            [sys, devices] = schedule_tests(sys, devices, params, config);
            
            % 设备预防性更换（空闲且必要时）
            sys = check_equipment_replacement(sys, params);
            
            % 如果当前无事件且无法调度新测试，则快进到班末
            if isempty(sys.event_queue)
                % 所有测试台都空闲且无占用工位 => 可以跳到班末
                benches_free = ~sys.benches(1).occupied && ~sys.benches(2).occupied;
                stations_free = true;
                stations = {'A','B','C','E'};
                for ii=1:numel(stations)
                    stations_free = stations_free && ~sys.stations.(stations{ii}).occupied;
                end
                if benches_free && stations_free
                    sys.shift_time = config.hours_per_shift; % 直接结束本班
                else
                    % 仍有在途/运输中的设备，微步前进以触发运输完成等
                    sys.shift_time = min(config.hours_per_shift, sys.shift_time + 0.5);
                    sys.total_time = sys.total_time + 0.5; % 同步推进全局时间
                end
            end
        end
        
        % 班次结束处理
        [sys, devices] = handle_shift_end(sys, devices, params);
        sys.current_day = sys.current_day + 1;
    end
    
    % 计算性能指标
    result = calculate_metrics(devices, sys);
end

function devices = initialize_devices(n, params)
    % 初始化装置状态
    devices = struct([]);
    for i = n:-1:1
        devices(i).id = i;
        % 真实问题状态
        devices(i).true_problems = struct();
        devices(i).true_problems.A = rand() < params.p0.A;
        devices(i).true_problems.B = rand() < params.p0.B;
        devices(i).true_problems.C = rand() < params.p0.C;
        devices(i).true_problems.D = rand() < params.p0.D;
        devices(i).has_any_problem = devices(i).true_problems.A || ...
                                     devices(i).true_problems.B || ...
                                     devices(i).true_problems.C || ...
                                     devices(i).true_problems.D;
        % 先验
        devices(i).prob_estimates = struct();
        devices(i).prob_estimates.A = params.p0.A;
        devices(i).prob_estimates.B = params.p0.B;
        devices(i).prob_estimates.C = params.p0.C;
        devices(i).prob_estimates.D = params.p0.D;
        % 测试状态
        devices(i).test_passed    = struct('A', false, 'B', false, 'C', false, 'E', false);
        devices(i).test_attempts  = struct('A', 0, 'B', 0, 'C', 0, 'E', 0);
        devices(i).test_time_used = struct('A', 0, 'B', 0, 'C', 0, 'E', 0); % 这里保留接口
        % 装置状态
        devices(i).status       = 'waiting'; % waiting/arriving/testing/passed/failed
        devices(i).location     = 'queue';
        devices(i).current_test = '';
    end
end

function sys = initialize_system(params, config)
    % 初始化系统状态
    sys = struct();
    sys.current_day = 1;
    sys.shift_time  = 0;
    sys.total_time  = 0;
    sys.n_completed = 0;
    % 测试台（两台）
    sys.benches = struct('occupied', {false, false}, 'device_id', {0, 0});
    % 工位状态
    stations = {'A','B','C','E'};
    for i = 1:length(stations)
        s = stations{i};
        sys.stations.(s) = struct();
        sys.stations.(s).occupied           = false;
        sys.stations.(s).device_id          = 0;
        sys.stations.(s).equipment_life     = 0;     % 已使用工时
        sys.stations.(s).next_failure_usage = sample_next_failure_usage(params, s);
        sys.stations.(s).test_start_time    = 0;
        sys.stations.(s).work_time          = 0;     % 统计有效工时
    end
    % 事件队列（统一字段）
    sys.event_queue = struct('type', {}, 'time', {}, 'device_id', {}, 'station', {});
end

function th = sample_next_failure_usage(params, s)
    % 采样"下一次故障发生的使用工时阈值"（基于累计概率）
    u  = rand;
    r1 = params.failure.r1.(s);
    r2 = params.failure.r2.(s);
    if u < r1
        th = 120 * rand;         % [0,120]
    elseif u < r2
        th = 120 + 120 * rand;   % (120,240]
    else
        th = inf;                % 240 小时内不坏
    end
end

function sys = push_event(sys, ev)
    % 将事件按时间有序插入队列
    if isempty(sys.event_queue)
        sys.event_queue = ev; return;
    end
    t = [sys.event_queue.time];
    k = find(ev.time < t, 1, 'first');
    if isempty(k)
        sys.event_queue(end+1) = ev;
    else
        sys.event_queue = [sys.event_queue(1:k-1) ev sys.event_queue(k:end)];
    end
end

function [sys, event] = pop_event_if_within_shift(sys, config)
    % 若队首事件在本班剩余时间内，则弹出；否则返回空
    event = [];
    if isempty(sys.event_queue), return; end
    ev = sys.event_queue(1);
    latest_time_this_shift = sys.total_time + (config.hours_per_shift - sys.shift_time);
    if ev.time <= latest_time_this_shift
        event = ev;
        sys.event_queue(1) = [];
        % 时间推进到事件发生时刻
        dt = event.time - sys.total_time;
        sys.shift_time = sys.shift_time + dt;
        sys.total_time = event.time;
    end
end

function [sys, event] = get_next_event(sys, config)
    % 兼容接口：取下一可在本班内发生的事件
    [sys, event] = pop_event_if_within_shift(sys, config);
end

function [sys, devices] = process_event(sys, devices, event, params)
    % 处理事件
    switch event.type
        case 'test_complete'
            [sys, devices] = handle_test_complete(sys, devices, event, params);
        case 'equipment_failure'
            [sys, devices] = handle_equipment_failure(sys, devices, event, params);
        case 'transport_complete'
            % 运输完成，装置到达测试台，状态从 arriving -> testing
            devices(event.device_id).status = 'testing';
        otherwise
            % no-op
    end
end

function [sys, devices] = handle_test_complete(sys, devices, event, params)
    % 测试完成（包含贝叶斯更新）
    device_id = event.device_id;
    station   = event.station;
    
    % 生成测试结果
    test_result = generate_test_result(devices(device_id), station, params);
    
    % 贝叶斯更新
    devices(device_id) = bayesian_update(devices(device_id), station, test_result, params);
    
    % 更新尝试次数
    devices(device_id).test_attempts.(station) = devices(device_id).test_attempts.(station) + 1;
    
    if test_result
        devices(device_id).test_passed.(station) = true;
        if strcmp(station, 'E')
            % 全流程通过
            devices(device_id).status = 'passed';
            sys.n_completed = sys.n_completed + 1;
            % 释放测试台
            for b = 1:2
                if sys.benches(b).device_id == device_id
                    sys.benches(b).occupied = false; sys.benches(b).device_id = 0; break;
                end
            end
        end
    else
        if devices(device_id).test_attempts.(station) >= 2
            % 连续两次失败则淘汰
            devices(device_id).status = 'failed';
            sys.n_completed = sys.n_completed + 1;
            for b = 1:2
                if sys.benches(b).device_id == device_id
                    sys.benches(b).occupied = false; sys.benches(b).device_id = 0; break;
                end
            end
        end
    end
    
    % 释放工位
    sys.stations.(station).occupied  = false;
    sys.stations.(station).device_id = 0;
    
    % 更新设备使用工时与有效工时（本次测试完整完成）
    test_time = params.test_time.(station);
    sys.stations.(station).work_time      = sys.stations.(station).work_time + test_time;
    sys.stations.(station).equipment_life = sys.stations.(station).equipment_life + test_time;
    
    % 清零测试时间/标记未在测
    devices(device_id).test_time_used.(station) = 0;
    devices(device_id).current_test = '';
end

function [sys, devices] = handle_equipment_failure(sys, devices, event, params)
    % 设备故障：按"使用工时"触发；中断测试不得接续
    s  = event.station;
    id = sys.stations.(s).device_id;
    if id == 0
        % 极少数边界：事件到来时已被释放（理论上不会发生）
        return;
    end
    
    % 计算从测试开始到故障的已用时，并计入工时与使用寿命
    elapsed = sys.total_time - sys.stations.(s).test_start_time;
    if elapsed < 0, elapsed = 0; end
    sys.stations.(s).work_time      = sys.stations.(s).work_time + elapsed;
    sys.stations.(s).equipment_life = sys.stations.(s).equipment_life + elapsed;
    
    % 中断：清零该工序已用时间，不得接续；释放工位
    devices(id).test_time_used.(s) = 0;
    devices(id).current_test       = '';
    sys.stations.(s).occupied      = false;
    sys.stations.(s).device_id     = 0;
    
    % 立即更换设备（含调试时间）并重采样下一次故障阈值
    sys = replace_equipment(sys, s, params);
end

function test_result = generate_test_result(device, station, params)
    % 生成测试结果（基于真实状态与误判/漏判概率）
    if strcmp(station, 'E')
        % 综合测试
        has_problem = device.has_any_problem;
        p_any  = 1 - (1-device.prob_estimates.A) * (1-device.prob_estimates.B) * ...
                     (1-device.prob_estimates.C) * (1-device.prob_estimates.D);
        alpha_E = (0.5 * params.e.E) / max(p_any, 0.001);
        beta_E  = (0.5 * params.e.E) / max(1-p_any, 0.001);
        if has_problem
            test_result = rand() < alpha_E;      % 漏判（错误地通过）
        else
            test_result = rand() >= beta_E;      % 正确通过或误判
        end
    else
        % A/B/C 工位
        has_problem = device.true_problems.(station);
        prior = device.prob_estimates.(station);
        alpha = (0.5 * params.e.(station)) / max(prior, 0.001);
        beta  = (0.5 * params.e.(station)) / max(1-prior, 0.001);
        if has_problem
            test_result = rand() < alpha;        % 漏判
        else
            test_result = rand() >= beta;        % 正确或误判
        end
    end
end

function device = bayesian_update(device, station, test_result, params)
    % 贝叶斯概率更新（E 工位不更新单项概率）
    if ~strcmp(station, 'E')
        prior = device.prob_estimates.(station);
        alpha = (0.5 * params.e.(station)) / max(prior, 0.001);
        beta  = (0.5 * params.e.(station)) / max(1-prior, 0.001);
        if test_result         % 通过
            posterior = (prior * alpha) / (prior * alpha + (1-prior) * (1-beta));
        else                   % 未通过
            posterior = (prior * (1-alpha)) / (prior * (1-alpha) + (1-prior) * beta);
        end
        device.prob_estimates.(station) = posterior;
    end
end

function sys = check_equipment_replacement(sys, params)
    % 空闲时按期望损失预防性更换
    stations = {'A','B','C','E'};
    for i = 1:length(stations)
        s = stations{i};
        L = sys.stations.(s).equipment_life;
        if L >= 240
            sys = replace_equipment(sys, s, params);
        elseif L >= 120 && L < 240 && ~sys.stations.(s).occupied
            r1 = params.failure.r1.(s);
            r2 = params.failure.r2.(s);
            C_failure = params.cost.failure.(s);
            C_replace = params.cost.replace.(s);
            dL_dt = (r2 - r1) / 120 * (C_failure - C_replace);
            if dL_dt > 0
                sys = replace_equipment(sys, s, params);
            end
        end
    end
end

function sys = replace_equipment(sys, station, params)
    % 执行设备更换（含调试时间 & 重采样故障阈值）
    sys.stations.(station).equipment_life     = 0;
    sys.stations.(station).next_failure_usage = sample_next_failure_usage(params, station);
    sys.shift_time = sys.shift_time + params.setup_time.(station);
end

function [sys, devices] = schedule_tests(sys, devices, params, config)
    % 调度新测试：给在测试台的装置分配 A/B/C/E 工位
    
    % 先给已在测试台且 ready 的装置开测
    for b = 1:2
        if sys.benches(b).occupied
            device_id = sys.benches(b).device_id;
            if strcmp(devices(device_id).status, 'testing') && isempty(devices(device_id).current_test)
                next_test = get_next_test(devices(device_id));
                if ~isempty(next_test) && ~sys.stations.(next_test).occupied
                    remaining = config.hours_per_shift - sys.shift_time;
                    required  = params.test_time.(next_test); % 未使用分段，直接完整时长
                    if remaining >= required + config.buffer_time
                        sys = start_test(sys, devices, device_id, next_test, params);
                        devices(device_id).current_test = next_test;
                    end
                end
            end
        end
    end
    
    % 将队列中的 waiting 装置放到空闲测试台（并产生运输事件）
    for i = 1:length(devices)
        if strcmp(devices(i).status, 'waiting')
            for b = 1:2
                if ~sys.benches(b).occupied
                    sys.benches(b).occupied = true;
                    sys.benches(b).device_id = i;
                    devices(i).status   = 'arriving';           % 先标记为到达中
                    devices(i).location = sprintf('bench_%d', b);
                    % 运输完成事件
                    ev = struct('type','transport_complete', ...
                                'time', sys.total_time + params.transport_time, ...
                                'device_id', i, 'station','');
                    sys = push_event(sys, ev);
                    break;
                end
            end
        end
    end
end

function next_test = get_next_test(device)
    % 确定下一个需要的测试（先 A/B/C 后 E）
    next_test = '';
    tests = {'A','B','C'};
    for i = 1:length(tests)
        t = tests{i};
        if ~device.test_passed.(t) && device.test_attempts.(t) < 2
            next_test = t; return;
        end
    end
    if device.test_passed.A && device.test_passed.B && device.test_passed.C
        if ~device.test_passed.E && device.test_attempts.E < 2
            next_test = 'E';
        end
    end
end

function sys = start_test(sys, devices, device_id, station, params)
    % 开始测试：根据"距离故障的剩余可用工时"决定排哪个事件
    sys.stations.(station).occupied        = true;
    sys.stations.(station).device_id       = device_id;
    sys.stations.(station).test_start_time = sys.total_time;
    
    life_used = sys.stations.(station).equipment_life;
    remaining_to_fail = sys.stations.(station).next_failure_usage - life_used;
    test_time = params.test_time.(station);
    
    if test_time > remaining_to_fail
        % 故障先发生
        ev = struct('type','equipment_failure', ...
                    'time', sys.total_time + remaining_to_fail, ...
                    'device_id', device_id, 'station', station);
    else
        % 正常完成
        ev = struct('type','test_complete', ...
                    'time', sys.total_time + test_time, ...
                    'device_id', device_id, 'station', station);
    end
    sys = push_event(sys, ev);
end

function [sys, devices] = handle_shift_end(sys, devices, params)
    % 班次结束处理（理论上由于 buffer_time 限制，很少有仍占用的工位）
    stations = {'A','B','C','E'};
    for i = 1:length(stations)
        s = stations{i};
        if sys.stations.(s).occupied
            device_id = sys.stations.(s).device_id;
            % 计算已测时间
            elapsed = sys.shift_time - (sys.stations.(s).test_start_time - ...
                      (sys.total_time - sys.shift_time));
            if elapsed < params.test_time.(s)
                % 未完成，清零（不得接续）
                devices(device_id).test_time_used.(s) = 0;
            end
            devices(device_id).current_test = '';
            % 释放工位
            sys.stations.(s).occupied  = false;
            sys.stations.(s).device_id = 0;
        end
    end
    % 班末不做额外时间前移，下一班由 start_new_shift 处理
end

function sys = start_new_shift(sys, params)
    % 开始新班次
    sys.shift_time = 0;
    % 第一天设备调试
    if sys.current_day == 1
        stations = {'A','B','C','E'};
        for i = 1:length(stations)
            s = stations{i};
            sys.shift_time = sys.shift_time + params.setup_time.(s);
        end
    end
end

function result = calculate_metrics(devices, sys)
    % 计算性能指标
    result = struct();
    % T: 完成天数
    result.completion_days = sys.current_day - 1;
    % S: 通过数量
    pass_idx = strcmp({devices.status}, 'passed');
    result.n_passed = sum(pass_idx);
    % P_L: 漏判概率（通过但仍有真实问题）
    passed_devices = devices(pass_idx);
    if ~isempty(passed_devices)
        n_missed = sum([passed_devices.has_any_problem]);
        result.miss_rate = n_missed / numel(passed_devices);
    else
        result.miss_rate = 0;
    end
    % P_W: 误判概率（判失败但其实没问题）
    fail_idx = strcmp({devices.status}, 'failed');
    failed_devices = devices(fail_idx);
    if ~isempty(failed_devices)
        n_false = sum(~[failed_devices.has_any_problem]);
        result.false_rate = n_false / numel(failed_devices);
    else
        result.false_rate = 0;
    end
    % YXB: 有效工时比
    total_hours = max(1, result.completion_days) * 12;
    stations = {'A','B','C','E'};
    result.efficiency = zeros(1, 4);
    for i = 1:4
        result.efficiency(i) = sys.stations.(stations{i}).work_time / total_hours;
    end
end

function stats = analyze_results(results)
    % 统计分析
    stats = struct();
    stats.T_mean   = mean(results.T);
    stats.T_std    = std(results.T);
    stats.S_mean   = mean(results.S);
    stats.S_std    = std(results.S);
    stats.PL_mean  = mean(results.PL);
    stats.PL_std   = std(results.PL);
    stats.PW_mean  = mean(results.PW);
    stats.PW_std   = std(results.PW);
    stats.YXB_mean = mean(results.YXB, 1);
    stats.YXB_std  = std(results.YXB, 0, 1);
end

function display_results(stats)
    % 显示结果
    fprintf('\n========== 仿真结果 ==========\n');
    fprintf('任务完成天数 T: %.2f ± %.2f\n', stats.T_mean, stats.T_std);
    fprintf('通过装置数 S: %.2f ± %.2f\n', stats.S_mean, stats.S_std);
    fprintf('总漏判概率 P_L: %.4f ± %.4f\n', stats.PL_mean, stats.PL_std);
    fprintf('总误判概率 P_W: %.4f ± %.4f\n', stats.PW_mean, stats.PW_std);
    fprintf('有效工时比 YXB:\n');
    fprintf('  A: %.3f ± %.3f\n', stats.YXB_mean(1), stats.YXB_std(1));
    fprintf('  B: %.3f ± %.3f\n', stats.YXB_mean(2), stats.YXB_std(2));
    fprintf('  C: %.3f ± %.3f\n', stats.YXB_mean(3), stats.YXB_std(3));
    fprintf('  E: %.3f ± %.3f\n', stats.YXB_mean(4), stats.YXB_std(4));
    fprintf('==============================\n');
end

function visualize_results(results, stats)
    % 可视化结果
    figure('Position', [100, 100, 1200, 800]);
    % 子图1：完成天数分布
    subplot(2,3,1);
    histogram(results.T, 20);
    xlabel('完成天数'); ylabel('频数');
    title(sprintf('T分布 (μ=%.1f, σ=%.1f)', stats.T_mean, stats.T_std));
    % 子图2：通过数量分布
    subplot(2,3,2);
    histogram(results.S, 15);
    xlabel('通过装置数'); ylabel('频数');
    title(sprintf('S分布 (μ=%.1f, σ=%.1f)', stats.S_mean, stats.S_std));
    % 子图3：漏判概率
    subplot(2,3,3);
    histogram(results.PL, 20);
    xlabel('漏判概率'); ylabel('频数');
    title(sprintf('P_L分布 (μ=%.3f)', stats.PL_mean));
    % 子图4：误判概率
    subplot(2,3,4);
    histogram(results.PW, 20);
    xlabel('误判概率'); ylabel('频数');
    title(sprintf('P_W分布 (μ=%.3f)', stats.PW_mean));
    % 子图5：效率对比
    subplot(2,3,5);
    bar(stats.YXB_mean); hold on;
    errorbar(1:4, stats.YXB_mean, stats.YXB_std, 'k.');
    xlabel('工位'); ylabel('有效工时比'); title('YXB对比');
    set(gca, 'XTickLabel', {'A','B','C','E'});
    % 子图6：收敛性
    subplot(2,3,6);
    plot(cumsum(results.T)./(1:length(results.T))');
    xlabel('仿真次数'); ylabel('累积平均完成天数'); title('收敛性分析'); grid on;
    sgtitle('问题2仿真结果分析');
end
