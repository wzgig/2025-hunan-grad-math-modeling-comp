% RunAll.m - 完整运行脚本
%% 完整运行问题2仿真分析

% 清理环境
clear; clc; close all;

% 创建必要的文件夹
if ~exist('Results', 'dir')
    mkdir('Results');
end

% 记录开始时间
tic;

%% 1. 主仿真
fprintf('===== 步骤1: 运行主仿真 =====\n');
MainSimulation;

%% 2. 敏感性分析
fprintf('\n===== 步骤2: 敏感性分析 =====\n');
sensitivityAnalysis;

%% 3. 优化分析
fprintf('\n===== 步骤3: 调度策略优化 =====\n');
optimizeSchedulingWeights;

%% 4. 生成报告
fprintf('\n===== 步骤4: 生成完整报告 =====\n');
generateFullReport;

% 记录结束时间
elapsed = toc;
fprintf('\n全部分析完成！总用时: %.2f 分钟\n', elapsed/60);