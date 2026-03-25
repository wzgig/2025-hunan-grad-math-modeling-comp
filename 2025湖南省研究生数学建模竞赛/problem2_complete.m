%% 问题2完整实现：基于贝叶斯更新的测试任务规划
% 包含完整的数学模型实现

clear; clc; close all;

%% 参数初始化
params = initialize_complete_parameters();

%% 仿真配置
config = struct();
config.n_devices = 100;
config.n_replications = 100;
config.max_days = 50;
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
    
    % 设备故障参数
    params.failure = struct();
    params.failure.r1 = struct('A', 0.03, 'B', 0.04, 'C', 0.02, 'E', 0.03);
    params.failure.r2 = struct('A', 0.05, 'B', 0.07, 'C', 0.06, 'E', 0.05);
    
    % 计算成本参数（用于设备更换决策）
    stations = {'A', 'B', 'C', 'E'};
    for i = 1:length(stations)
        s = stations{i};
        params.cost.failure.(s) = params.setup_time.(s) + 0.5 * params.test_time.(s);
        params.cost.replace.(s) = params.setup_time.(s);
    end
end

function results = monte_carlo_simulation(params, config)
    % 蒙特卡洛仿真主函数
    
    results = struct();
    results.T = zeros(config.n_replications, 1);
    results.S = zeros(config.n_replications, 1);
    results.PL = zeros(config.n_replications, 1);
    results.PW = zeros(config.n_replications, 1);
    results.YXB = zeros(config.n_replications, 4);
    
    for rep = 1:config.n_replications
        if config.verbose && mod(rep, 10) == 0
            fprintf('  完成 %d/%d\n', rep, config.n_replications);
        end
        
        % 运行单次仿真
        sim_result = run_single_simulation(params, config);
        
        % 记录结果
        results.T(rep) = sim_result.completion_days;
        results.S(rep) = sim_result.n_passed;
        results.PL(rep) = sim_result.miss_rate;
        results.PW(rep) = sim_result.false_rate;
        results.YXB(rep, :) = sim_result.efficiency;
    end
end

function result = run_single_simulation(params, config)
    % 单次仿真实现
    
    % 初始化装置
    devices = initialize_devices(config.n_devices, params);
    
    % 初始化系统状态
    sys = initialize_system(params, config);
    
    % 仿真主循环
    while sys.n_completed < config.n_devices && sys.current_day <= config.max_days
        % 新的一天开始
        sys = start_new_shift(sys, params);
        
        % 班次内仿真
        while sys.shift_time < config.hours_per_shift
            % 处理事件队列
            [sys, event] = get_next_event(sys, config);
            
            if ~isempty(event)
                % 处理事件
                [sys, devices] = process_event(sys, devices, event, params);
            end
            
            % 调度新测试
            event = struct('type', 'transport_complete', ...
               'time', sys.total_time + params.transport_time, ...
               'device_id', i, ...
               'station', '');    % 统一字段：没有工位就设为空字符串
            sys.event_queue(end+1) = event;    % 用 end+1 追加更直观
            
            % 检查设备更换
            sys = check_equipment_replacement(sys, params);
            
            % 时间推进
            if isempty(sys.event_queue)
                sys.shift_time = sys.shift_time + 0.1;
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
    
    for i = n:-1:1
        % 生成真实问题状态
        devices(i).id = i;
        devices(i).true_problems = struct();
        devices(i).true_problems.A = rand() < params.p0.A;
        devices(i).true_problems.B = rand() < params.p0.B;
        devices(i).true_problems.C = rand() < params.p0.C;
        devices(i).true_problems.D = rand() < params.p0.D;
        devices(i).has_any_problem = devices(i).true_problems.A || ...
                                     devices(i).true_problems.B || ...
                                     devices(i).true_problems.C || ...
                                     devices(i).true_problems.D;
        
        % 初始化概率估计（贝叶斯先验）
        devices(i).prob_estimates = struct();
        devices(i).prob_estimates.A = params.p0.A;
        devices(i).prob_estimates.B = params.p0.B;
        devices(i).prob_estimates.C = params.p0.C;
        devices(i).prob_estimates.D = params.p0.D;
        
        % 测试状态
        devices(i).test_passed = struct('A', false, 'B', false, 'C', false, 'E', false);
        devices(i).test_attempts = struct('A', 0, 'B', 0, 'C', 0, 'E', 0);
        devices(i).test_time_used = struct('A', 0, 'B', 0, 'C', 0, 'E', 0);
        
        % 装置状态
        devices(i).status = 'waiting';
        devices(i).location = 'queue';
        devices(i).current_test = '';
    end
