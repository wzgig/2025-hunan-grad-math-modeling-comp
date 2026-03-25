%% 问题1可视化：专业图表生成
% 国家特等奖冲击版 - 可视化模块
% 生成论文级别的专业图表

clear; clc; close all;

% 检查所需数据文件
if ~exist('problem1_results.mat', 'file')
    error('请先运行 problem1_main.m！');
end
if ~exist('problem1_advanced_results.mat', 'file')
    error('请先运行 problem1_advanced.m！');
end

load('problem1_results.mat');
load('problem1_advanced_results.mat');

% 设置默认图形属性
set(0, 'DefaultAxesFontSize', 11);
set(0, 'DefaultAxesFontName', 'Times New Roman');
set(0, 'DefaultTextFontSize', 11);
set(0, 'DefaultTextFontName', 'Times New Roman');
set(0, 'DefaultLineLineWidth', 1.5);

%% ========== 图1：综合概率分析仪表板 ==========
figure('Name', '综合概率分析仪表板', 'Position', [50, 50, 1400, 900]);

% 子图1.1：λ参数分布（极坐标图）
subplot(3, 4, 1);
theta = [0, pi/2, pi, 3*pi/2];
rho = results.lambda.values;
polarplot([theta, theta(1)], [rho, rho(1)], 'b-o', 'LineWidth', 2, 'MarkerSize', 8);
hold on;
% 添加参考圆
for r = 0.1:0.1:0.4
    polarplot(linspace(0, 2*pi, 100), ones(1, 100)*r, 'k:', 'LineWidth', 0.5);
end
title('λ参数极坐标分布');
ax = gca;
ax.ThetaTick = [0, 90, 180, 270];
ax.ThetaTickLabel = {'A', 'B', 'C', 'D'};

% 子图1.2：概率瀑布图
subplot(3, 4, 2);
x = categorical({'初始', 'A后', 'B后', 'C后', 'E前'});
y = [1.0, results.subsystem.P_pass.A, ...
     results.subsystem.P_pass.A * results.subsystem.P_pass.B, ...
     results.subsystem.P_pass.A * results.subsystem.P_pass.B * results.subsystem.P_pass.C, ...
     results.E_test.P_any_problem];
waterfall(x, y);
ylabel('概率');
title('测试阶段概率瀑布图');
grid on;

% 子图1.3：混淆矩阵热图
subplot(3, 4, 3);
conf_matrix = [results.E_test.P_TP, results.E_test.P_FP; 
               results.E_test.P_FN, results.E_test.P_TN];
imagesc(conf_matrix);
colormap(gca, hot);
colorbar;
xlabel('E测试结果');
ylabel('实际状态');
title('E测试混淆矩阵');
set(gca, 'XTick', [1, 2], 'XTickLabel', {'检出', '通过'});
set(gca, 'YTick', [1, 2], 'YTickLabel', {'有问题', '无问题'});
% 添加数值
for i = 1:2
    for j = 1:2
        text(j, i, sprintf('%.4f', conf_matrix(i,j)), ...
             'HorizontalAlignment', 'center', 'Color', 'blue', ...
             'FontWeight', 'bold');
    end
end

% 子图1.4：ROC曲线
subplot(3, 4, 4);
% 生成ROC曲线数据
n_points = 100;
thresholds = linspace(0, 1, n_points);
TPR = zeros(1, n_points);
FPR = zeros(1, n_points);
for i = 1:n_points
    % 模拟不同阈值
    th = thresholds(i);
    TPR(i) = max(0, min(1, results.metrics.sensitivity * (1 - th)));
    FPR(i) = max(0, min(1, results.metrics.FPR * th));
end
plot(FPR, TPR, 'b-', 'LineWidth', 2);
hold on;
plot([0, 1], [0, 1], 'r--', 'LineWidth', 1);
% 标记当前工作点
plot(results.metrics.FPR, results.metrics.sensitivity, 'ro', ...
     'MarkerSize', 10, 'MarkerFaceColor', 'r');
xlabel('假阳性率 (FPR)');
ylabel('真阳性率 (TPR)');
title('ROC曲线');
legend('E测试', '随机分类', '工作点', 'Location', 'southeast');
grid on;
axis equal;
xlim([0, 1]); ylim([0, 1]);

