%% 问题2 快速测试脚本
% 用于测试代码是否正常运行

clear; clc; close all;

fprintf('════════════════════════════════════════\n');
fprintf('     问题2 快速测试（减少仿真次数）\n');
fprintf('════════════════════════════════════════\n\n');

try
    %% 初始化参数（与主程序相同）
    fprintf('【初始化参数】\n');
    params = initialize_parameters();
    fprintf('✓ 参数初始化成功\n\n');
    
    %% 配置仿真（减少次数以快速测试）
    fprintf('【配置仿真】\n');
    sim_config = struct();
    sim_config.n_devices = 10;           % 减少到10个装置
    sim_config.n_replications = 5;       % 只运行5次
    sim_config.max_days = 20;            % 最大20天
    sim_config.hours_per_shift = 12;     
    sim_config.random_seed = 42;         
    sim_config.verbose = true;           
    
    fprintf('装置数量：%d\n', sim_config.n_devices);
    fprintf('仿真次数：%d\n', sim_config.n_replications);
    fprintf('✓ 配置完成\n\n');
    
    %% 运行测试仿真
    fprintf('【运行测试仿真】\n');
    tic;
    results = run_monte_carlo_simulation(params, sim_config);
    elapsed = toc;
    fprintf('✓ 仿真成功！用时：%.2f秒\n\n', elapsed);
    
    %% 计算基本统计
    fprintf('【基本统计结果】\n');
    fprintf('完成天数：%.2f ± %.2f\n', mean(results.T), std(results.T));
    fprintf('通过数量：%.2f ± %.2f\n', mean(results.S), std(results.S));
    fprintf('漏判概率：%.2f%%\n', mean(results.PL)*100);
    fprintf('误判概率：%.2f%%\n', mean(results.PW)*100);
    fprintf('平均效率：%.2f%%\n', mean(mean(results.YXB))*100);
    
    fprintf('\n════════════════════════════════════════\n');
    fprintf('✓ 测试成功！代码运行正常\n');
    fprintf('现在可以运行 problem2_main.m 进行完整分析\n');
    fprintf('════════════════════════════════════════\n');
    
catch ME
    fprintf('\n✗ 测试失败！\n');
    fprintf('错误信息：%s\n', ME.message);
    fprintf('错误位置：%s (第%d行)\n', ME.stack(1).file, ME.stack(1).line);
    fprintf('\n请检查错误信息并修复\n');
end

%% 参数初始化函数（从主程序复制）
function params = initialize_parameters()
    % 初始化所有参数
    
    % 子系统固有问题概率
    params.p = struct();
    params.p.A = 0.025;
    params.p.B = 0.030;
    params.p.C = 0.020;
    params.p.D = 0.001;
    
    % 测手差错率
    params.e = struct();
    params.e.A = 0.03;
    params.e.B = 0.04;
    params.e.C = 0.02;
    params.e.E = 0.02;
    
    % 计算漏判率和误判率
    params.alpha = struct();
    params.beta = struct();
    
    systems = {'A', 'B', 'C'};
    for i = 1:length(systems)
        sys = systems{i};
        params.alpha.(sys) = 0.5 * params.e.(sys) / params.p.(sys);
        params.beta.(sys) = 0.5 * params.e.(sys) / (1 - params.p.(sys));
    end
    
    % E组参数（基于问题1的修正计算）
    P_problem_A = params.p.A * params.alpha.A / ...
                  (params.p.A * params.alpha.A + (1-params.p.A) * (1-params.beta.A));
    P_problem_B = params.p.B * params.alpha.B / ...
                  (params.p.B * params.alpha.B + (1-params.p.B) * (1-params.beta.B));
    P_problem_C = params.p.C * params.alpha.C / ...
                  (params.p.C * params.alpha.C + (1-params.p.C) * (1-params.beta.C));
    
    P_any_problem = 1 - (1-P_problem_A) * (1-P_problem_B) * (1-P_problem_C) * (1-params.p.D);
    params.alpha.E = (0.5 * params.e.E) / P_any_problem;
    params.beta.E = (0.5 * params.e.E) / (1 - P_any_problem);
    
    % 测试时间参数（小时）
    params.test_time = struct();
    params.test_time.A = 2.5;
    params.test_time.B = 2.0;
    params.test_time.C = 2.5;
    params.test_time.E = 3.0;
    
    % 调试时间（小时）
    params.setup_time = struct();
    params.setup_time.A = 30/60;  % 30分钟
    params.setup_time.B = 20/60;  % 20分钟
    params.setup_time.C = 20/60;  % 20分钟
    params.setup_time.E = 40/60;  % 40分钟
    
    % 运输时间（小时）
    params.transport_time = 0.5;
    
    % 设备故障参数
    params.failure_rate = struct();
    params.failure_rate.A = [0.03, 0.05];  % [0-120h, 120-240h]
    params.failure_rate.B = [0.04, 0.07];
    params.failure_rate.C = [0.02, 0.06];
    params.failure_rate.E = [0.03, 0.05];
    
    % 测试台和工位数量
    params.n_test_benches = 2;
    params.n_stations = struct('A', 1, 'B', 1, 'C', 1, 'E', 1);
end