end

function sys = initialize_system(params, config)
    % 初始化系统状态
    
    sys = struct();
    sys.current_day = 1;
    sys.shift_time = 0;
    sys.total_time = 0;
    sys.n_completed = 0;
    
    % 测试台
    sys.benches = struct('occupied', {false, false}, 'device_id', {0, 0});
    
    % 工位状态
    stations = {'A', 'B', 'C', 'E'};
    for i = 1:length(stations)
        s = stations{i};
        sys.stations.(s) = struct();
        sys.stations.(s).occupied = false;
        sys.stations.(s).device_id = 0;
        sys.stations.(s).equipment_life = 0;
        sys.stations.(s).test_start_time = 0;
        sys.stations.(s).work_time = 0;
    end
    
    % 事件队列
    sys.event_queue = struct('type', {}, 'time', {}, 'device_id', {}, 'station', {});
end

function [sys, devices] = process_event(sys, devices, event, params)
    % 处理事件
    
    switch event.type
        case 'test_complete'
            [sys, devices] = handle_test_complete(sys, devices, event, params);
            
        case 'equipment_failure'
            sys = handle_equipment_failure(sys, event);
            
        case 'transport_complete'
            % 运输完成，装置可以开始测试
    end
end

function [sys, devices] = handle_test_complete(sys, devices, event, params)
    % 处理测试完成事件（包含贝叶斯更新）
    
    device_id = event.device_id;
    station = event.station;
    
    % 生成测试结果
    test_result = generate_test_result(devices(device_id), station, params);
    
    % 贝叶斯概率更新
    devices(device_id) = bayesian_update(devices(device_id), station, test_result, params);
    
    % 更新测试状态
    devices(device_id).test_attempts.(station) = devices(device_id).test_attempts.(station) + 1;
    
    if test_result
        devices(device_id).test_passed.(station) = true;
        
        if strcmp(station, 'E')
            % 通过所有测试
            devices(device_id).status = 'passed';
            sys.n_completed = sys.n_completed + 1;
            % 释放测试台
            for b = 1:2
                if sys.benches(b).device_id == device_id
                    sys.benches(b).occupied = false;
                    sys.benches(b).device_id = 0;
                    break;
                end
            end
        end
    else
        if devices(device_id).test_attempts.(station) >= 2
            % 连续两次失败
            devices(device_id).status = 'failed';
            sys.n_completed = sys.n_completed + 1;
            % 释放测试台
            for b = 1:2
                if sys.benches(b).device_id == device_id
                    sys.benches(b).occupied = false;
                    sys.benches(b).device_id = 0;
                    break;
                end
            end
        end
    end
    
    % 释放工位
    sys.stations.(station).occupied = false;
    sys.stations.(station).device_id = 0;
    
    % 更新工时
    test_time = params.test_time.(station);
    sys.stations.(station).work_time = sys.stations.(station).work_time + test_time;
    sys.stations.(station).equipment_life = sys.stations.(station).equipment_life + test_time;
    
    % 清零测试时间
    devices(device_id).test_time_used.(station) = 0;
    devices(device_id).current_test = '';
end

function test_result = generate_test_result(device, station, params)
    % 生成测试结果（基于真实状态和误判/漏判概率）
    
    if strcmp(station, 'E')
        % E工位：综合测试
        has_problem = device.has_any_problem;
        
        % 计算E工位的动态参数
        p_any = 1 - (1-device.prob_estimates.A) * (1-device.prob_estimates.B) * ...
                    (1-device.prob_estimates.C) * (1-device.prob_estimates.D);
        alpha_E = (0.5 * params.e.E) / max(p_any, 0.001);
        beta_E = (0.5 * params.e.E) / max(1-p_any, 0.001);
        
        if has_problem
            test_result = rand() < alpha_E;  % 漏判
        else
            test_result = rand() >= beta_E;  % 正确或误判
        end
    else
        % A/B/C工位
        has_problem = device.true_problems.(station);
        
        % 计算动态的alpha和beta
        prior = device.prob_estimates.(station);
        alpha = (0.5 * params.e.(station)) / max(prior, 0.001);
        beta = (0.5 * params.e.(station)) / max(1-prior, 0.001);
        
        if has_problem
            test_result = rand() < alpha;  % 漏判
        else
            test_result = rand() >= beta;  % 正确或误判
        end
    end
end

