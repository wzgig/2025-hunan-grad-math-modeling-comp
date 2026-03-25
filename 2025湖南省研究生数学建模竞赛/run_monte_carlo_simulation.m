function results = run_monte_carlo_simulation(params, config)
    % 运行蒙特卡洛仿真
    % 输入：
    %   params - 参数结构体
    %   config - 仿真配置
    % 输出：
    %   results - 仿真结果
    
    % 设置随机种子
    rng(config.random_seed);
    
    % 初始化结果存储
    results = struct();
    results.T = zeros(config.n_replications, 1);          % 完成天数
    results.S = zeros(config.n_replications, 1);          % 通过数量
    results.PL = zeros(config.n_replications, 1);         % 漏判概率
    results.PW = zeros(config.n_replications, 1);         % 误判概率
    results.YXB = zeros(config.n_replications, 4);        % 有效工时比
    results.details = cell(config.n_replications, 1);     % 详细信息
    
    % 进度条设置
    if config.verbose
        fprintf('仿真进度：');
        progress_points = round(linspace(1, config.n_replications, 20));
    end
    
    % 运行多次仿真
    for rep = 1:config.n_replications
        % 生成本次仿真的装置问题状态
        devices = generate_device_problems(config.n_devices, params);
        
        % 运行单次仿真
        sim_result = run_single_simulation(devices, params, config);
        
        % 记录结果
        results.T(rep) = sim_result.completion_days;
        results.S(rep) = sim_result.n_passed;
        results.PL(rep) = sim_result.miss_rate;
        results.PW(rep) = sim_result.false_rate;
        results.YXB(rep, :) = sim_result.efficiency;
        results.details{rep} = sim_result;
        
        % 更新进度条
        if config.verbose && ismember(rep, progress_points)
            fprintf('█');
        end
    end
    
    if config.verbose
        fprintf(' 完成！\n');
    end
    
    % 添加汇总信息
    results.summary = struct();
    results.summary.n_replications = config.n_replications;
    results.summary.n_devices = config.n_devices;
    results.summary.completion_rate = mean(results.S) / config.n_devices;
end

function devices = generate_device_problems(n_devices, params)
    % 生成装置的实际问题状态
    
    devices = struct();
    
    for i = 1:n_devices
        devices(i).id = i;
        
        % 生成各子系统的实际问题状态
        devices(i).has_problem.A = rand() < params.p.A;
        devices(i).has_problem.B = rand() < params.p.B;
        devices(i).has_problem.C = rand() < params.p.C;
        devices(i).has_problem.D = rand() < params.p.D;
        
        % 初始化测试状态
        devices(i).test_passed = struct('A', false, 'B', false, 'C', false, 'E', false);
        devices(i).test_attempts = struct('A', 0, 'B', 0, 'C', 0, 'E', 0);
        devices(i).status = 'waiting';  % waiting, testing, passed, failed
        devices(i).location = 'queue';  % queue, bench1, bench2, station_X
        devices(i).current_test = '';
        devices(i).test_start_time = 0;
        devices(i).total_time = 0;
    end
end

function result = run_single_simulation(devices, params, config)
    % 运行单次仿真
    
    % 初始化仿真环境
    sim_state = initialize_simulation_state(devices, params, config);
    
    % 主仿真循环
    while ~sim_state.completed && sim_state.current_day <= config.max_days
        % 新的一天开始
        sim_state = start_new_day(sim_state);
        
        % 班次内的仿真
        while sim_state.shift_hours_used < config.hours_per_shift
            % 获取下一个事件
            [sim_state, event] = get_next_event(sim_state);
            
            if isempty(event)
                % 没有事件，检查是否可以开始新的测试
                sim_state = schedule_new_tests(sim_state);
                
                if isempty(sim_state.event_queue)
                    % 仍然没有事件，推进时间
                    sim_state.shift_hours_used = sim_state.shift_hours_used + 0.1;
                end
            else
                % 处理事件
                sim_state = process_event(sim_state, event);
            end
            
            % 检查完成条件
            sim_state = check_completion(sim_state);
        end
        
        % 班次结束处理
        sim_state = end_shift(sim_state);
    end
    
    % 计算统计结果
    result = calculate_simulation_results(sim_state);
