% Visualize/visualizeResults.m
function visualizeResults(stats, params)
%VISUALIZERESULTS 结果可视化展示

figure('Position', [100, 100, 1400, 800], 'Name', '测试任务规划仿真结果');

%% 1. 完成时间分布
subplot(2, 3, 1);
histogram(stats.completionDays, 20, 'FaceColor', [0.2, 0.4, 0.8]);
xlabel('完成天数');
ylabel('频数');
title(sprintf('任务完成时间分布\n均值: %.2f天, 标准差: %.2f天', ...
    mean(stats.completionDays), std(stats.completionDays)));
grid on;

%% 2. 通过率分析
subplot(2, 3, 2);
passRates = stats.passedDevices / params.numDevices * 100;
boxplot(passRates);
ylabel('通过率 (%)');
title(sprintf('装置通过率\n均值: %.1f%%', mean(passRates)));
grid on;

%% 3. 漏判误判率对比
subplot(2, 3, 3);
data = [mean(stats.missRate)*100, mean(stats.falseAlarmRate)*100];
errors = [std(stats.missRate)*100, std(stats.falseAlarmRate)*100];
bar_handle = bar(data);
hold on;
errorbar(1:2, data, errors, 'k.', 'LineWidth', 1.5);
set(gca, 'XTickLabel', {'漏判率', '误判率'});
ylabel('概率 (%)');
title('质量检测性能');
bar_handle.FaceColor = [0.8, 0.3, 0.3];
grid on;

%% 4. 工位利用率
subplot(2, 3, 4);
workstations = {'A', 'B', 'C', 'E'};
utilization = [mean(stats.efficiency.A), mean(stats.efficiency.B), ...
               mean(stats.efficiency.C), mean(stats.efficiency.E)] * 100;
bar(utilization, 'FaceColor', [0.3, 0.7, 0.3]);
set(gca, 'XTickLabel', workstations);
ylabel('有效工作时间比 (%)');
title('工位利用率分析');
ylim([0, 100]);
grid on;

%% 5. 设备故障统计
subplot(2, 3, 5);
failureData = [stats.equipmentFailures.A, stats.equipmentFailures.B, ...
               stats.equipmentFailures.C, stats.equipmentFailures.E];
boxplot(failureData, 'Labels', workstations);
ylabel('故障次数');
title('设备故障情况');
grid on;

%% 6. 甘特图示例（单次仿真）
subplot(2, 3, 6);
% 绘制前20个装置的测试甘特图
plotGanttChart(stats.sampleSchedule, 20);
xlabel('时间 (小时)');
ylabel('装置编号');
title('测试调度甘特图（前20个装置）');
grid on;

% 保存图像
saveas(gcf, 'Results/simulation_results.png');
end

function plotGanttChart(schedule, numDevices)
%绘制甘特图
colors = struct('A', [0.8, 0.2, 0.2], ...
                'B', [0.2, 0.8, 0.2], ...
                'C', [0.2, 0.2, 0.8], ...
                'E', [0.8, 0.8, 0.2]);

hold on;
for i = 1:min(numDevices, length(schedule))
    deviceSchedule = schedule{i};
    for j = 1:size(deviceSchedule, 1)
        ws = deviceSchedule{j, 1};
        startTime = deviceSchedule{j, 2} / 60;  % 转换为小时
        endTime = deviceSchedule{j, 3} / 60;
        
        rectangle('Position', [startTime, i-0.4, endTime-startTime, 0.8], ...
                 'FaceColor', colors.(ws), 'EdgeColor', 'k');
    end
end

% 添加图例
h = zeros(4, 1);
h(1) = plot(NaN, NaN, 's', 'MarkerFaceColor', colors.A, 'MarkerSize', 10);
h(2) = plot(NaN, NaN, 's', 'MarkerFaceColor', colors.B, 'MarkerSize', 10);
h(3) = plot(NaN, NaN, 's', 'MarkerFaceColor', colors.C, 'MarkerSize', 10);
h(4) = plot(NaN, NaN, 's', 'MarkerFaceColor', colors.E, 'MarkerSize', 10);
legend(h, {'测试A', '测试B', '测试C', '综合测试E'}, 'Location', 'best');
end