function device = bayesian_update(device, station, test_result, params)
    % 贝叶斯概率更新
    
    if ~strcmp(station, 'E')  % E工位不需要更新单个子系统概率
        prior = device.prob_estimates.(station);
        
        % 计算当前的alpha和beta
        alpha = (0.5 * params.e.(station)) / max(prior, 0.001);
        beta = (0.5 * params.e.(station)) / max(1-prior, 0.001);
        
        % 贝叶斯更新
        if test_result  % 通过
            posterior = (prior * alpha) / (prior * alpha + (1-prior) * (1-beta));
        else  % 未通过
            posterior = (prior * (1-alpha)) / (prior * (1-alpha) + (1-prior) * beta);
        end
        
        device.prob_estimates.(station) = posterior;
    end
end

function sys = check_equipment_replacement(sys, params)
    % 检查并执行设备更换（基于期望损失）
    
    stations = {'A', 'B', 'C', 'E'};
    
    for i = 1:length(stations)
        s = stations{i};
        L = sys.stations.(s).equipment_life;
        
        if L >= 240
            % 强制更换
            sys = replace_equipment(sys, s, params);
        elseif L >= 120 && L < 240 && ~sys.stations.(s).occupied
            % 计算期望损失变化率
            r1 = params.failure.r1.(s);
            r2 = params.failure.r2.(s);
            C_failure = params.cost.failure.(s);
            C_replace = params.cost.replace.(s);
            
            dL_dt = (r2 - r1) / 120 * (C_failure - C_replace);
            
            if dL_dt > 0
                % 预防性更换
                sys = replace_equipment(sys, s, params);
            end
        end
    end
end

function sys = replace_equipment(sys, station, params)
    % 执行设备更换
    
    sys.stations.(station).equipment_life = 0;
    sys.shift_time = sys.shift_time + params.setup_time.(station);
end

function [sys, devices] = schedule_tests(sys, devices, params, config)
    % 调度新测试
    
    % 为测试台上的装置分配工位
    for b = 1:2
        if sys.benches(b).occupied
            device_id = sys.benches(b).device_id;
            
            if isempty(devices(device_id).current_test) && ...
               strcmp(devices(device_id).status, 'testing')
                
                % 确定下一个测试
                next_test = get_next_test(devices(device_id));
                
                if ~isempty(next_test) && ~sys.stations.(next_test).occupied
                    % 检查剩余时间
                    remaining = config.hours_per_shift - sys.shift_time;
                    required = params.test_time.(next_test) - devices(device_id).test_time_used.(next_test);
                    
                    if remaining >= required + config.buffer_time
                        % 开始测试
                        sys = start_test(sys, devices, device_id, next_test, params);
                        devices(device_id).current_test = next_test;
                    end
                end
            end
        end
    end
    
    % 将等待装置分配到空闲测试台
    for i = 1:length(devices)
        if strcmp(devices(i).status, 'waiting')
            for b = 1:2
                if ~sys.benches(b).occupied
                    sys.benches(b).occupied = true;
                    sys.benches(b).device_id = i;
                    devices(i).status = 'testing';
                    devices(i).location = sprintf('bench_%d', b);
                    
                    % 添加运输时间
                    event = struct();
                    event.type = 'transport_complete';
                    event.device_id = i;
                    event.time = sys.total_time + params.transport_time;
                    sys.event_queue = [sys.event_queue, event];
                    break;
                end
            end
        end
    end
end

function next_test = get_next_test(device)
    % 确定下一个需要的测试
    
    next_test = '';
    
    % 检查A/B/C
    tests = {'A', 'B', 'C'};
    for i = 1:length(tests)
        t = tests{i};
        if ~device.test_passed.(t) && device.test_attempts.(t) < 2
            next_test = t;
            return;
        end
    end
    
    % 检查E
    if device.test_passed.A && device.test_passed.B && device.test_passed.C
        if ~device.test_passed.E && device.test_attempts.E < 2
            next_test = 'E';
        end
    end
end

function sys = start_test(sys, devices, device_id, station, params)
    % 开始测试
    
    sys.stations.(station).occupied = true;
    sys.stations.(station).device_id = device_id;
    sys.stations.(station).test_start_time = sys.total_time;
    
    % 创建完成事件
    test_time = params.test_time.(station) - devices(device_id).test_time_used.(station);
    event = struct('type', 'test_complete', ...
                   'time', sys.total_time + test_time, ...
                   'device_id', device_id, ...
                   'station', station);
    sys.event_queue(end+1) = event;
end