end

function sim_state = initialize_simulation_state(devices, params, config)
    % 初始化仿真状态
    
    sim_state = struct();
    sim_state.devices = devices;
    sim_state.params = params;
    sim_state.config = config;
    
    % 时间状态
    sim_state.current_day = 1;
    sim_state.shift_hours_used = 0;
    sim_state.total_hours = 0;
    
    % 资源状态
    sim_state.test_benches = struct();
    sim_state.test_benches(1).occupied = false;
    sim_state.test_benches(1).device_id = 0;
    sim_state.test_benches(2).occupied = false;
    sim_state.test_benches(2).device_id = 0;
    
    sim_state.stations = struct();
    stations = {'A', 'B', 'C', 'E'};
    for i = 1:length(stations)
        sim_state.stations.(stations{i}).occupied = false;
        sim_state.stations.(stations{i}).device_id = 0;
        sim_state.stations.(stations{i}).equipment_life = 0;
        sim_state.stations.(stations{i}).setup_done = false;
        sim_state.stations.(stations{i}).total_work_time = 0;
    end
    
    % 事件队列 - 初始化为空的结构体数组
    sim_state.event_queue = struct('type', {}, 'time', {}, 'device_id', {}, ...
                                   'test_type', {}, 'station', {});
    
    % 统计信息
    sim_state.n_completed = 0;
    sim_state.n_passed = 0;
    sim_state.n_failed = 0;
    sim_state.completed = false;
    
    % 工时统计
    sim_state.work_hours = struct('A', 0, 'B', 0, 'C', 0, 'E', 0);
end

function sim_state = start_new_day(sim_state)
    % 开始新的一天
    sim_state.shift_hours_used = 0;
    
    % 设备初始调试（第一天）
    if sim_state.current_day == 1
        stations = {'A', 'B', 'C', 'E'};
        for i = 1:length(stations)
            if ~sim_state.stations.(stations{i}).setup_done
                setup_time = sim_state.params.setup_time.(stations{i});
                sim_state.shift_hours_used = sim_state.shift_hours_used + setup_time;
                sim_state.stations.(stations{i}).setup_done = true;
            end
        end
    end
end

function [sim_state, event] = get_next_event(sim_state)
    % 获取下一个事件
    
    event = [];
    if isempty(sim_state.event_queue)
        return;
    end
    
    % 找到最早的事件
    [~, idx] = min([sim_state.event_queue.time]);
    event = sim_state.event_queue(idx);
    
    % 检查是否在本班次内
    time_to_event = event.time - sim_state.total_hours;
    if sim_state.shift_hours_used + time_to_event <= sim_state.config.hours_per_shift
        % 可以处理该事件
        sim_state.event_queue(idx) = [];
        sim_state.shift_hours_used = sim_state.shift_hours_used + time_to_event;
        sim_state.total_hours = event.time;
    else
        % 事件在下一班次
        event = [];
    end
end

function sim_state = process_event(sim_state, event)
    % 处理事件
    
    switch event.type
        case 'test_complete'
            sim_state = handle_test_complete(sim_state, event);
            
        case 'transport_complete'
            sim_state = handle_transport_complete(sim_state, event);
            
        case 'equipment_failure'
            sim_state = handle_equipment_failure(sim_state, event);
    end
end

