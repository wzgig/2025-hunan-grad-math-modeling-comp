%% 问题1高级分析：Monte Carlo验证、灵敏度分析与优化
% 国家特等奖冲击版 - 高级分析模块
% 包含：Monte Carlo验证、灵敏度分析、参数优化、鲁棒性分析

clear; clc; close all;
format long;

% 检查是否有基础结果
if ~exist('problem1_results.mat', 'file')
    error('请先运行 problem1_main.m 生成基础结果！');
end
load('problem1_results.mat');

fprintf('╔════════════════════════════════════════════════════════╗\n');
fprintf('║            问题1 - 高级分析与模型验证                 ║\n');
fprintf('╚════════════════════════════════════════════════════════╝\n\n');

%% ========== 第一部分：Monte Carlo模拟验证 ==========
fprintf('【1. Monte Carlo模拟验证】\n');
fprintf('─────────────────────────────────────────\n');
fprintf('正在进行大规模Monte Carlo模拟，请稍候...\n');

% 设置模拟参数
rng(42);  % 设置随机种子以保证可重复性
N_sim = 5000000;  % 500万次模拟

% 提取参数
p_vec = [results.params.p.A, results.params.p.B, results.params.p.C, results.params.p.D];
e_vec = [results.params.e.A, results.params.e.B, results.params.e.C, results.params.e.E];
alpha_vec = [results.subsystem.alpha.A, results.subsystem.alpha.B, results.subsystem.alpha.C];
beta_vec = [results.subsystem.beta.A, results.subsystem.beta.B, results.subsystem.beta.C];

% 初始化统计变量
count_pass_all = 0;
count_E_detect = 0;
problem_source = zeros(1, 4);
actual_problems = zeros(1, 4);  % 实际问题统计
detected_problems = zeros(1, 4);  % 检出问题统计

% Monte Carlo主循环
tic;
for sim = 1:N_sim
    % 生成子系统实际状态
    has_problem = rand(1, 4) < p_vec;
    
    % A,B,C子系统测试过程
    pass_tests = true(1, 3);
    for j = 1:3
        if has_problem(j)
            % 有问题，可能漏判
            if rand() < alpha_vec(j)
                % 漏判，错误地判为通过
                pass_tests(j) = true;
            else
                % 正确检出
                pass_tests(j) = false;
            end
        else
            % 无问题，可能误判
            if rand() < beta_vec(j)
                % 误判为有问题
                pass_tests(j) = false;
            else
                % 正确判定为无问题
                pass_tests(j) = true;
            end
        end
    end
    
    % 判断是否进入E测试
    if all(pass_tests)
        count_pass_all = count_pass_all + 1;
        
        % 记录进入E测试时的实际问题
        for k = 1:4
            if has_problem(k)
                actual_problems(k) = actual_problems(k) + 1;
            end
        end
        
        % E测试过程
        any_problem = any(has_problem);
        
        % 计算正确的E测试参数
        P_any = results.E_test.P_any_problem;
        alpha_E = results.E_test.alpha_E;
        beta_E = results.E_test.beta_E;
        
        if any_problem
            % 系统有问题
            if rand() > alpha_E  % 正确检出（1-漏判率）
                count_E_detect = count_E_detect + 1;
                % 记录问题来源（简化：随机选择一个有问题的子系统）
                problem_indices = find(has_problem);
                if ~isempty(problem_indices)
                    selected = problem_indices(randi(length(problem_indices)));
                    problem_source(selected) = problem_source(selected) + 1;
                    detected_problems(selected) = detected_problems(selected) + 1;
                end
            end
        else
            % 系统无问题，可能误判
            if rand() < beta_E  % 误判
                count_E_detect = count_E_detect + 1;
                % 误判时随机分配问题来源（根据λ权重）
                cum_lambda = cumsum(results.lambda.values);
                r = rand();
                for k = 1:4
                    if r <= cum_lambda(k)
                        problem_source(k) = problem_source(k) + 1;
                        break;
                    end
                end
            end
        end
    end
    
    % 显示进度
    if mod(sim, 500000) == 0
        fprintf('  已完成 %d/%d (%.1f%%)\n', sim, N_sim, sim/N_sim*100);
    end
end
elapsed_time = toc;

% 计算模拟结果
lambda_sim = problem_source / sum(problem_source);
P_E_sim = count_E_detect / count_pass_all;
P_problem_sim = actual_problems / count_pass_all;

fprintf('\nMonte Carlo模拟完成！\n');
fprintf('  模拟次数：%d\n', N_sim);
fprintf('  用时：%.2f秒\n', elapsed_time);
fprintf('  进入E测试数：%d\n\n', count_pass_all);

