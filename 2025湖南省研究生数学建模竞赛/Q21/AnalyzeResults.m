function stats = AnalyzeResults(results, params)
%% AnalyzeResults - 分析仿真结果
% 输入：results - 仿真结果，params - 参数
% 输出：stats - 统计指标

fprintf('========== 结果统计分析 ==========\n');

%% 基本统计
stats.T = mean(results.completionDays);
stats.T_std = std(results.completionDays);
stats.S = mean(results.passedDevices);
stats.S_std = std(results.passedDevices);
stats.PL = mean(results.missRate) * 100;
stats.PL_std = std(results.missRate) * 100;
stats.PW = mean(results.falseAlarmRate) * 100;
stats.PW_std = std(results.falseAlarmRate) * 100;

%% 有效工作时间比
stats.YXB1 = mean(results.efficiency(:,1)) * 100;
stats.YXB2 = mean(results.efficiency(:,2)) * 100;
stats.YXB3 = mean(results.efficiency(:,3)) * 100;
stats.YXB4 = mean(results.efficiency(:,4)) * 100;

%% 95%置信区间
alpha = 0.05;
n = length(results.completionDays);
t_critical = tinv(1-alpha/2, n-1);

stats.T_CI = [stats.T - t_critical*stats.T_std/sqrt(n), ...
              stats.T + t_critical*stats.T_std/sqrt(n)];
stats.S_CI = [stats.S - t_critical*stats.S_std/sqrt(n), ...
              stats.S + t_critical*stats.S_std/sqrt(n)];

%% 输出结果
fprintf('T (完成天数): %.2f ± %.2f 天\n', stats.T, stats.T_std);
fprintf('  95%%置信区间: [%.2f, %.2f]\n', stats.T_CI(1), stats.T_CI(2));
fprintf('S (通过数量): %.2f ± %.2f 个\n', stats.S, stats.S_std);
fprintf('  95%%置信区间: [%.2f, %.2f]\n', stats.S_CI(1), stats.S_CI(2));
fprintf('PL (漏判率): %.2f ± %.2f %%\n', stats.PL, stats.PL_std);
fprintf('PW (误判率): %.2f ± %.2f %%\n', stats.PW, stats.PW_std);
fprintf('YXB1 (A组效率): %.2f%%\n', stats.YXB1);
fprintf('YXB2 (B组效率): %.2f%%\n', stats.YXB2);
fprintf('YXB3 (C组效率): %.2f%%\n', stats.YXB3);
fprintf('YXB4 (E组效率): %.2f%%\n', stats.YXB4);
fprintf('=====================================\n\n');

end