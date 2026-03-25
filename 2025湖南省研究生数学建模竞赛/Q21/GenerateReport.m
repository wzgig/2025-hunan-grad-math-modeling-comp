function GenerateReport(stats)
%% GenerateReport - 生成问题2结果报告

%% 创建表格
fprintf('\n========== 问题2 结果报告表 ==========\n');
fprintf('指标\t\t数值\t\t单位\n');
fprintf('----------------------------------------\n');
fprintf('T\t\t%.2f\t\t天\n', stats.T);
fprintf('S\t\t%.2f\t\t个\n', stats.S);
fprintf('PL\t\t%.2f\t\t%%\n', stats.PL);
fprintf('PW\t\t%.2f\t\t%%\n', stats.PW);
fprintf('YXB1\t\t%.2f\t\t%%\n', stats.YXB1);
fprintf('YXB2\t\t%.2f\t\t%%\n', stats.YXB2);
fprintf('YXB3\t\t%.2f\t\t%%\n', stats.YXB3);
fprintf('YXB4\t\t%.2f\t\t%%\n', stats.YXB4);
fprintf('========================================\n\n');

%% 保存到Excel文件
T = table(stats.T, stats.S, stats.PL, stats.PW, ...
         stats.YXB1, stats.YXB2, stats.YXB3, stats.YXB4, ...
         'VariableNames', {'T_days', 'S_count', 'PL_percent', 'PW_percent', ...
                          'YXB1', 'YXB2', 'YXB3', 'YXB4'});

filename = sprintf('Problem2_Results_%s.xlsx', datestr(now, 'yyyymmdd_HHMMSS'));
writetable(T, filename);
fprintf('结果已保存到Excel文件: %s\n', filename);

%% 生成LaTeX表格代码
fprintf('\n%% LaTeX表格代码\n');
fprintf('\\begin{table}[h]\n');
fprintf('\\centering\n');
fprintf('\\caption{问题2仿真结果}\n');
fprintf('\\begin{tabular}{cccccccc}\n');
fprintf('\\hline\n');
fprintf('T & S & $P_L$ & $P_W$ & YXB1 & YXB2 & YXB3 & YXB4 \\\\\n');
fprintf('\\hline\n');
fprintf('%.2f & %.2f & %.2f\\%% & %.2f\\%% & %.2f\\%% & %.2f\\%% & %.2f\\%% & %.2f\\%% \\\\\n', ...
    stats.T, stats.S, stats.PL, stats.PW, ...
    stats.YXB1, stats.YXB2, stats.YXB3, stats.YXB4);
fprintf('\\hline\n');
fprintf('\\end{tabular}\n');
fprintf('\\end{table}\n');

end