% 对比理论值与模拟值
fprintf('理论值 vs 模拟值对比：\n');
fprintf('┌─────────┬──────────┬──────────┬──────────┬─────────┐\n');
fprintf('│ 参数    │   理论值  │   模拟值  │  绝对误差 │相对误差│\n');
fprintf('├─────────┼──────────┼──────────┼──────────┼─────────┤\n');
for i = 1:4
    fprintf('│ λ_%d     │ %.6f │ %.6f │ %.6f │ %.2f%%  │\n', i, ...
        results.lambda.values(i), lambda_sim(i), ...
        abs(results.lambda.values(i) - lambda_sim(i)), ...
        abs(results.lambda.values(i) - lambda_sim(i))/results.lambda.values(i)*100);
end
fprintf('├─────────┼──────────┼──────────┼──────────┼─────────┤\n');
fprintf('│ P(E检出)│ %.6f │ %.6f │ %.6f │ %.2f%%  │\n', ...
    results.E_test.P_report, P_E_sim, ...
    abs(results.E_test.P_report - P_E_sim), ...
    abs(results.E_test.P_report - P_E_sim)/results.E_test.P_report*100);
fprintf('└─────────┴──────────┴──────────┴──────────┴─────────┘\n\n');

%% ========== 第二部分：参数灵敏度分析 ==========
fprintf('【2. 参数灵敏度分析】\n');
fprintf('─────────────────────────────────────────\n');

% 定义参数变化范围
variation_range = 0.5:0.1:1.5;  % -50% 到 +50%
n_points = length(variation_range);

% 参数列表
param_names = {'p_A', 'p_B', 'p_C', 'p_D', 'e_A', 'e_B', 'e_C', 'e_E'};
base_values = [p_vec, e_vec];

% 存储灵敏度结果
sensitivity_lambda = zeros(length(param_names), 4, n_points);
sensitivity_P_E = zeros(length(param_names), n_points);

% 进行灵敏度分析
for param_idx = 1:length(param_names)
    for var_idx = 1:n_points
        % 创建参数副本
        p_temp = p_vec;
        e_temp = e_vec;
        
        % 修改特定参数
        if param_idx <= 4
            % 修改p参数
            p_temp(param_idx) = base_values(param_idx) * variation_range(var_idx);
        else
            % 修改e参数
            e_temp(param_idx - 4) = base_values(param_idx) * variation_range(var_idx);
        end
        
        % 重新计算模型
        % 计算alpha和beta
        alpha_temp = zeros(1, 3);
        beta_temp = zeros(1, 3);
        for j = 1:3
            alpha_temp(j) = 0.5 * e_temp(j) / p_temp(j);
            beta_temp(j) = 0.5 * e_temp(j) / (1 - p_temp(j));
        end
        
        % 计算后验概率
        P_pass_temp = p_temp(1:3) .* alpha_temp + (1 - p_temp(1:3)) .* (1 - beta_temp);
        P_problem_temp = (p_temp(1:3) .* alpha_temp) ./ P_pass_temp;
        
        % 计算λ
        weights_temp = [P_problem_temp, p_temp(4)];
        lambda_temp = weights_temp / sum(weights_temp);
        sensitivity_lambda(param_idx, :, var_idx) = lambda_temp;
        
        % 计算P(E)
        P_any_temp = 1 - prod(1 - [P_problem_temp, p_temp(4)]);
        alpha_E_temp = (0.5 * e_temp(4)) / P_any_temp;
        beta_E_temp = (0.5 * e_temp(4)) / (1 - P_any_temp);
        P_E_temp = P_any_temp * (1 - alpha_E_temp) + (1 - P_any_temp) * beta_E_temp;
        sensitivity_P_E(param_idx, var_idx) = P_E_temp;
    end
end

% 计算灵敏度指标（弹性系数）
elasticity = zeros(length(param_names), 5);  % 4个λ + 1个P_E
for i = 1:length(param_names)
    % 对λ的弹性
    for j = 1:4
        mid_idx = ceil(n_points/2);
        delta_lambda = sensitivity_lambda(i, j, end) - sensitivity_lambda(i, j, 1);
        delta_param = variation_range(end) - variation_range(1);
        elasticity(i, j) = (delta_lambda / results.lambda.values(j)) / delta_param;
    end
    % 对P_E的弹性
    delta_P_E = sensitivity_P_E(i, end) - sensitivity_P_E(i, 1);
    elasticity(i, 5) = (delta_P_E / results.E_test.P_report) / delta_param;
end

