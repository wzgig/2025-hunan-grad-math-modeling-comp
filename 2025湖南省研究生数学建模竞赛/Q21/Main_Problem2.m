%% Main_Problem2.m - 问题2主程序
% 单班制测试任务规划仿真系统
% 作者：[团队名称]
% 日期：2024年12月

clear; clc; close all;tic
rng(2024); % 设置随机种子保证可重复性

fprintf('=====================================\n');
fprintf('   大型装置测试任务规划仿真系统\n');
fprintf('        问题2：单班制模式\n');
fprintf('=====================================\n\n');

%% 1. 参数初始化
params = InitParams();
fprintf('系统参数加载完成\n');
fprintf('- 装置数量：%d\n', params.numDevices);
fprintf('- 每日工作时间：%d小时\n', params.shiftHours);
fprintf('- 测试台数量：%d\n', params.numPlatforms);
fprintf('\n');

%% 2. Monte Carlo仿真
numSimulations = 1; % 仿真次数
fprintf('开始Monte Carlo仿真（%d次）...\n', numSimulations);

% 预分配结果存储
results = struct();
results.completionDays = zeros(numSimulations, 1);
results.passedDevices = zeros(numSimulations, 1);
results.missRate = zeros(numSimulations, 1);
results.falseAlarmRate = zeros(numSimulations, 1);
results.efficiency = zeros(numSimulations, 4); % A,B,C,E
results.schedules = cell(numSimulations, 1);

% 进度条
h = waitbar(0, '仿真进行中...');

for simID = 1:numSimulations
    % 更新进度条
    waitbar(simID/numSimulations, h, ...
        sprintf('仿真进度：%d/%d', simID, numSimulations));
    
    % 运行单次仿真
    rng(2024 + simID); % 每次仿真不同的随机种子
    sim = TestingSimulator(params);
    simResult = sim.run();
    
    % 收集结果
    results.completionDays(simID) = simResult.completionDays;
    results.passedDevices(simID) = simResult.passedDevices;
    results.missRate(simID) = simResult.missRate;
    results.falseAlarmRate(simID) = simResult.falseAlarmRate;
    results.efficiency(simID, :) = simResult.efficiency;
    
    % 保存第一次仿真的调度详情用于可视化
    if simID == 1
        results.schedules{1} = simResult.schedule;
    end
end

close(h);
fprintf('仿真完成！\n\n');

%% 3. 结果分析
stats = AnalyzeResults(results, params);

%% 4. 可视化
Visualization(results, stats, params);

%% 5. 生成报告表格
GenerateReport(stats);
toc