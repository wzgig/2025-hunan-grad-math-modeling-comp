%% 问题1主程序：综合测试概率模型的完整实现
% 湖南省研究生数学建模竞赛 - 大型装置测试任务规划
% 版本：国家特等奖冲击版 V3.0
% 作者：建模团队
% 日期：2025年

clear; clc; close all;
format long;

%% ========== 第一部分：基础参数设置 ==========
fprintf('╔════════════════════════════════════════════════════════╗\n');
fprintf('║     湖南省研究生数学建模竞赛 - 问题1完整解决方案      ║\n');
fprintf('║              综合测试概率参数计算与分析                ║\n');
fprintf('╚════════════════════════════════════════════════════════╝\n\n');

% 1.1 子系统固有问题概率
p = struct();
p.A = 0.025;  % A系统固有问题概率
p.B = 0.030;  % B系统固有问题概率
p.C = 0.020;  % C系统固有问题概率
p.D = 0.001;  % D系统（联接系统）问题概率

% 1.2 测手差错率
e = struct();
e.A = 0.03;   % A组测手总差错率
e.B = 0.04;   % B组测手总差错率
e.C = 0.02;   % C组测手总差错率
e.E = 0.02;   % E组测手总差错率

% 1.3 输出基础参数
fprintf('【1. 输入参数汇总】\n');
fprintf('─────────────────────────────────────────\n');
fprintf('子系统固有问题概率：\n');
fprintf('  p_A = %.3f (%.1f%%)    p_B = %.3f (%.1f%%)\n', ...
    p.A, p.A*100, p.B, p.B*100);
fprintf('  p_C = %.3f (%.1f%%)    p_D = %.3f (%.1f%%)\n', ...
    p.C, p.C*100, p.D, p.D*100);
fprintf('\n测手差错率：\n');
fprintf('  e_A = %.3f (%.1f%%)    e_B = %.3f (%.1f%%)\n', ...
    e.A, e.A*100, e.B, e.B*100);
fprintf('  e_C = %.3f (%.1f%%)    e_E = %.3f (%.1f%%)\n', ...
    e.C, e.C*100, e.E, e.E*100);
fprintf('─────────────────────────────────────────\n\n');

%% ========== 第二部分：子系统测试阶段分析 ==========
fprintf('【2. 子系统测试阶段概率分析】\n');
fprintf('─────────────────────────────────────────\n');

% 2.1 计算各子系统的漏判率和误判率
systems = {'A', 'B', 'C'};
alpha = struct();  % 漏判率
beta = struct();   % 误判率

for i = 1:length(systems)
    sys = systems{i};
    % 根据误判漏判各占50%的约束
    alpha.(sys) = 0.5 * e.(sys) / p.(sys);
    beta.(sys) = 0.5 * e.(sys) / (1 - p.(sys));
    
    fprintf('%s系统测试参数：\n', sys);
    fprintf('  漏判率 α_%s = %.4f (%.2f%%)\n', sys, alpha.(sys), alpha.(sys)*100);
    fprintf('  误判率 β_%s = %.4f (%.2f%%)\n', sys, beta.(sys), beta.(sys)*100);
    
    % 验证总差错率
    error_check = p.(sys) * alpha.(sys) + (1 - p.(sys)) * beta.(sys);
    fprintf('  验证：%.4f ≈ %.4f ✓\n\n', error_check, e.(sys));
end

% 2.2 计算通过各子系统测试的概率
P_pass = struct();
for i = 1:length(systems)
    sys = systems{i};
    P_pass.(sys) = p.(sys) * alpha.(sys) + (1 - p.(sys)) * (1 - beta.(sys));
    fprintf('P(通过%s测试) = %.6f\n', sys, P_pass.(sys));
end

% 2.3 计算三个子系统都通过的概率
P_pass_all = P_pass.A * P_pass.B * P_pass.C;
fprintf('\nP(通过所有子系统测试) = %.6f\n', P_pass_all);
fprintf('─────────────────────────────────────────\n\n');

%% ========== 第三部分：贝叶斯后验概率更新 ==========
fprintf('【3. 贝叶斯后验概率分析】\n');
fprintf('─────────────────────────────────────────\n');

% 3.1 计算通过测试条件下，各子系统实际有问题的后验概率
P_problem_given_pass = struct();
for i = 1:length(systems)
    sys = systems{i};
    P_problem_given_pass.(sys) = (p.(sys) * alpha.(sys)) / P_pass.(sys);
    fprintf('P(%s有问题|通过%s测试) = %.6f (%.3f%%)\n', ...
        sys, sys, P_problem_given_pass.(sys), P_problem_given_pass.(sys)*100);