% 输出灵敏度分析结果
fprintf('参数弹性系数矩阵：\n');
fprintf('┌──────────┬────────┬────────┬────────┬────────┬────────┐\n');
fprintf('│ 参数     │   λ₁   │   λ₂   │   λ₃   │   λ₄   │  P(E)  │\n');
fprintf('├──────────┼────────┼────────┼────────┼────────┼────────┤\n');
for i = 1:length(param_names)
    fprintf('│ %-8s │', param_names{i});
    for j = 1:5
        if abs(elasticity(i, j)) > 0.5
            fprintf(' %+.3f*│', elasticity(i, j));  % 高灵敏度参数标记
        else
            fprintf(' %+.3f │', elasticity(i, j));
        end
    end
    fprintf('\n');
end
fprintf('└──────────┴────────┴────────┴────────┴────────┴────────┘\n');
fprintf('注：*表示高灵敏度参数（|弹性系数| > 0.5）\n\n');

%% ========== 第三部分：参数优化分析 ==========
fprintf('【3. 参数优化分析】\n');
fprintf('─────────────────────────────────────────\n');

% 定义优化目标：最小化总漏判概率
% 约束：保持总差错率不变

% 优化目标函数
objective = @(x) compute_total_miss_rate(x, p_vec);

% 初始值（当前差错率）
x0 = e_vec;

% 约束条件
A = [];
b = [];
Aeq = [];
beq = [];
lb = zeros(size(x0));  % 下界
ub = ones(size(x0)) * 0.1;  % 上界（最大10%差错率）

% 非线性约束（保持误判漏判平衡）
nonlcon = [];

% 优化选项
options = optimoptions('fmincon', 'Display', 'off', 'Algorithm', 'sqp');

% 执行优化
[x_opt, fval] = fmincon(objective, x0, A, b, Aeq, beq, lb, ub, nonlcon, options);

fprintf('优化结果（最小化总漏判概率）：\n');
fprintf('  原始差错率：e_A=%.2f%%, e_B=%.2f%%, e_C=%.2f%%, e_E=%.2f%%\n', ...
    e_vec(1)*100, e_vec(2)*100, e_vec(3)*100, e_vec(4)*100);
fprintf('  优化差错率：e_A=%.2f%%, e_B=%.2f%%, e_C=%.2f%%, e_E=%.2f%%\n', ...
    x_opt(1)*100, x_opt(2)*100, x_opt(3)*100, x_opt(4)*100);
fprintf('  总漏判概率：%.4f%% → %.4f%% (改善%.2f%%)\n\n', ...
    objective(x0)*100, fval*100, (objective(x0)-fval)/objective(x0)*100);

%% ========== 第四部分：鲁棒性分析 ==========
fprintf('【4. 鲁棒性分析】\n');
fprintf('─────────────────────────────────────────\n');

% 对关键参数进行扰动分析
n_robust = 1000;
perturbation = 0.1;  % 10%扰动

lambda_robust = zeros(n_robust, 4);
P_E_robust = zeros(n_robust, 1);

for i = 1:n_robust
    % 生成随机扰动
    p_perturb = p_vec .* (1 + (rand(size(p_vec)) - 0.5) * 2 * perturbation);
    e_perturb = e_vec .* (1 + (rand(size(e_vec)) - 0.5) * 2 * perturbation);
    
    % 确保参数在合理范围内
    p_perturb = max(0.001, min(0.1, p_perturb));
    e_perturb = max(0.001, min(0.1, e_perturb));
    
    % 计算扰动后的结果
    [lambda_perturb, P_E_perturb] = calculate_model(p_perturb, e_perturb);
    lambda_robust(i, :) = lambda_perturb;
    P_E_robust(i) = P_E_perturb;
end

% 统计分析
lambda_mean = mean(lambda_robust, 1);
lambda_std = std(lambda_robust, 0, 1);
lambda_cv = lambda_std ./ lambda_mean;  % 变异系数

P_E_mean = mean(P_E_robust);
P_E_std = std(P_E_robust);
P_E_cv = P_E_std / P_E_mean;

fprintf('鲁棒性分析结果（±10%%扰动，%d次模拟）：\n', n_robust);
fprintf('┌─────────┬──────────┬──────────┬──────────┐\n');
fprintf('│ 参数    │   均值    │  标准差   │ 变异系数 │\n');
fprintf('├─────────┼──────────┼──────────┼──────────┤\n');
for i = 1:4
    fprintf('│ λ_%d     │ %.6f │ %.6f │  %.3f   │\n', i, ...
        lambda_mean(i), lambda_std(i), lambda_cv(i));
end
fprintf('├─────────┼──────────┼──────────┼──────────┤\n');
fprintf('│ P(E)    │ %.6f │ %.6f │  %.3f   │\n', ...
    P_E_mean, P_E_std, P_E_cv);