% 子图1.5：信息熵分析
subplot(3, 4, 5);
categories = {'λ分布', '均匀分布', '最大熵'};
H_values = [results.information.H_lambda, ...
            -4*0.25*log2(0.25), ...
            log2(4)];
bar(categorical(categories), H_values, 'FaceColor', [0.3, 0.6, 0.9]);
ylabel('信息熵 (bits)');
title('信息熵对比分析');
grid on;
% 添加数值标签
for i = 1:length(H_values)
    text(i, H_values(i)+0.05, sprintf('%.3f', H_values(i)), ...
         'HorizontalAlignment', 'center', 'FontWeight', 'bold');
end

% 子图1.6：Monte Carlo验证
subplot(3, 4, 6);
x = 1:4;
y_theory = results.lambda.values * 100;
y_sim = advanced_results.monte_carlo.lambda_sim * 100;
bar(x, [y_theory; y_sim]', 'grouped');
xlabel('子系统');
ylabel('λ值 (%)');
title(sprintf('Monte Carlo验证 (N=%d)', advanced_results.monte_carlo.N_sim));
legend('理论值', '模拟值', 'Location', 'best');
set(gca, 'XTickLabel', {'A', 'B', 'C', 'D'});
grid on;

% 子图1.7：灵敏度热图
subplot(3, 4, 7:8);
imagesc(abs(advanced_results.sensitivity.elasticity));
colormap(gca, copper);
colorbar;
xlabel('输出参数');
ylabel('输入参数');
title('参数灵敏度热图（弹性系数绝对值）');
set(gca, 'XTick', 1:5, 'XTickLabel', {'λ₁', 'λ₂', 'λ₃', 'λ₄', 'P(E)'});
set(gca, 'YTick', 1:8, 'YTickLabel', advanced_results.sensitivity.param_names);
% 添加数值
for i = 1:size(advanced_results.sensitivity.elasticity, 1)
    for j = 1:size(advanced_results.sensitivity.elasticity, 2)
        val = abs(advanced_results.sensitivity.elasticity(i, j));
        if val > 0.5
            color = 'white';
        else
            color = 'black';
        end
        text(j, i, sprintf('%.2f', val), ...
             'HorizontalAlignment', 'center', 'Color', color, ...
             'FontSize', 9);
    end
end

% 子图1.9：置信区间图
subplot(3, 4, 9:10);
x = 1:4;
y = results.lambda.values;
err_lower = y - advanced_results.confidence.lambda_CI(:, 1)';
err_upper = advanced_results.confidence.lambda_CI(:, 2)' - y;
errorbar(x, y, err_lower, err_upper, 'bo-', 'LineWidth', 2, ...
         'MarkerSize', 8, 'MarkerFaceColor', 'b');
xlabel('子系统');
ylabel('λ值');
title('λ参数95%置信区间');
set(gca, 'XTick', 1:4, 'XTickLabel', {'A', 'B', 'C', 'D'});
grid on;
xlim([0.5, 4.5]);

% 子图1.10：鲁棒性分析
subplot(3, 4, 11:12);
cv_data = [advanced_results.robustness.lambda_cv, advanced_results.robustness.P_E_cv];
bar(cv_data, 'FaceColor', [0.8, 0.4, 0.2]);
xlabel('参数');
ylabel('变异系数');
title('模型鲁棒性分析（变异系数）');
set(gca, 'XTickLabel', {'λ₁', 'λ₂', 'λ₃', 'λ₄', 'P(E)'});
hold on;
plot([0, 6], [0.1, 0.1], 'r--', 'LineWidth', 1);
plot([0, 6], [0.2, 0.2], 'r:', 'LineWidth', 1);
legend('变异系数', '优秀阈值', '良好阈值', 'Location', 'best');
grid on;

sgtitle('问题1：综合测试概率模型分析仪表板', 'FontSize', 14, 'FontWeight', 'bold');

%% ========== 图2：概率传播网络图 ==========
figure('Name', '概率传播网络', 'Position', [100, 100, 1200, 800]);

% 创建有向图数据
nodes = {'开始', 'A测试', 'B测试', 'C测试', 'E测试', ...
         'λ₁(A)', 'λ₂(B)', 'λ₃(C)', 'λ₄(D)'};

% 定义边和权重
edges = [1 2; 2 3; 3 4; 4 5; 5 6; 5 7; 5 8; 5 9];
weights = [results.params.p.A; 
           results.subsystem.P_pass.A * results.params.p.B;
           results.subsystem.P_pass.A * results.subsystem.P_pass.B * results.params.p.C;
           results.subsystem.P_pass.A * results.subsystem.P_pass.B * results.subsystem.P_pass.C;
           results.lambda.values'];

% 创建图对象
G = digraph(edges(:,1), edges(:,2), weights);

% 自定义布局
x = [0, 2, 4, 6, 8, 10, 10, 10, 10];
y = [4, 4, 4, 4, 4, 6, 4.5, 3, 1.5];

% 绘制网络图
h = plot(G, 'XData', x, 'YData', y, ...
         'NodeLabel', nodes, ...
         'NodeColor', [0.2, 0.4, 0.8], ...
         'EdgeColor', [0.5, 0.5, 0.5], ...
         'LineWidth', 2, ...
         'MarkerSize', 12, ...
         'ArrowSize', 10, ...
         'NodeFontSize', 11, ...
         'NodeFontWeight', 'bold', ...
         'EdgeAlpha', 0.8);

% 根据权重调整边的粗细
edge_weights = G.Edges.Weight;
edge_widths = 1 + 4 * (edge_weights - min(edge_weights)) / (max(edge_weights) - min(edge_weights));
h.LineWidth = edge_widths;

% 添加边标签
edge_labels = arrayfun(@(x) sprintf('%.3f', x), weights, 'UniformOutput', false);
h.EdgeLabel = edge_labels;

title('测试流程概率传播网络', 'FontSize', 14, 'FontWeight', 'bold');
axis off;

%% ========== 图3：3D参数空间分析 ==========
figure('Name', '3D参数空间', 'Position', [150, 150, 1200, 800]);

% 生成参数网格
[P_A, P_B] = meshgrid(0.01:0.002:0.05, 0.01:0.002:0.05);
Lambda_1 = zeros(size(P_A));
Lambda_2 = zeros(size(P_B));

% 计算λ值
for i = 1:numel(P_A)
    p_temp = [P_A(i), P_B(i), results.params.p.C, results.params.p.D];
    e_temp = [results.params.e.A, results.params.e.B, results.params.e.C, results.params.e.E];
    
    alpha_temp = 0.5 * e_temp(1:3) ./ p_temp(1:3);
    beta_temp = 0.5 * e_temp(1:3) ./ (1 - p_temp(1:3));
    P_pass_temp = p_temp(1:3) .* alpha_temp + (1 - p_temp(1:3)) .* (1 - beta_temp);
    P_problem_temp = (p_temp(1:3) .* alpha_temp) ./ P_pass_temp;
    
    weights_temp = [P_problem_temp, p_temp(4)];
    lambda_temp = weights_temp / sum(weights_temp);
    
    Lambda_1(i) = lambda_temp(1);
    Lambda_2(i) = lambda_temp(2);
end

% 子图3.1：λ₁的3D曲面
subplot(1, 2, 1);
surf(P_A*100, P_B*100, Lambda_1*100, 'EdgeColor', 'none');
xlabel('p_A (%)');
ylabel('p_B (%)');
zlabel('λ₁ (%)');
title('λ₁在(p_A, p_B)参数空间的分布');
colormap(jet);
colorbar;
view(-45, 30);
grid on;
hold on;
% 标记当前工作点
plot3(results.params.p.A*100, results.params.p.B*100, ...
      results.lambda.lambda_1*100, 'ro', 'MarkerSize', 10, ...
      'MarkerFaceColor', 'r');

% 子图3.2：λ₂的3D曲面
subplot(1, 2, 2);
surf(P_A*100, P_B*100, Lambda_2*100, 'EdgeColor', 'none');
xlabel('p_A (%)');
ylabel('p_B (%)');
zlabel('λ₂ (%)');
title('λ₂在(p_A, p_B)参数空间的分布');
colormap(jet);
colorbar;
view(-45, 30);
grid on;
hold on;
% 标记当前工作点
plot3(results.params.p.A*100, results.params.p.B*100, ...
      results.lambda.lambda_2*100, 'ro', 'MarkerSize', 10, ...
      'MarkerFaceColor', 'r');

sgtitle('λ参数在三维参数空间的分布特性', 'FontSize', 14, 'FontWeight', 'bold');

%% ========== 图4：贝叶斯推断示意图 ==========
figure('Name', '贝叶斯推断', 'Position', [200, 200, 1000, 600]);

% 准备数据
systems = {'A', 'B', 'C'};
prior = [results.params.p.A, results.params.p.B, results.params.p.C];
posterior = [results.posterior.A, results.posterior.B, results.posterior.C];

% 创建分组条形图
x = 1:3;
y = [prior*100; posterior*100]';
b = bar(x, y, 'grouped');
b(1).FaceColor = [0.3, 0.5, 0.8];
b(2).FaceColor = [0.8, 0.3, 0.3];

xlabel('子系统');
ylabel('问题概率 (%)');
title('贝叶斯推断：先验与后验概率对比', 'FontSize', 14, 'FontWeight', 'bold');
legend('先验概率', '后验概率', 'Location', 'best');
set(gca, 'XTickLabel', systems);
grid on;

% 添加数值标签
for i = 1:3
    text(i-0.15, prior(i)*100+0.1, sprintf('%.2f%%', prior(i)*100), ...
         'HorizontalAlignment', 'center', 'FontWeight', 'bold');
    text(i+0.15, posterior(i)*100+0.1, sprintf('%.2f%%', posterior(i)*100), ...
         'HorizontalAlignment', 'center', 'FontWeight', 'bold');
end

% 添加贝叶斯公式注释
text(2, max(y(:))*0.9, ...
     'P(问题|通过) = P(通过|问题) × P(问题) / P(通过)', ...
     'HorizontalAlignment', 'center', 'FontSize', 12, ...
     'BackgroundColor', 'white', 'EdgeColor', 'black');

%% ========== 图5：综合性能雷达图 ==========
figure('Name', '性能雷达图', 'Position', [250, 250, 800, 800]);

% 准备数据
metrics_names = {'灵敏度', '特异度', '准确率', '精确率', 'F1分数', '信息增益'};
metrics_values = [results.metrics.sensitivity, ...
                  results.metrics.specificity, ...
                  results.metrics.accuracy, ...
                  results.metrics.precision, ...
                  results.metrics.F1_score, ...
                  results.information.I_XY/results.information.H_lambda];

% 创建雷达图
theta = linspace(0, 2*pi, length(metrics_names)+1);
rho = [metrics_values, metrics_values(1)];

polarplot(theta, rho, 'b-o', 'LineWidth', 2, 'MarkerSize', 8, ...
          'MarkerFaceColor', 'b');
hold on;

% 添加参考线
for r = 0.2:0.2:1
    polarplot(linspace(0, 2*pi, 100), ones(1, 100)*r, 'k:', 'LineWidth', 0.5);
end

% 设置标签
ax = gca;
ax.ThetaTick = rad2deg(theta(1:end-1));
ax.ThetaTickLabel = metrics_names;
ax.RLim = [0, 1];
title('E测试综合性能雷达图', 'FontSize', 14, 'FontWeight', 'bold');

%% ========== 图6：论文用综合图 ==========
figure('Name', '论文用综合图', 'Position', [300, 100, 1400, 800]);

% 子图6.1：λ参数分布
subplot(2, 3, 1);
pie(results.lambda.values, ...
    {sprintf('A: %.1f%%', results.lambda.lambda_1*100), ...
     sprintf('B: %.1f%%', results.lambda.lambda_2*100), ...
     sprintf('C: %.1f%%', results.lambda.lambda_3*100), ...
     sprintf('D: %.1f%%', results.lambda.lambda_4*100)});
title('(a) λ参数分布');
colormap(gca, lines(4));

% 子图6.2：漏判率对比
subplot(2, 3, 2);
alpha_values = [results.subsystem.alpha.A, results.subsystem.alpha.B, ...
                results.subsystem.alpha.C, results.E_test.alpha_E] * 100;
bar(alpha_values, 'FaceColor', [0.8, 0.3, 0.3]);
xlabel('测试组');
ylabel('漏判率 (%)');
title('(b) 各测试组漏判率');
set(gca, 'XTickLabel', {'A', 'B', 'C', 'E'});
grid on;
% 添加数值
for i = 1:4
    text(i, alpha_values(i)+1, sprintf('%.1f%%', alpha_values(i)), ...
         'HorizontalAlignment', 'center', 'FontWeight', 'bold');
end

% 子图6.3：误判率对比
subplot(2, 3, 3);
beta_values = [results.subsystem.beta.A, results.subsystem.beta.B, ...
               results.subsystem.beta.C, results.E_test.beta_E] * 100;
bar(beta_values, 'FaceColor', [0.3, 0.8, 0.3]);
xlabel('测试组');
ylabel('误判率 (%)');
title('(c) 各测试组误判率');
set(gca, 'XTickLabel', {'A', 'B', 'C', 'E'});
grid on;
% 添加数值
for i = 1:4
    text(i, beta_values(i)+0.05, sprintf('%.2f%%', beta_values(i)), ...
         'HorizontalAlignment', 'center', 'FontWeight', 'bold');
end

% 子图6.4：Monte Carlo验证散点图
subplot(2, 3, 4);
scatter(results.lambda.values*100, advanced_results.monte_carlo.lambda_sim*100, ...
        100, 1:4, 'filled');
hold on;
plot([0, 50], [0, 50], 'r--', 'LineWidth', 1);
xlabel('理论值 (%)');
ylabel('模拟值 (%)');
title('(d) Monte Carlo验证');
colormap(gca, lines(4));
colorbar('Ticks', 1:4, 'TickLabels', {'λ₁', 'λ₂', 'λ₃', 'λ₄'});
grid on;
axis equal;
xlim([0, 50]); ylim([0, 50]);

% 子图6.5：灵敏度排序
subplot(2, 3, 5);
mean_elasticity = mean(abs(advanced_results.sensitivity.elasticity), 2);
[sorted_elas, idx] = sort(mean_elasticity, 'descend');
barh(sorted_elas, 'FaceColor', [0.4, 0.4, 0.8]);
xlabel('平均弹性系数');
ylabel('参数');
title('(e) 参数灵敏度排序');
set(gca, 'YTickLabel', advanced_results.sensitivity.param_names(idx));
grid on;

% 子图6.6：性能指标对比
subplot(2, 3, 6);
metrics_comp = [results.metrics.sensitivity, results.metrics.specificity, ...
                results.metrics.accuracy, results.metrics.precision] * 100;
bar(metrics_comp, 'FaceColor', [0.6, 0.6, 0.6]);
xlabel('性能指标');
ylabel('百分比 (%)');
title('(f) E测试性能指标');
set(gca, 'XTickLabel', {'灵敏度', '特异度', '准确率', '精确率'});
ylim([0, 100]);
grid on;
% 添加数值
for i = 1:4
    text(i, metrics_comp(i)+2, sprintf('%.1f%%', metrics_comp(i)), ...
         'HorizontalAlignment', 'center', 'FontWeight', 'bold');
end

sgtitle('综合测试概率模型分析结果', 'FontSize', 16, 'FontWeight', 'bold');

%% ========== 保存所有图表 ==========
% 创建输出文件夹
if ~exist('figures', 'dir')
    mkdir('figures');
end

% 保存所有图表
fig_handles = findall(0, 'Type', 'figure');
for i = 1:length(fig_handles)
    fig_name = get(fig_handles(i), 'Name');
    if isempty(fig_name)
        fig_name = sprintf('Figure_%d', i);
    end
    
    % 保存为高质量PNG
    print(fig_handles(i), fullfile('figures', [fig_name, '.png']), ...
          '-dpng', '-r300');
    
    % 保存为矢量格式EPS（用于论文）
    print(fig_handles(i), fullfile('figures', [fig_name, '.eps']), ...
          '-depsc', '-r300');
    
    % 保存为PDF
    print(fig_handles(i), fullfile('figures', [fig_name, '.pdf']), ...
          '-dpdf', '-r300');
end

fprintf('\n所有图表已保存至 figures 文件夹\n');
fprintf('包含格式：PNG (300dpi), EPS (矢量), PDF\n');
fprintf('\n问题1完整分析完成！\n');