end

% 3.2 加入D系统
P_problem_given_pass.D = p.D;
fprintf('P(D有问题) = %.6f (%.3f%%)\n', p.D, p.D*100);
fprintf('─────────────────────────────────────────\n\n');

%% ========== 第四部分：λ参数计算 ==========
fprintf('【4. λ参数计算（问题指向性比例）】\n');
fprintf('─────────────────────────────────────────\n');

% 4.1 计算权重
weights = [P_problem_given_pass.A, P_problem_given_pass.B, ...
           P_problem_given_pass.C, P_problem_given_pass.D];
sum_weights = sum(weights);

% 4.2 归一化得到λ参数
lambda = weights / sum_weights;
lambda_1 = lambda(1);
lambda_2 = lambda(2);
lambda_3 = lambda(3);
lambda_4 = lambda(4);

fprintf('权重分析：\n');
fprintf('  w_A = %.6f    w_B = %.6f\n', weights(1), weights(2));
fprintf('  w_C = %.6f    w_D = %.6f\n', weights(3), weights(4));
fprintf('  Σw = %.6f\n\n', sum_weights);

fprintf('λ参数（归一化后）：\n');
fprintf('  λ₁ = %.6f (%.2f%%) - 指向A系统\n', lambda_1, lambda_1*100);
fprintf('  λ₂ = %.6f (%.2f%%) - 指向B系统\n', lambda_2, lambda_2*100);
fprintf('  λ₃ = %.6f (%.2f%%) - 指向C系统\n', lambda_3, lambda_3*100);
fprintf('  λ₄ = %.6f (%.2f%%) - 指向D系统\n', lambda_4, lambda_4*100);
fprintf('  Σλᵢ = %.6f (验证归一化)\n', sum(lambda));
fprintf('─────────────────────────────────────────\n\n');

%% ========== 第五部分：综合测试检出概率（修正版）==========
fprintf('【5. 综合测试E的检出概率分析（修正版）】\n');
fprintf('─────────────────────────────────────────\n');

% 5.1 计算系统存在问题的总概率
P_any_problem = 1 - (1-P_problem_given_pass.A) * (1-P_problem_given_pass.B) * ...
                    (1-P_problem_given_pass.C) * (1-P_problem_given_pass.D);
P_no_problem = 1 - P_any_problem;

fprintf('进入E测试时的系统状态：\n');
fprintf('  P(系统有问题) = %.6f (%.3f%%)\n', P_any_problem, P_any_problem*100);
fprintf('  P(系统无问题) = %.6f (%.3f%%)\n\n', P_no_problem, P_no_problem*100);

% 5.2 正确计算E组的漏判率和误判率
% 根据误判漏判各占总差错50%的约束
alpha_E = (0.5 * e.E) / P_any_problem;  % 有问题时的漏判率
beta_E = (0.5 * e.E) / P_no_problem;    % 无问题时的误判率

fprintf('E组测手差错参数（修正版）：\n');
fprintf('  漏判率 α_E = %.6f (%.2f%%)\n', alpha_E, alpha_E*100);
fprintf('  误判率 β_E = %.6f (%.2f%%)\n', beta_E, beta_E*100);

% 验证总差错率
total_error_E = P_any_problem * alpha_E + P_no_problem * beta_E;
fprintf('  验证总差错率：%.6f ≈ %.6f ✓\n\n', total_error_E, e.E);

% 5.3 计算E测试的四种结果概率
P_TP = P_any_problem * (1 - alpha_E);  % 真阳性
P_FN = P_any_problem * alpha_E;        % 假阴性
P_TN = P_no_problem * (1 - beta_E);    % 真阴性
P_FP = P_no_problem * beta_E;          % 假阳性

fprintf('E测试的四种可能结果：\n');
fprintf('  真阳性(TP): P = %.6f (%.3f%%)\n', P_TP, P_TP*100);
fprintf('  假阴性(FN): P = %.6f (%.3f%%)\n', P_FN, P_FN*100);
fprintf('  真阴性(TN): P = %.6f (%.3f%%)\n', P_TN, P_TN*100);
fprintf('  假阳性(FP): P = %.6f (%.3f%%)\n', P_FP, P_FP*100);
fprintf('  验证Σ = %.6f\n\n', P_TP + P_FN + P_TN + P_FP);