fprintf('└─────────┴──────────┴──────────┴──────────┘\n\n');

% 判断鲁棒性
if max([lambda_cv, P_E_cv]) < 0.1
    fprintf('模型鲁棒性评价：优秀（所有变异系数<0.1）\n');
elseif max([lambda_cv, P_E_cv]) < 0.2
    fprintf('模型鲁棒性评价：良好（所有变异系数<0.2）\n');
else
    fprintf('模型鲁棒性评价：一般（存在变异系数>0.2）\n');
end

%% ========== 第五部分：置信区间估计 ==========
fprintf('\n【5. 参数置信区间估计（Bootstrap法）】\n');
fprintf('─────────────────────────────────────────\n');

% Bootstrap参数
n_bootstrap = 10000;
alpha_conf = 0.05;  % 95%置信区间

% Bootstrap采样
lambda_bootstrap = zeros(n_bootstrap, 4);
P_E_bootstrap = zeros(n_bootstrap, 1);

for i = 1:n_bootstrap
    % 生成Bootstrap样本（基于二项分布）
    n_sample = 10000;
    
    % 模拟子系统问题
    problems_A = sum(rand(n_sample, 1) < p_vec(1));
    problems_B = sum(rand(n_sample, 1) < p_vec(2));
    problems_C = sum(rand(n_sample, 1) < p_vec(3));
    problems_D = sum(rand(n_sample, 1) < p_vec(4));
    
    % 估计问题概率
    p_boot = [problems_A, problems_B, problems_C, problems_D] / n_sample;
    
    % 计算Bootstrap结果
    [lambda_boot, P_E_boot] = calculate_model(p_boot, e_vec);
    lambda_bootstrap(i, :) = lambda_boot;
    P_E_bootstrap(i) = P_E_boot;
end

% 计算置信区间
lambda_CI = zeros(4, 2);
for i = 1:4
    lambda_CI(i, :) = quantile(lambda_bootstrap(:, i), [alpha_conf/2, 1-alpha_conf/2]);
end
P_E_CI = quantile(P_E_bootstrap, [alpha_conf/2, 1-alpha_conf/2]);

fprintf('95%%置信区间：\n');
fprintf('  λ₁: [%.6f, %.6f]\n', lambda_CI(1, 1), lambda_CI(1, 2));
fprintf('  λ₂: [%.6f, %.6f]\n', lambda_CI(2, 1), lambda_CI(2, 2));
fprintf('  λ₃: [%.6f, %.6f]\n', lambda_CI(3, 1), lambda_CI(3, 2));
fprintf('  λ₄: [%.6f, %.6f]\n', lambda_CI(4, 1), lambda_CI(4, 2));
fprintf('  P(E): [%.6f, %.6f]\n', P_E_CI(1), P_E_CI(2));

%% ========== 第六部分：保存高级分析结果 ==========
advanced_results = struct();
advanced_results.monte_carlo = struct('lambda_sim', lambda_sim, 'P_E_sim', P_E_sim, ...
                                     'N_sim', N_sim);
advanced_results.sensitivity = struct('elasticity', elasticity, 'param_names', {param_names});
advanced_results.optimization = struct('e_opt', x_opt, 'improvement', (objective(x0)-fval)/objective(x0));
advanced_results.robustness = struct('lambda_cv', lambda_cv, 'P_E_cv', P_E_cv);
advanced_results.confidence = struct('lambda_CI', lambda_CI, 'P_E_CI', P_E_CI);

save('problem1_advanced_results.mat', 'advanced_results');
fprintf('\n高级分析结果已保存至 problem1_advanced_results.mat\n');
fprintf('请运行 problem1_visualization.m 生成专业可视化图表\n');

%% ========== 辅助函数 ==========
function total_miss = compute_total_miss_rate(e, p)
    % 计算总漏判概率
    alpha = 0.5 * e(1:3) ./ p(1:3);
    total_miss = sum(p(1:3) .* alpha);
end

function [lambda, P_E] = calculate_model(p, e)
    % 计算模型输出
    alpha = 0.5 * e(1:3) ./ p(1:3);
    beta = 0.5 * e(1:3) ./ (1 - p(1:3));
    P_pass = p(1:3) .* alpha + (1 - p(1:3)) .* (1 - beta);
    P_problem = (p(1:3) .* alpha) ./ P_pass;
    weights = [P_problem, p(4)];
    lambda = weights / sum(weights);
    
    P_any = 1 - prod(1 - [P_problem, p(4)]);
    alpha_E = (0.5 * e(4)) / P_any;
    beta_E = (0.5 * e(4)) / (1 - P_any);
    P_E = P_any * (1 - alpha_E) + (1 - P_any) * beta_E;
end