function sim_state = handle_test_complete(sim_state, event)
    % 处理测试完成事件
    
    device_id = event.device_id;
    test_type = event.test_type;
    
    % 生成测试结果
    test_passed = generate_test_result(sim_state.devices(device_id), test_type, sim_state.params);
    
    % 更新装置状态
    sim_state.devices(device_id).test_attempts.(test_type) = ...
        sim_state.devices(device_id).test_attempts.(test_type) + 1;
    
    if test_passed
        sim_state.devices(device_id).test_passed.(test_type) = true;
        
        % 检查是否完成所有测试
        if strcmp(test_type, 'E')
            % E测试通过，装置完成
            sim_state.devices(device_id).status = 'passed';
            sim_state.n_passed = sim_state.n_passed + 1;
            sim_state.n_completed = sim_state.n_completed + 1;
            
            % 释放测试台
            for bench_id = 1:2
                if sim_state.test_benches(bench_id).device_id == device_id
                    sim_state.test_benches(bench_id).occupied = false;
                    sim_state.test_benches(bench_id).device_id = 0;
                    break;
                end
            end
        else
            % 准备下一个测试
            sim_state.devices(device_id).current_test = '';
        end
    else
        % 测试失败
        if sim_state.devices(device_id).test_attempts.(test_type) >= 2
            % 连续两次失败，装置退出
            sim_state.devices(device_id).status = 'failed';
            sim_state.n_failed = sim_state.n_failed + 1;
            sim_state.n_completed = sim_state.n_completed + 1;
            
            % 释放测试台
            for bench_id = 1:2
                if sim_state.test_benches(bench_id).device_id == device_id
                    sim_state.test_benches(bench_id).occupied = false;
                    sim_state.test_benches(bench_id).device_id = 0;
                    break;
                end
            end
        else
            % 准备重测
            sim_state.devices(device_id).current_test = '';
        end
    end
    
    % 释放工位
    sim_state.stations.(test_type).occupied = false;
    sim_state.stations.(test_type).device_id = 0;
    
    % 更新工时统计
    test_time = sim_state.params.test_time.(test_type);
    sim_state.work_hours.(test_type) = sim_state.work_hours.(test_type) + test_time;
    sim_state.stations.(test_type).total_work_time = ...
        sim_state.stations.(test_type).total_work_time + test_time;
end

function test_passed = generate_test_result(device, test_type, params)
    % 生成测试结果（考虑误判和漏判）
    
    if strcmp(test_type, 'E')
        % E测试：检查所有子系统
        has_problem = device.has_problem.A || device.has_problem.B || ...
                     device.has_problem.C || device.has_problem.D;
        
        if has_problem
            % 有问题，可能漏判
            test_passed = rand() < params.alpha.E;
        else
            % 无问题，可能误判
            test_passed = rand() >= params.beta.E;
        end
    else
        % A/B/C测试
        if device.has_problem.(test_type)
            % 有问题，可能漏判
            test_passed = rand() < params.alpha.(test_type);
        else
            % 无问题，可能误判
            test_passed = rand() >= params.beta.(test_type);
        end
    end
end

function sim_state = schedule_new_tests(sim_state)
    % 调度新的测试
    
    % 检查测试台上的装置
    for bench_id = 1:2
        if sim_state.test_benches(bench_id).occupied
            device_id = sim_state.test_benches(bench_id).device_id;
            device = sim_state.devices(device_id);
            
            % 检查可以进行的测试
            if isempty(device.current_test) && strcmp(device.status, 'testing')
                % 尝试分配测试
                next_test = get_next_test(device);
                
                if ~isempty(next_test)
                    % 检查工位是否可用
                    if ~sim_state.stations.(next_test).occupied
                        % 检查剩余时间是否足够
                        required_time = get_test_time(sim_state.params, next_test);
                        remaining_time = sim_state.config.hours_per_shift - sim_state.shift_hours_used;
                        
                        if remaining_time >= required_time + 0.5  % 留0.5小时缓冲
                            % 开始测试
                            sim_state = start_test(sim_state, device_id, next_test);
                        end
                    end
                end
            end
        end
    end
    
    % 将等待装置分配到空闲测试台
    for i = 1:length(sim_state.devices)
        if strcmp(sim_state.devices(i).status, 'waiting')
            % 寻找空闲测试台
            for bench_id = 1:2
                if ~sim_state.test_benches(bench_id).occupied
                    % 分配到测试台
                    sim_state.test_benches(bench_id).occupied = true;
                    sim_state.test_benches(bench_id).device_id = i;
                    sim_state.devices(i).location = sprintf('bench%d', bench_id);
                    sim_state.devices(i).status = 'testing';
                    
                    % 添加运入时间
                    transport_event = struct();
                    transport_event.type = 'transport_complete';       % 事件类型
                    transport_event.device_id = i;                     % 装置ID（有效）
                    transport_event.time = sim_state.total_hours + sim_state.params.transport_time;  % 事件时间
                    transport_event.test_type = '';                    % 非测试事件，设为空
                    transport_event.station = '';                      % 非故障事件，设为空
                    sim_state.event_queue(end+1) = transport_event;
                    
                    break;
                end
            end
        end
    end