% 5.4 综合测试报告有问题的总概率
P_E_report_problem = P_TP + P_FP;
fprintf('E测试报告有问题的总概率：\n');
fprintf('  P(E报告有问题) = P(TP) + P(FP)\n');
fprintf('                  = %.6f + %.6f\n', P_TP, P_FP);
fprintf('                  = %.6f (%.3f%%)\n', P_E_report_problem, P_E_report_problem*100);
fprintf('─────────────────────────────────────────\n\n');

%% ========== 第六部分：性能指标计算 ==========
fprintf('【6. E测试性能指标评估】\n');
fprintf('─────────────────────────────────────────\n');

% 计算各项性能指标
metrics = struct();
metrics.sensitivity = P_TP / P_any_problem;           % 灵敏度
metrics.specificity = P_TN / P_no_problem;           % 特异度
metrics.accuracy = P_TP + P_TN;                      % 准确率
metrics.precision = P_TP / P_E_report_problem;       % 精确率
metrics.F1_score = 2 * metrics.precision * metrics.sensitivity / ...
                   (metrics.precision + metrics.sensitivity);  % F1分数
metrics.FPR = P_FP / P_no_problem;                   % 假阳性率
metrics.FNR = P_FN / P_any_problem;                  % 假阴性率

fprintf('性能指标：\n');
fprintf('  灵敏度(Sensitivity/TPR) = %.2f%%\n', metrics.sensitivity*100);
fprintf('  特异度(Specificity/TNR) = %.2f%%\n', metrics.specificity*100);
fprintf('  准确率(Accuracy)        = %.2f%%\n', metrics.accuracy*100);
fprintf('  精确率(Precision/PPV)   = %.2f%%\n', metrics.precision*100);
fprintf('  F1分数                  = %.4f\n', metrics.F1_score);
fprintf('  假阳性率(FPR)           = %.2f%%\n', metrics.FPR*100);
fprintf('  假阴性率(FNR)           = %.2f%%\n', metrics.FNR*100);
fprintf('─────────────────────────────────────────\n\n');

%% ========== 第七部分：信息论分析 ==========
fprintf('【7. 信息论分析】\n');
fprintf('─────────────────────────────────────────\n');

% 7.1 计算λ分布的信息熵
H_lambda = -sum(lambda .* log2(lambda + eps));
H_uniform = -4 * 0.25 * log2(0.25);  % 均匀分布的熵

fprintf('信息熵分析：\n');
fprintf('  H(λ) = %.4f bits\n', H_lambda);
fprintf('  H(均匀分布) = %.4f bits\n', H_uniform);
fprintf('  相对熵效率 = %.2f%%\n', (H_lambda/H_uniform)*100);
fprintf('  冗余度 = %.2f%%\n', (1 - H_lambda/H_uniform)*100);

% 7.2 计算互信息
% I(X;Y) = H(Y) - H(Y|X)
H_Y = -P_E_report_problem * log2(P_E_report_problem + eps) - ...
      (1-P_E_report_problem) * log2(1-P_E_report_problem + eps);
H_Y_given_X = P_any_problem * (-alpha_E * log2(alpha_E + eps) - ...
              (1-alpha_E) * log2(1-alpha_E + eps)) + ...
              P_no_problem * (-beta_E * log2(beta_E + eps) - ...
              (1-beta_E) * log2(1-beta_E + eps));
I_XY = H_Y - H_Y_given_X;

fprintf('\n互信息分析：\n');
fprintf('  H(Y) = %.4f bits\n', H_Y);
fprintf('  H(Y|X) = %.4f bits\n', H_Y_given_X);
fprintf('  I(X;Y) = %.4f bits\n', I_XY);
fprintf('─────────────────────────────────────────\n\n');

%% ========== 第八部分：最终结果汇总 ==========
fprintf('╔════════════════════════════════════════════════════════╗\n');
fprintf('║                    最终计算结果汇总                    ║\n');
fprintf('╠════════════════════════════════════════════════════════╣\n');
fprintf('║ λ参数：                                                ║\n');
fprintf('║   λ₁ = %.6f (A系统)                                  ║\n', lambda_1);
fprintf('║   λ₂ = %.6f (B系统)                                  ║\n', lambda_2);
fprintf('║   λ₃ = %.6f (C系统)                                  ║\n', lambda_3);
fprintf('║   λ₄ = %.6f (D系统)                                  ║\n', lambda_4);
fprintf('║                                                        ║\n');
fprintf('║ 综合测试检出概率：                                     ║\n');
fprintf('║   P(E检出问题) = %.6f (%.2f%%)                      ║\n', ...
    P_E_report_problem, P_E_report_problem*100);
