function Visualization(results, stats, params)
%% Visualization - 结果可视化

%% 创建图形窗口
figure('Position', [100, 100, 1400, 800], 'Name', '问题2仿真结果');

%% 1. 完成天数分布
subplot(2,3,1);
histogram(results.completionDays, 20, 'FaceColor', [0.2, 0.4, 0.8]);
hold on;
xline(stats.T, 'r--', 'LineWidth', 2);
xlabel('完成天数');
ylabel('频数');
title(sprintf('任务完成时间分布\n均值: %.2f天, 标准差: %.2f天', ...
    stats.T, stats.T_std));
grid on;

%% 2. 通过率分析
subplot(2,3,2);
passRate = results.passedDevices / params.numDevices * 100;
histogram(passRate, 15, 'FaceColor', [0.2, 0.8, 0.4]);
xlabel('通过率 (%)');
ylabel('频数');
title(sprintf('装置通过率分布\n均值: %.1f%%', mean(passRate)));
grid on;

%% 3. 漏判/误判率
subplot(2,3,3);
data = [stats.PL, stats.PW];
errors = [stats.PL_std, stats.PW_std];
bar_colors = [0.8, 0.3, 0.3; 0.3, 0.3, 0.8];
b = bar(data);
b.FaceColor = 'flat';
b.CData = bar_colors;
hold on;
errorbar(1:2, data, errors, 'k.', 'LineWidth', 1.5);
set(gca, 'XTickLabel', {'漏判率', '误判率'});
ylabel('概率 (%)');
title('质量检测性能指标');
grid on;

%% 4. 工位利用率
subplot(2,3,4);
workstations = {'A', 'B', 'C', 'E'};
utilization = [stats.YXB1, stats.YXB2, stats.YXB3, stats.YXB4];
bar(utilization, 'FaceColor', [0.3, 0.7, 0.7]);
set(gca, 'XTickLabel', workstations);
ylabel('有效工作时间比 (%)');
title('各工位利用率分析');
ylim([0, 100]);
grid on;

%% 5. 完成天数趋势（箱线图）
subplot(2,3,5);
% 将数据分组（每10次仿真为一组）
groupSize = 10;
numGroups = floor(length(results.completionDays)/groupSize);
groupedData = reshape(results.completionDays(1:numGroups*groupSize), ...
    groupSize, numGroups);
boxplot(groupedData);
xlabel('仿真组别');
ylabel('完成天数');
title('完成时间稳定性分析');
grid on;

%% 6. 甘特图（第一次仿真的前10个装置）
subplot(2,3,6);
if ~isempty(results.schedules{1})
    plotGanttChart(results.schedules{1}, 10);
end
xlabel('时间 (小时)');
ylabel('装置编号');
title('测试调度甘特图（前10个装置）');
grid on;

%% 保存图形
saveas(gcf, 'Problem2_Results.png');
fprintf('结果图形已保存为 Problem2_Results.png\n');

end

function plotGanttChart(schedule, maxDevices)
%% 绘制甘特图
colors = struct('A', [0.8,0.2,0.2], 'B', [0.2,0.8,0.2], ...
               'C', [0.2,0.2,0.8], 'E', [0.8,0.8,0.2]);

hold on;
deviceCount = 0;
processedDevices = [];

for i = 1:length(schedule)
    event = schedule{i};
    deviceID = event.deviceID;
    
    % 只显示前maxDevices个装置
    if ~ismember(deviceID, processedDevices)
        deviceCount = deviceCount + 1;
        processedDevices(end+1) = deviceID;
        if deviceCount > maxDevices
            break;
        end
    end
    
    deviceIdx = find(processedDevices == deviceID);
    if isempty(deviceIdx) || deviceIdx > maxDevices
        continue;
    end
    
    % 绘制测试块
    startHour = event.startTime / 60;
    ws = event.workstation;
    
    switch ws
        case 'A', duration = 2.5;
        case 'B', duration = 2.0;
        case 'C', duration = 2.5;
        case 'E', duration = 3.0;
    end
    
    rectangle('Position', [startHour, deviceIdx-0.4, duration, 0.8], ...
             'FaceColor', colors.(ws), 'EdgeColor', 'k');
end

% 添加图例
h = zeros(4,1);
h(1) = plot(NaN, NaN, 's', 'MarkerFaceColor', colors.A, 'MarkerSize', 10);
h(2) = plot(NaN, NaN, 's', 'MarkerFaceColor', colors.B, 'MarkerSize', 10);
h(3) = plot(NaN, NaN, 's', 'MarkerFaceColor', colors.C, 'MarkerSize', 10);
h(4) = plot(NaN, NaN, 's', 'MarkerFaceColor', colors.E, 'MarkerSize', 10);
legend(h, {'测试A', '测试B', '测试C', '综合测试E'}, ...
       'Location', 'eastoutside', 'FontSize', 8);

xlim([0, 50]); % 显示前50小时
ylim([0, maxDevices+1]);
end