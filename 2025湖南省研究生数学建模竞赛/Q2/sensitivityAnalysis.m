% Functions/sensitivityAnalysis.m
function sensitivityAnalysis()
%SENSITIVITYANALYSIS 参数敏感性分析（为论文提供深度分析）

fprintf('开始敏感性分析...\n');

% 基准参数
baseParams = initializeParameters();

% 分析维度
factors = {'班次时长', '测手差错率', '设备故障率', '调度权重'};
variations = {10:0.5:14, 0.5:0.5:2, 0.5:0.5:2, [1,2,3; 2,1,3; 3,1,2; 3,2,1]};

results = struct();

%% 1. 班次时长敏感性
shiftHours = 10:0.5:14;
T_shift = zeros(size(shiftHours));
S_shift = zeros(size(shiftHours));

for i = 1:length(shiftHours)
    params = baseParams;
    params.shiftHours = shiftHours(i);
    
    % 运行小规模仿真
    simResults = runQuickSimulation(params, 20);
    T_shift(i) = simResults.avgCompletionDays;
    S_shift(i) = simResults.avgPassedDevices;
end

%% 2. 可视化
figure('Position', [100, 100, 1200, 400]);

subplot(1, 3, 1);
plot(shiftHours, T_shift, 'b-o', 'LineWidth', 2);
xlabel('班次时长 (小时)');
ylabel('平均完成天数');
title('班次时长敏感性分析');
grid on;

subplot(1, 3, 2);
% 绘制其他敏感性分析...

subplot(1, 3, 3);
% 绘制3D敏感性曲面...

saveas(gcf, 'Results/sensitivity_analysis.png');
end