fprintf('║                                                        ║\n');
fprintf('║ 关键性能指标：                                         ║\n');
fprintf('║   灵敏度 = %.2f%%    特异度 = %.2f%%                ║\n', ...
    metrics.sensitivity*100, metrics.specificity*100);
fprintf('║   F1分数 = %.4f     信息熵 = %.4f bits             ║\n', ...
    metrics.F1_score, H_lambda);
fprintf('╚════════════════════════════════════════════════════════╝\n\n');

%% ========== 第九部分：数据保存 ==========
% 9.1 整理所有结果
results = struct();
results.params = struct('p', p, 'e', e);
results.subsystem = struct('alpha', alpha, 'beta', beta, 'P_pass', P_pass);
results.posterior = P_problem_given_pass;
results.lambda = struct('values', lambda, 'lambda_1', lambda_1, ...
                       'lambda_2', lambda_2, 'lambda_3', lambda_3, ...
                       'lambda_4', lambda_4);
results.E_test = struct('P_any_problem', P_any_problem, ...
                       'alpha_E', alpha_E, 'beta_E', beta_E, ...
                       'P_report', P_E_report_problem, ...
                       'P_TP', P_TP, 'P_FN', P_FN, ...
                       'P_TN', P_TN, 'P_FP', P_FP);
results.metrics = metrics;
results.information = struct('H_lambda', H_lambda, 'I_XY', I_XY);

% 9.2 保存数据
save('problem1_results.mat', 'results');
fprintf('所有结果已保存至 problem1_results.mat\n\n');

%% ========== 第十部分：生成LaTeX表格代码 ==========
fprintf('【LaTeX表格代码（用于论文）】\n');
fprintf('─────────────────────────────────────────\n');

% 表1：λ参数和问题概率
fprintf('\\begin{table}[H]\n');
fprintf('\\centering\n');
fprintf('\\caption{综合测试概率参数计算结果}\n');
fprintf('\\label{tab:lambda_params}\n');
fprintf('\\begin{tabular}{lcccc}\n');
fprintf('\\toprule\n');
fprintf('参数 & A系统 & B系统 & C系统 & D系统 \\\\\n');
fprintf('\\midrule\n');
fprintf('固有问题概率 & %.1f\\%% & %.1f\\%% & %.1f\\%% & %.1f\\%% \\\\\n', ...
    p.A*100, p.B*100, p.C*100, p.D*100);
fprintf('漏判率 & %.1f\\%% & %.1f\\%% & %.1f\\%% & - \\\\\n', ...
    alpha.A*100, alpha.B*100, alpha.C*100);
fprintf('后验问题概率 & %.2f\\%% & %.2f\\%% & %.2f\\%% & %.2f\\%% \\\\\n', ...
    P_problem_given_pass.A*100, P_problem_given_pass.B*100, ...
    P_problem_given_pass.C*100, P_problem_given_pass.D*100);
fprintf('$\\lambda_i$ & %.4f & %.4f & %.4f & %.4f \\\\\n', ...
    lambda_1, lambda_2, lambda_3, lambda_4);
fprintf('\\bottomrule\n');
fprintf('\\end{tabular}\n');
fprintf('\\end{table}\n\n');

% 表2：性能指标
fprintf('\\begin{table}[H]\n');
fprintf('\\centering\n');
fprintf('\\caption{综合测试E的性能指标}\n');
fprintf('\\label{tab:performance}\n');
fprintf('\\begin{tabular}{lc}\n');
fprintf('\\toprule\n');
fprintf('性能指标 & 数值 \\\\\n');
fprintf('\\midrule\n');
fprintf('灵敏度(Sensitivity) & %.2f\\%% \\\\\n', metrics.sensitivity*100);
fprintf('特异度(Specificity) & %.2f\\%% \\\\\n', metrics.specificity*100);
fprintf('准确率(Accuracy) & %.2f\\%% \\\\\n', metrics.accuracy*100);
fprintf('精确率(Precision) & %.2f\\%% \\\\\n', metrics.precision*100);
fprintf('F1分数 & %.4f \\\\\n', metrics.F1_score);
fprintf('信息熵H($\\lambda$) & %.4f bits \\\\\n', H_lambda);
fprintf('\\bottomrule\n');
fprintf('\\end{tabular}\n');
fprintf('\\end{table}\n');

fprintf('\n程序运行完成！\n');
fprintf('接下来请运行 problem1_advanced.m 进行高级分析\n');
fprintf('然后运行 problem1_visualization.m 生成专业图表\n');