%% 问题2主程序：测试任务规划仿真
% 湖南省研究生数学建模竞赛
% 任务：100个装置的测试规划，每班12小时

clear; clc; close all;
addpath('functions/');  % 添加函数路径

%% ================== 参数初始化 ==================
fprintf('╔════════════════════════════════════════════════════════╗\n');
fprintf('║            问题2：测试任务规划仿真系统                ║\n');
fprintf('╚════════════════════════════════════════════════════════╝\n\n');

% 初始化全局参数
params = initialize_parameters();

% 仿真设置
sim_config = struct();
sim_config.n_devices = 100;           % 装置数量
sim_config.n_replications = 100;      % 仿真重复次数
sim_config.max_days = 50;             % 最大仿真天数
sim_config.hours_per_shift = 12;      % 每班工作小时数
sim_config.random_seed = 42;          % 随机种子
sim_config.verbose = true;            % 详细输出

%% ================== 运行仿真 ==================
fprintf('【开始仿真】\n');
fprintf('装置数量：%d\n', sim_config.n_devices);
fprintf('仿真次数：%d\n', sim_config.n_replications);
fprintf('每班时长：%d小时\n', sim_config.hours_per_shift);
fprintf('────────────────────────────────────\n');

% 运行蒙特卡洛仿真
tic;
results = run_monte_carlo_simulation(params, sim_config);
elapsed_time = toc;

fprintf('\n仿真完成！用时：%.2f秒\n', elapsed_time);
fprintf('────────────────────────────────────\n\n');

%% ================== 结果分析 ==================
fprintf('【仿真结果统计】\n');
fprintf('────────────────────────────────────\n');

% 计算统计指标
stats = calculate_statistics(results);

% 输出主要结果
fprintf('任务完成天数 T：\n');
fprintf('  均值：%.2f天\n', stats.T_mean);
fprintf('  标准差：%.2f天\n', stats.T_std);
fprintf('  95%%置信区间：[%.2f, %.2f]天\n\n', stats.T_ci(1), stats.T_ci(2));

fprintf('通过测试装置数 S：\n');
fprintf('  均值：%.2f个\n', stats.S_mean);
fprintf('  标准差：%.2f个\n', stats.S_std);
fprintf('  通过率：%.2f%%\n\n', stats.S_mean/sim_config.n_devices*100);

fprintf('总漏判概率 P_L：%.4f%% (%.4f%%)\n', stats.PL_mean*100, stats.PL_std*100);
fprintf('总误判概率 P_W：%.4f%% (%.4f%%)\n\n', stats.PW_mean*100, stats.PW_std*100);

fprintf('有效工作时间比 YXB：\n');
fprintf('  A组：%.2f%% (%.2f%%)\n', stats.YXB_mean(1)*100, stats.YXB_std(1)*100);
fprintf('  B组：%.2f%% (%.2f%%)\n', stats.YXB_mean(2)*100, stats.YXB_std(2)*100);
fprintf('  C组：%.2f%% (%.2f%%)\n', stats.YXB_mean(3)*100, stats.YXB_std(3)*100);
fprintf('  E组：%.2f%% (%.2f%%)\n', stats.YXB_mean(4)*100, stats.YXB_std(4)*100);
fprintf('────────────────────────────────────\n\n');

%% ================== 生成表格 ==================
% 生成问题2要求的结果表格
generate_result_table(stats);

%% ================== 可视化分析 ==================
fprintf('【生成可视化图表】\n');
visualize_results(results, stats, params);
fprintf('图表生成完成！\n\n');

%% ================== 保存结果 ==================
save('problem2_results.mat', 'results', 'stats', 'params', 'sim_config');
fprintf('结果已保存至 problem2_results.mat\n\n');

% 生成报告
generate_report(stats, sim_config);

%% ================== 辅助函数 ==================

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

function generate_result_table(stats)
    % 生成结果表格（表2格式）
    
    fprintf('╔════════════════════════════════════════════════════════════════════════════╗\n');
    fprintf('║                        表2：问题2结果统计指标                              ║\n');
    fprintf('╠═════╦═══════╦════════╦════════╦════════╦════════╦════════╦════════╦════════╣\n');
    fprintf('║  T  ║   S   ║   P_L  ║   P_W  ║  YXB1  ║  YXB2  ║  YXB3  ║  YXB4  ║\n');
    fprintf('╠═════╬═══════╬════════╬════════╬════════╬════════╬════════╬════════╬════════╣\n');
    fprintf('║%5.1f║%7.1f║%7.4f║%7.4f║%7.3f║%7.3f║%7.3f║%7.3f║\n', ...
        stats.T_mean, stats.S_mean, stats.PL_mean, stats.PW_mean, ...
        stats.YXB_mean(1), stats.YXB_mean(2), stats.YXB_mean(3), stats.YXB_mean(4));
    fprintf('╚═════╩═══════╩════════╩════════╩════════╩════════╩════════╩════════╩════════╝\n\n');
end

function generate_report(stats, config)
    % 生成文本报告
    
    fid = fopen('problem2_report.txt', 'w');
    
    fprintf(fid, '=====================================\n');
    fprintf(fid, '     问题2 仿真分析报告\n');
    fprintf(fid, '     %s\n', datestr(now));
    fprintf(fid, '=====================================\n\n');
    
    fprintf(fid, '一、仿真设置\n');
    fprintf(fid, '-------------\n');
    fprintf(fid, '装置数量：%d\n', config.n_devices);
    fprintf(fid, '仿真次数：%d\n', config.n_replications);
    fprintf(fid, '每班时长：%d小时\n\n', config.hours_per_shift);
    
    fprintf(fid, '二、主要结果\n');
    fprintf(fid, '-------------\n');
    fprintf(fid, '任务完成天数：%.2f ± %.2f天\n', stats.T_mean, stats.T_std);
    fprintf(fid, '通过装置数：%.2f ± %.2f个\n', stats.S_mean, stats.S_std);
    fprintf(fid, '总漏判概率：%.4f%%\n', stats.PL_mean*100);
    fprintf(fid, '总误判概率：%.4f%%\n\n', stats.PW_mean*100);
    
    fprintf(fid, '三、效率分析\n');
    fprintf(fid, '-------------\n');
    fprintf(fid, 'A组有效工时比：%.2f%%\n', stats.YXB_mean(1)*100);
    fprintf(fid, 'B组有效工时比：%.2f%%\n', stats.YXB_mean(2)*100);
    fprintf(fid, 'C组有效工时比：%.2f%%\n', stats.YXB_mean(3)*100);
    fprintf(fid, 'E组有效工时比：%.2f%%\n\n', stats.YXB_mean(4)*100);
    
    fprintf(fid, '四、关键发现\n');
    fprintf(fid, '-------------\n');
    fprintf(fid, '1. 平均%.1f天完成100个装置测试\n', stats.T_mean);
    fprintf(fid, '2. 通过率约%.1f%%\n', stats.S_mean);
    fprintf(fid, '3. 各组工时利用率在%.0f%%-%.0f%%之间\n', ...
            min(stats.YXB_mean)*100, max(stats.YXB_mean)*100);
    
    fclose(fid);
    
    fprintf('分析报告已生成：problem2_report.txt\n');
end