end

function test_time = get_test_time(params, test_type)
    % 获取测试时间
    test_time = params.test_time.(test_type);
end

function next_test = get_next_test(device)
    % 获取下一个需要进行的测试
    
    next_test = '';
    
    % 检查A/B/C测试
    tests = {'A', 'B', 'C'};
    for i = 1:length(tests)
        if ~device.test_passed.(tests{i}) && device.test_attempts.(tests{i}) < 2
            next_test = tests{i};
            return;
        end
    end
    
    % 检查是否可以进行E测试
    if device.test_passed.A && device.test_passed.B && device.test_passed.C
        if ~device.test_passed.E && device.test_attempts.E < 2
            next_test = 'E';
        end
    end
end

function sim_state = start_test(sim_state, device_id, test_type)
    % 开始测试
    
    % 占用工位
    sim_state.stations.(test_type).occupied = true;
    sim_state.stations.(test_type).device_id = device_id;
    
    % 更新装置状态
    sim_state.devices(device_id).current_test = test_type;
    sim_state.devices(device_id).test_start_time = sim_state.total_hours;
    
    % 获取测试时间
    test_time = get_test_time(sim_state.params, test_type);
    
    % 创建完成事件
    complete_event = struct();
    complete_event.type = 'test_complete';             % 事件类型
    complete_event.device_id = device_id;              % 装置ID（有效）
    complete_event.time = sim_state.total_hours + test_time;  % 事件时间
    complete_event.test_type = test_type;              % 测试类型（有效）
    complete_event.station = '';                       % 非故障事件，设为空
    complete_event.time = sim_state.total_hours + test_time;
    
    sim_state.event_queue(end+1) = complete_event;
    
    % 更新设备寿命
    sim_state.stations.(test_type).equipment_life = ...
        sim_state.stations.(test_type).equipment_life + test_time;
    
    % 检查设备故障
    sim_state = check_equipment_failure(sim_state, test_type);
end

function sim_state = check_equipment_failure(sim_state, station)
    % 检查设备是否故障
    
    life = sim_state.stations.(station).equipment_life;
    
    % 计算故障概率
    if life <= 120
        failure_prob = sim_state.params.failure_rate.(station)(1) * (life / 120);
    elseif life <= 240
        failure_prob = sim_state.params.failure_rate.(station)(1) + ...
                       (sim_state.params.failure_rate.(station)(2) - sim_state.params.failure_rate.(station)(1)) * ...
                       ((life - 120) / 120);
    else
        failure_prob = 1;  % 必须更换
    end
    
    % 生成故障事件（将概率转换为小时级别）
    test_time = get_test_time(sim_state.params, station);
    if rand() < failure_prob / 100 * test_time / 120  % 调整为合理的故障率
        failure_event = struct();
        failure_event.type = 'equipment_failure';          % 事件类型
        failure_event.device_id = 0;                       % 无关联装置，设为0
        failure_event.time = sim_state.total_hours + rand() * test_time;  % 事件时间
        failure_event.test_type = '';                      % 非测试事件，设为空
        failure_event.station = station;                   % 工位名称（有效）
        failure_event.time = sim_state.total_hours + rand() * test_time;
        sim_state.event_queue(end+1) = failure_event;
    end
end