function [sys, devices] = handle_shift_end(sys, devices, params)
    % 班次结束处理
    stations = {'A', 'B', 'C', 'E'};
    for i = 1:length(stations)
        s = stations{i};
        if sys.stations.(s).occupied
            device_id = sys.stations.(s).device_id;

            % 计算已测时间
            elapsed = sys.shift_time - (sys.stations.(s).test_start_time - ...
                      (sys.total_time - sys.shift_time));

            % 判断是否完成
            if elapsed < params.test_time.(s)
                % 未完成，清零累计的已用测试时间
                devices(device_id).test_time_used.(s) = 0;
            end

            devices(device_id).current_test = '';

            % 释放工位
            sys.stations.(s).occupied = false;
            sys.stations.(s).device_id = 0;
        end
    end
end


function sys = start_new_shift(sys, params)
    % 开始新班次
    sys.shift_time = 0;

    % 第一天设备调试
    if sys.current_day == 1
        stations = {'A', 'B', 'C', 'E'};
        for i = 1:length(stations)
            s = stations{i};
            sys.shift_time = sys.shift_time + params.setup_time.(s);
        end
    end
end


function [sys, event] = get_next_event(sys, config)
    % 获取下一个事件
    event = [];
    if isempty(sys.event_queue), return; end

    % 找最早事件
    [~, idx] = min([sys.event_queue.time]);

    if sys.event_queue(idx).time <= sys.total_time + (config.hours_per_shift - sys.shift_time)
        event = sys.event_queue(idx);
        sys.event_queue(idx) = [];

        time_advance = event.time - sys.total_time;
        sys.shift_time = sys.shift_time + time_advance;
        sys.total_time = event.time;
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
    
    % P_L: 漏判概率
    passed_devices = devices(pass_idx);
    if ~isempty(passed_devices)
        n_missed = sum([passed_devices.has_any_problem]);
        result.miss_rate = n_missed / numel(passed_devices);
    else
        result.miss_rate = 0;
    end
    
    
    % P_W: 误判概率
    fail_idx = strcmp({devices.status}, 'failed');
    failed_devices = devices(fail_idx);
    if ~isempty(failed_devices)
        n_false = sum(~[failed_devices.has_any_problem]);
        result.false_rate = n_false / numel(failed_devices);
    else
        result.false_rate = 0;
    end
    
    % YXB: 有效工时比
    total_hours = result.completion_days * 12;
    stations = {'A', 'B', 'C', 'E'};
    result.efficiency = zeros(1, 4);
    for i = 1:4
        result.efficiency(i) = sys.stations.(stations{i}).work_time / total_hours;
    end
end

function stats = analyze_results(results)
    % 统计分析
    
    stats = struct();
    stats.T_mean = mean(results.T);
    stats.T_std = std(results.T);
    stats.S_mean = mean(results.S);
    stats.S_std = std(results.S);
    stats.PL_mean = mean(results.PL);
    stats.PL_std = std(results.PL);
    stats.PW_mean = mean(results.PW);
    stats.PW_std = std(results.PW);
    stats.YXB_mean = mean(results.YXB, 1);
    stats.YXB_std = std(results.YXB, 0, 1);
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
    xlabel('完成天数');
    ylabel('频数');
    title(sprintf('T分布 (μ=%.1f, σ=%.1f)', stats.T_mean, stats.T_std));
    
    % 子图2：通过数量分布
    subplot(2,3,2);
    histogram(results.S, 15);
    xlabel('通过装置数');
    ylabel('频数');
    title(sprintf('S分布 (μ=%.1f, σ=%.1f)', stats.S_mean, stats.S_std));
    
    % 子图3：漏判概率
    subplot(2,3,3);
    histogram(results.PL, 20);
    xlabel('漏判概率');
    ylabel('频数');
    title(sprintf('P_L分布 (μ=%.3f)', stats.PL_mean));
    
    % 子图4：误判概率
    subplot(2,3,4);
    histogram(results.PW, 20);
    xlabel('误判概率');
    ylabel('频数');
    title(sprintf('P_W分布 (μ=%.3f)', stats.PW_mean));
    
    % 子图5：效率对比
    subplot(2,3,5);
    bar(stats.YXB_mean);
    hold on;
    errorbar(1:4, stats.YXB_mean, stats.YXB_std, 'k.');
    xlabel('工位');
    ylabel('有效工时比');
    title('YXB对比');
    set(gca, 'XTickLabel', {'A', 'B', 'C', 'E'});
    
    % 子图6：收敛性
    subplot(2,3,6);
    plot(cumsum(results.T)./(1:length(results.T))');
    xlabel('仿真次数');
    ylabel('累积平均完成天数');
    title('收敛性分析');
    grid on;
    
    sgtitle('问题2仿真结果分析');
end