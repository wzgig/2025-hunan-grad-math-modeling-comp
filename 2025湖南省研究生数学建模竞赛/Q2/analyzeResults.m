% Functions/analyzeResults.m
function stats = analyzeResults(results, params)
%ANALYZERESULTS 分析仿真结果

numSims = length(results);

% 初始化统计数组
stats.completionDays = zeros(numSims, 1);
stats.passedDevices = zeros(numSims, 1);
stats.missRate = zeros(numSims, 1);
stats.falseAlarmRate = zeros(numSims, 1);
stats.efficiency = struct('A', zeros(numSims,1), 'B', zeros(numSims,1), ...
                          'C', zeros(numSims,1), 'E', zeros(numSims,1));
stats.equipmentFailures = struct('A', zeros(numSims,1), 'B', zeros(numSims,1), ...
                                 'C', zeros(numSims,1), 'E', zeros(numSims,1));

% 提取每次仿真的结果
for i = 1:numSims
    r = results{i};
    stats.completionDays(i) = r.completionTime / (12*60);  % 转换为天数
    stats.passedDevices(i) = r.numPassed;
    stats.missRate(i) = r.missRate;
    stats.falseAlarmRate(i) = r.falseAlarmRate;
    
    stats.efficiency.A(i) = r.workstationEfficiency.A;
    stats.efficiency.B(i) = r.workstationEfficiency.B;
    stats.efficiency.C(i) = r.workstationEfficiency.C;
    stats.efficiency.E(i) = r.workstationEfficiency.E;
    
    stats.equipmentFailures.A(i) = r.equipmentFailures.A;
    stats.equipmentFailures.B(i) = r.equipmentFailures.B;
    stats.equipmentFailures.C(i) = r.equipmentFailures.C;
    stats.equipmentFailures.E(i) = r.equipmentFailures.E;
end

% 保存一个样本调度用于甘特图
stats.sampleSchedule = results{1}.schedule;

% 计算汇总统计
stats.summary = struct();
stats.summary.T = mean(stats.completionDays);  % 平均完成天数
stats.summary.T_std = std(stats.completionDays);
stats.summary.S = mean(stats.passedDevices);    % 平均通过数量
stats.summary.S_std = std(stats.passedDevices);
stats.summary.PL = mean(stats.missRate);        % 总漏判概率
stats.summary.PW = mean(stats.falseAlarmRate);  % 总误判概率
stats.summary.YXB1 = mean(stats.efficiency.A);  % A组效率
stats.summary.YXB2 = mean(stats.efficiency.B);  % B组效率
stats.summary.YXB3 = mean(stats.efficiency.C);  % C组效率
stats.summary.YXB4 = mean(stats.efficiency.E);  % E组效率

% 计算95%置信区间
alpha = 0.05;
stats.CI = struct();
stats.CI.T = [stats.summary.T - 1.96*stats.summary.T_std/sqrt(numSims), ...
              stats.summary.T + 1.96*stats.summary.T_std/sqrt(numSims)];
stats.CI.S = [stats.summary.S - 1.96*stats.summary.S_std/sqrt(numSims), ...
              stats.summary.S + 1.96*stats.summary.S_std/sqrt(numSims)];

end

% Functions/generateReportTable.m
function generateReportTable(stats)
%GENERATEREPORTTABLE 生成论文所需的表格

fprintf('\n========== 问题2 仿真结果统计表 ==========\n');
fprintf('指标\t\t均值\t\t标准差\t\t95%%置信区间\n');
fprintf('------------------------------------------------\n');
fprintf('T (天)\t\t%.2f\t\t%.2f\t\t[%.2f, %.2f]\n', ...
    stats.summary.T, stats.summary.T_std, stats.CI.T(1), stats.CI.T(2));
fprintf('S (个)\t\t%.2f\t\t%.2f\t\t[%.2f, %.2f]\n', ...
    stats.summary.S, stats.summary.S_std, stats.CI.S(1), stats.CI.S(2));
fprintf('PL (%%)\t\t%.2f\t\t%.2f\t\t-\n', ...
    stats.summary.PL*100, std(stats.missRate)*100);
fprintf('PW (%%)\t\t%.2f\t\t%.2f\t\t-\n', ...
    stats.summary.PW*100, std(stats.falseAlarmRate)*100);
fprintf('YXB1 (%%)\t%.2f\t\t%.2f\t\t-\n', ...
    stats.summary.YXB1*100, std(stats.efficiency.A)*100);
fprintf('YXB2 (%%)\t%.2f\t\t%.2f\t\t-\n', ...
    stats.summary.YXB2*100, std(stats.efficiency.B)*100);
fprintf('YXB3 (%%)\t%.2f\t\t%.2f\t\t-\n', ...
    stats.summary.YXB3*100, std(stats.efficiency.C)*100);
fprintf('YXB4 (%%)\t%.2f\t\t%.2f\t\t-\n', ...
    stats.summary.YXB4*100, std(stats.efficiency.E)*100);
fprintf('================================================\n');

% 输出LaTeX格式表格（便于论文使用）
fprintf('\n%% LaTeX格式表格\n');
fprintf('\\begin{table}[h]\n');
fprintf('\\centering\n');
fprintf('\\caption{问题2仿真结果统计}\n');
fprintf('\\begin{tabular}{cccccccc}\n');
fprintf('\\hline\n');
fprintf('T & S & $P_L$ & $P_W$ & YXB1 & YXB2 & YXB3 & YXB4 \\\\\n');
fprintf('\\hline\n');
fprintf('%.2f & %.2f & %.2f\\%% & %.2f\\%% & %.2f\\%% & %.2f\\%% & %.2f\\%% & %.2f\\%% \\\\\n', ...
    stats.summary.T, stats.summary.S, ...
    stats.summary.PL*100, stats.summary.PW*100, ...
    stats.summary.YXB1*100, stats.summary.YXB2*100, ...
    stats.summary.YXB3*100, stats.summary.YXB4*100);
fprintf('\\hline\n');
fprintf('\\end{tabular}\n');
fprintf('\\end{table}\n');

% 保存结果到Excel文件
saveResultsToExcel(stats);

end

function saveResultsToExcel(stats)
%保存结果到Excel
filename = sprintf('Results/Problem2_Results_%s.xlsx', datestr(now, 'yyyymmdd_HHMMSS'));

% 创建表格数据
T = table(stats.summary.T, stats.summary.S, ...
         stats.summary.PL*100, stats.summary.PW*100, ...
         stats.summary.YXB1*100, stats.summary.YXB2*100, ...
         stats.summary.YXB3*100, stats.summary.YXB4*100, ...
         'VariableNames', {'T_days', 'S_devices', 'PL_percent', 'PW_percent', ...
                          'YXB1_percent', 'YXB2_percent', 'YXB3_percent', 'YXB4_percent'});

% 写入Excel
writetable(T, filename, 'Sheet', 'Summary');
fprintf('结果已保存到: %s\n', filename);
end