function sim_state = handle_equipment_failure(sim_state, event)
    % 处理设备故障
    
    station = event.station;
    
    % 中断当前测试
    if sim_state.stations.(station).occupied
        device_id = sim_state.stations.(station).device_id;
        sim_state.devices(device_id).current_test = '';
        
        % 移除相关的完成事件
        keep_events = true(size(sim_state.event_queue));
        for i = 1:length(sim_state.event_queue)
            if strcmp(sim_state.event_queue(i).type, 'test_complete') && ...
               sim_state.event_queue(i).device_id == device_id
                keep_events(i) = false;
            end
        end
        sim_state.event_queue = sim_state.event_queue(keep_events);
    end
    
    % 更换设备
    sim_state.stations.(station).equipment_life = 0;
    sim_state.stations.(station).setup_done = false;
    sim_state.stations.(station).occupied = false;
    
    % 添加调试时间
    sim_state.shift_hours_used = sim_state.shift_hours_used + sim_state.params.setup_time.(station);
    sim_state.stations.(station).setup_done = true;
end

function sim_state = handle_transport_complete(sim_state, event)
    % 处理运输完成事件
    % 装置已经在测试台上，可以开始测试
end

function sim_state = end_shift(sim_state)
    % 班次结束处理
    
    % 中断未完成的测试
    stations = {'A', 'B', 'C', 'E'};
    for i = 1:length(stations)
        if sim_state.stations.(stations{i}).occupied
            device_id = sim_state.stations.(stations{i}).device_id;
            sim_state.devices(device_id).current_test = '';
            
            % 移除相关事件
            keep_events = true(size(sim_state.event_queue));
            for j = 1:length(sim_state.event_queue)
                if isfield(sim_state.event_queue(j), 'device_id') && ...
                   sim_state.event_queue(j).device_id == device_id
                    keep_events(j) = false;
                end
            end
            sim_state.event_queue = sim_state.event_queue(keep_events);
            
            % 释放工位
            sim_state.stations.(stations{i}).occupied = false;
        end
    end
    
    % 更新时间
    sim_state.total_hours = sim_state.total_hours + ...
        (sim_state.config.hours_per_shift - sim_state.shift_hours_used);
    sim_state.current_day = sim_state.current_day + 1;
end

function sim_state = check_completion(sim_state)
    % 检查是否完成所有装置
    
    if sim_state.n_completed >= sim_state.config.n_devices
        sim_state.completed = true;
    end
end

function result = calculate_simulation_results(sim_state)
    % 计算仿真结果
    
    result = struct();
    
    % 完成天数
    result.completion_days = sim_state.current_day - 1;
    
    % 通过数量
    result.n_passed = sim_state.n_passed;
    
    % 漏判概率：通过的装置中实际有问题的比例
    n_missed = 0;
    for i = 1:length(sim_state.devices)
        if strcmp(sim_state.devices(i).status, 'passed')
            if sim_state.devices(i).has_problem.A || sim_state.devices(i).has_problem.B || ...
               sim_state.devices(i).has_problem.C || sim_state.devices(i).has_problem.D
                n_missed = n_missed + 1;
            end
        end
    end
    result.miss_rate = n_missed / max(sim_state.n_passed, 1);
    
    % 误判概率：未通过的装置中实际无问题的比例
    n_false = 0;
    for i = 1:length(sim_state.devices)
        if strcmp(sim_state.devices(i).status, 'failed')
            if ~sim_state.devices(i).has_problem.A && ~sim_state.devices(i).has_problem.B && ...
               ~sim_state.devices(i).has_problem.C && ~sim_state.devices(i).has_problem.D
                n_false = n_false + 1;
            end
        end
    end
    result.false_rate = n_false / max(sim_state.n_failed, 1);
    
    % 有效工时比
    total_shift_hours = result.completion_days * sim_state.config.hours_per_shift;
    stations = {'A', 'B', 'C', 'E'};
    result.efficiency = zeros(1, 4);
    for i = 1:length(stations)
        result.efficiency(i) = sim_state.work_hours.(stations{i}) / total_shift_hours;
    end
    
    % 额外统计信息
    result.total_hours = sim_state.total_hours;
    result.n_failed = sim_state.n_failed;
    result.work_hours = sim_state.work_hours;
end