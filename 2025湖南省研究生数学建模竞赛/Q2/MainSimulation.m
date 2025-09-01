% MainSimulation.m - 主程序入口
clear; clc; close all;

% 创建必要的文件夹
if ~exist('Classes', 'dir')
    error('Classes文件夹不存在，请确保所有类文件都在Classes文件夹中');
end
if ~exist('Functions', 'dir')
    error('Functions文件夹不存在，请确保所有函数文件都在Functions文件夹中');
end
if ~exist('Results', 'dir')
    mkdir('Results');
end

addpath('Classes');    
addpath('Functions');  
addpath('Visualize');  

%% 1. 参数初始化
params = initializeParameters();
fprintf('=== 大型装置测试任务规划仿真系统 ===\n');
fprintf('任务规模：%d个装置\n', params.numDevices);
fprintf('班次设置：单班制，每班%d小时\n', params.shiftHours);

%% 2. 多次仿真运行
numSimulations = 100;  
results = cell(numSimulations, 1);

for simID = 1:numSimulations
    if mod(simID, 10) == 0
        fprintf('运行仿真 %d/%d...\n', simID, numSimulations);
    end
    
    % 创建仿真器并设置随机种子
    sim = TestingSimulator(params);
    sim.setRandomSeed(simID);  % 使用不同的种子
    
    % 运行仿真
    try
        results{simID} = sim.run();
    catch ME
        fprintf('仿真 %d 出错: %s\n', simID, ME.message);
        % 记录空结果
        results{simID} = struct('completionTime', NaN, 'numPassed', 0, ...
                               'numFailed', 0, 'missRate', 0, 'falseAlarmRate', 0);
    end
end

%% 3. 移除失败的仿真结果
validResults = {};
for i = 1:numSimulations
    if ~isnan(results{i}.completionTime)
        validResults{end+1} = results{i};
    end
end
fprintf('成功完成 %d/%d 次仿真\n', length(validResults), numSimulations);

%% 4. 结果统计分析
if ~isempty(validResults)
    stats = analyzeResults(validResults, params);
    
    %% 5. 可视化展示
    visualizeResults(stats, params);
    
    %% 6. 输出论文所需表格
    generateReportTable(stats);
else
    fprintf('所有仿真都失败了，请检查代码\n');
end