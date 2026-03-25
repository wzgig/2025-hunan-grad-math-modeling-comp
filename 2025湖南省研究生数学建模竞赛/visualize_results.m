function visualize_results(results, stats, params)
    % 生成问题2的可视化图表
    % 输入：
    %   results - 仿真结果
    %   stats - 统计分析结果
    %   params - 参数
    
    % 设置图形默认属性
    set(0, 'DefaultAxesFontSize', 10);
    set(0, 'DefaultAxesFontName', 'Times New Roman');
    set(0, 'DefaultLineLineWidth', 1.5);
    
    % ========== 图1：主要指标分布 ==========
    create_main_distributions_figure(results, stats);
    
    % ========== 图2：效率分析仪表板 ==========
    create_efficiency_dashboard(results, stats);
    
    % ========== 图3：收敛性与稳定性分析 ==========
    create_convergence_analysis(stats);
    
    % ========== 图4：相关性分析 ==========
    create_correlation_analysis(stats);
    
    % ========== 图5：综合仪表板 ==========
    create_comprehensive_dashboard(results, stats, params);
    
    % 保存所有图表
    save_all_figures();
end

function create_main_distributions_figure(results, stats)
    % 创建主要指标分布图
    
    figure('Name', '主要指标分布', 'Position', [100, 100, 1400, 800]);
    
    % 子图1：完成天数分布
    subplot(2, 3, 1);
    histogram(results.T, 20, 'FaceColor', [0.2, 0.4, 0.8], 'EdgeColor', 'black');
    hold on;
    xline(stats.T_mean, 'r--', 'LineWidth', 2);
    xline(stats.T_ci(1), 'g:', 'LineWidth', 1.5);
    xline(stats.T_ci(2), 'g:', 'LineWidth', 1.5);
    xlabel('完成天数');
    ylabel('频数');
    title(sprintf('任务完成天数分布\n均值=%.2f, 标准差=%.2f', stats.T_mean, stats.T_std));
    legend('分布', '均值', '95% CI', 'Location', 'best');
    grid on;
    
    % 子图2：通过装置数分布
    subplot(2, 3, 2);
    histogram(results.S, 15, 'FaceColor', [0.2, 0.8, 0.3], 'EdgeColor', 'black');
    hold on;
    xline(stats.S_mean, 'r--', 'LineWidth', 2);
    xlabel('通过装置数');
    ylabel('频数');
    title(sprintf('通过装置数分布\n均值=%.2f, 通过率=%.1f%%', ...
        stats.S_mean, stats.S_mean/100*100));
    legend('分布', '均值', 'Location', 'best');
    grid on;
    
    % 子图3：漏判概率分布
    subplot(2, 3, 3);
    histogram(results.PL*100, 20, 'FaceColor', [0.8, 0.3, 0.3], 'EdgeColor', 'black');
    hold on;
    xline(stats.PL_mean*100, 'r--', 'LineWidth', 2);
    xlabel('漏判概率 (%)');
    ylabel('频数');
    title(sprintf('总漏判概率分布\n均值=%.3f%%', stats.PL_mean*100));
    grid on;
    
    % 子图4：误判概率分布
    subplot(2, 3, 4);
    histogram(results.PW*100, 20, 'FaceColor', [0.8, 0.8, 0.2], 'EdgeColor', 'black');
    hold on;
    xline(stats.PW_mean*100, 'r--', 'LineWidth', 2);
    xlabel('误判概率 (%)');
    ylabel('频数');
    title(sprintf('总误判概率分布\n均值=%.3f%%', stats.PW_mean*100));
    grid on;
    
    % 子图5：T的Q-Q图（正态性检验）
    subplot(2, 3, 5);
    qqplot(results.T);
    title('完成天数Q-Q图');
    xlabel('理论分位数');
    ylabel('样本分位数');
    grid on;
    
    % 子图6：箱线图汇总
    subplot(2, 3, 6);
    data_for_boxplot = [results.T/max(results.T), ...
                        results.S/100, ...
                        results.PL*10, ...
                        results.PW*10];
    boxplot(data_for_boxplot, {'T(归一化)', 'S(%)', 'P_L(×10)', 'P_W(×10)'});
    title('主要指标箱线图');
    ylabel('归一化值');
    grid on;
    
    sgtitle('问题2：主要指标分布分析', 'FontSize', 14, 'FontWeight', 'bold');
end

function create_efficiency_dashboard(results, stats)
    % 创建效率分析仪表板
    
    figure('Name', '效率分析', 'Position', [150, 150, 1400, 800]);
    
    % 子图1：各组效率对比
    subplot(2, 3, 1);
    bar_data = stats.YXB_mean * 100;
    bar_err = stats.YXB_std * 100;
    bar(bar_data, 'FaceColor', [0.3, 0.6, 0.9]);
    hold on;
    errorbar(1:4, bar_data, bar_err, 'k.', 'LineWidth', 1.5);
    xlabel('测试组');
    ylabel('有效工时比 (%)');
    title('各测试组效率对比');
    set(gca, 'XTickLabel', {'A组', 'B组', 'C组', 'E组'});
    ylim([0, 100]);
    grid on;
    % 添加数值标签
    for i = 1:4
        text(i, bar_data(i)+2, sprintf('%.1f%%', bar_data(i)), ...
            'HorizontalAlignment', 'center', 'FontWeight', 'bold');
    end
    
    % 子图2：效率分布（小提琴图风格）
    subplot(2, 3, 2);
    positions = 1:4;
    for i = 1:4
        data = results.YXB(:, i) * 100;
        violin_plot(data, positions(i), 0.3, [0.5, 0.5, 0.9]);
    end
    xlabel('测试组');
    ylabel('有效工时比 (%)');
    title('效率分布（小提琴图）');
    set(gca, 'XTick', 1:4, 'XTickLabel', {'A组', 'B组', 'C组', 'E组'});
    ylim([0, 100]);
    grid on;
    
    % 子图3：效率时间序列
    subplot(2, 3, 3);
    plot(results.YXB, 'LineWidth', 1);
    xlabel('仿真次数');
    ylabel('有效工时比');
    title('效率变化趋势');
    legend({'A组', 'B组', 'C组', 'E组'}, 'Location', 'best');
    grid on;
    
    % 子图4：效率热图
    subplot(2, 3, 4);
    % 将结果分成若干批次
    n_batches = min(20, size(results.YXB, 1));
    batch_size = floor(size(results.YXB, 1) / n_batches);
    efficiency_matrix = zeros(n_batches, 4);
    for i = 1:n_batches
        start_idx = (i-1)*batch_size + 1;
        end_idx = min(i*batch_size, size(results.YXB, 1));
        efficiency_matrix(i, :) = mean(results.YXB(start_idx:end_idx, :), 1);
    end
    imagesc(efficiency_matrix * 100);
    colormap(hot);
    colorbar;
    xlabel('测试组');
    ylabel('批次');
    title('效率热图');
    set(gca, 'XTick', 1:4, 'XTickLabel', {'A', 'B', 'C', 'E'});
    
    % 子图5：效率与完成时间关系
    subplot(2, 3, 5);
    overall_efficiency = mean(results.YXB, 2);
    scatter(overall_efficiency*100, results.T, 30, 'filled');
    hold on;
    % 添加拟合线
    p = polyfit(overall_efficiency, results.T, 1);
    x_fit = linspace(min(overall_efficiency), max(overall_efficiency), 100);
    y_fit = polyval(p, x_fit);
    plot(x_fit*100, y_fit, 'r-', 'LineWidth', 2);
    xlabel('总体效率 (%)');
    ylabel('完成天数');
    title(sprintf('效率-时间关系 (r=%.3f)', stats.efficiency_analysis.correlation_with_T));
    legend('数据点', '拟合线', 'Location', 'best');
    grid on;
    
    % 子图6：资源利用率仪表
    subplot(2, 3, 6);
    % 创建仪表图
    theta = linspace(0, pi, 100);
    rho = ones(size(theta));
    polarplot(theta, rho, 'k-', 'LineWidth', 2);
    hold on;
    
    % 绘制效率指针
    eff_angle = pi * (1 - stats.efficiency_analysis.overall);
    polarplot([eff_angle, eff_angle], [0, 1], 'r-', 'LineWidth', 3);
    
    % 添加刻度
    for angle = 0:pi/4:pi
        polarplot([angle, angle], [0.95, 1.05], 'k-', 'LineWidth', 1);
    end
    
    title(sprintf('总体效率：%.1f%%', stats.efficiency_analysis.overall*100));
    ax = gca;
    ax.ThetaLim = [0, 180];
    ax.RLim = [0, 1.2];
    ax.ThetaTick = 0:45:180;
    ax.ThetaTickLabel = {'100%', '75%', '50%', '25%', '0%'};
    ax.RTickLabel = {};
    
    sgtitle('效率分析仪表板', 'FontSize', 14, 'FontWeight', 'bold');
end

function create_convergence_analysis(stats)
    % 创建收敛性分析图
    
    figure('Name', '收敛性分析', 'Position', [200, 200, 1200, 600]);
    
    % 子图1：T的收敛性
    subplot(1, 2, 1);
    plot(stats.stability.convergence.batch_sizes, ...
         stats.stability.convergence.T_mean, 'b-o', 'LineWidth', 2);
    hold on;
    yline(stats.T_mean, 'r--', 'LineWidth', 1.5, 'Label', '最终均值');
    xlabel('样本数');
    ylabel('累积平均完成天数');
    title('完成天数收敛性分析');
    grid on;
    
    % 添加置信带
    n = stats.stability.convergence.batch_sizes;
    ci_width = 1.96 * stats.T_std ./ sqrt(n);
    fill([n, fliplr(n)], ...
         [stats.stability.convergence.T_mean + ci_width, ...
          fliplr(stats.stability.convergence.T_mean - ci_width)], ...
         'b', 'FaceAlpha', 0.2, 'EdgeColor', 'none');
    
    % 子图2：S的收敛性
    subplot(1, 2, 2);
    plot(stats.stability.convergence.batch_sizes, ...
         stats.stability.convergence.S_mean, 'g-o', 'LineWidth', 2);
    hold on;
    yline(stats.S_mean, 'r--', 'LineWidth', 1.5, 'Label', '最终均值');
    xlabel('样本数');
    ylabel('累积平均通过数');
    title('通过装置数收敛性分析');
    grid on;
    
    % 添加置信带
    ci_width = 1.96 * stats.S_std ./ sqrt(n);
    fill([n, fliplr(n)], ...
         [stats.stability.convergence.S_mean + ci_width, ...
          fliplr(stats.stability.convergence.S_mean - ci_width)], ...
         'g', 'FaceAlpha', 0.2, 'EdgeColor', 'none');
    
    sgtitle(sprintf('仿真收敛性分析（稳定性评价：%s）', stats.stability.assessment), ...
            'FontSize', 14, 'FontWeight', 'bold');
end

function create_correlation_analysis(stats)
    % 创建相关性分析图
    
    figure('Name', '相关性分析', 'Position', [250, 250, 1200, 800]);
    
    % 子图1：相关系数矩阵热图
    subplot(2, 2, 1);
    imagesc(stats.correlations.matrix);
    colormap(redblue);
    colorbar;
    caxis([-1, 1]);
    title('变量相关系数矩阵');
    set(gca, 'XTick', 1:length(stats.correlations.variables));
    set(gca, 'YTick', 1:length(stats.correlations.variables));
    set(gca, 'XTickLabel', stats.correlations.variables);
    set(gca, 'YTickLabel', stats.correlations.variables);
    xtickangle(45);
    
    % 添加数值
    n_vars = length(stats.correlations.variables);
    for i = 1:n_vars
        for j = 1:n_vars
            if i ~= j
                text(j, i, sprintf('%.2f', stats.correlations.matrix(i, j)), ...
                     'HorizontalAlignment', 'center', 'Color', 'white', ...
                     'FontSize', 8);
            end
        end
    end
    
    % 子图2：主成分分析
    subplot(2, 2, 2);
    bar(stats.correlations.pca.explained_variance(1:min(5, end)), ...
        'FaceColor', [0.4, 0.6, 0.8]);
    xlabel('主成分');
    ylabel('解释方差比例 (%)');
    title(sprintf('主成分分析（前%d个成分解释90%%方差）', ...
                  stats.correlations.pca.n_components_90));
    grid on;
    
    % 子图3：主成分载荷图
    subplot(2, 2, 3);
    % 绘制前两个主成分的载荷
    if size(stats.correlations.pca.coefficients, 2) >= 2
        biplot(stats.correlations.pca.coefficients(:, 1:2), ...
               'VarLabels', stats.correlations.variables);
        title('主成分载荷图（PC1 vs PC2）');
    end
    
    % 子图4：强相关对散点图
    subplot(2, 2, 4);
    if ~isempty(stats.correlations.strong)
        % 选择最强的相关
        [~, idx] = max(abs(stats.correlations.strong(:, 3)));
        var1_idx = stats.correlations.strong(idx, 1);
        var2_idx = stats.correlations.strong(idx, 2);
        
        % 这里需要原始数据，暂时使用模拟
        title(sprintf('最强相关：%s vs %s (r=%.3f)', ...
                      stats.correlations.variables{var1_idx}, ...
                      stats.correlations.variables{var2_idx}, ...
                      stats.correlations.strong(idx, 3)));
    else
        title('无强相关（|r| > 0.7）');
    end
    
    sgtitle('相关性与主成分分析', 'FontSize', 14, 'FontWeight', 'bold');
end

function create_comprehensive_dashboard(results, stats, params)
    % 创建综合仪表板
    
    figure('Name', '综合仪表板', 'Position', [50, 50, 1600, 900]);
    
    % 子图1：关键指标卡片
    subplot(3, 4, [1, 2]);
    axis off;
    text(0.5, 0.9, '关键指标', 'FontSize', 16, 'FontWeight', 'bold', ...
         'HorizontalAlignment', 'center');
    text(0.1, 0.7, sprintf('完成天数：%.1f天', stats.T_mean), 'FontSize', 12);
    text(0.1, 0.5, sprintf('通过率：%.1f%%', stats.S_mean), 'FontSize', 12);
    text(0.1, 0.3, sprintf('漏判率：%.3f%%', stats.PL_mean*100), 'FontSize', 12);
    text(0.1, 0.1, sprintf('误判率：%.3f%%', stats.PW_mean*100), 'FontSize', 12);
    
    text(0.6, 0.7, sprintf('总效率：%.1f%%', stats.efficiency_analysis.overall*100), 'FontSize', 12);
    text(0.6, 0.5, sprintf('瓶颈工位：%s', stats.efficiency_analysis.bottleneck.station), 'FontSize', 12);
    text(0.6, 0.3, sprintf('稳定性：%s', stats.stability.assessment), 'FontSize', 12);
    text(0.6, 0.1, sprintf('仿真次数：%d', length(results.T)), 'FontSize', 12);
    
    % 子图2：完成时间趋势
    subplot(3, 4, 3);
    plot(results.T, 'b-', 'LineWidth', 1);
    hold on;
    plot(stats.stability.T_moving_mean, 'r-', 'LineWidth', 2);
    xlabel('仿真次数');
    ylabel('天数');
    title('完成时间趋势');
    legend('原始', '移动平均', 'Location', 'best');
    grid on;
    
    % 子图3：通过率趋势
    subplot(3, 4, 4);
    plot(results.S, 'g-', 'LineWidth', 1);
    hold on;
    plot(stats.stability.S_moving_mean, 'r-', 'LineWidth', 2);
    xlabel('仿真次数');
    ylabel('通过数');
    title('通过装置数趋势');
    legend('原始', '移动平均', 'Location', 'best');
    grid on;
    
    % 子图4：效率雷达图
    subplot(3, 4, [5, 6]);
    theta = [0, pi/2, pi, 3*pi/2, 2*pi];
    rho = [stats.YXB_mean, stats.YXB_mean(1)];
    polarplot(theta, rho, 'b-o', 'LineWidth', 2, 'MarkerSize', 8);
    hold on;
    % 添加参考圆
    for r = 0.2:0.2:1
        polarplot(linspace(0, 2*pi, 100), ones(1, 100)*r, 'k:', 'LineWidth', 0.5);
    end
    title('各组效率雷达图');
    ax = gca;
    ax.ThetaTick = [0, 90, 180, 270];
    ax.ThetaTickLabel = {'A', 'B', 'C', 'E'};
    ax.RLim = [0, 1];
    
    % 子图5：分布对比
    subplot(3, 4, [7, 8]);
    edges = linspace(min(results.T), max(results.T), 20);
    histogram(results.T, edges, 'Normalization', 'pdf', ...
              'FaceColor', [0.3, 0.5, 0.8], 'EdgeColor', 'none', 'FaceAlpha', 0.5);
    hold on;
    % 添加正态分布拟合
    x = linspace(min(results.T), max(results.T), 100);
    y = normpdf(x, stats.T_mean, stats.T_std);
    plot(x, y, 'r-', 'LineWidth', 2);
    xlabel('完成天数');
    ylabel('概率密度');
    title('完成时间分布拟合');
    legend('实际分布', '正态拟合', 'Location', 'best');
    grid on;
    
    % 子图6：质量指标
    subplot(3, 4, 9);
    x = categorical({'漏判率', '误判率'});
    y = [stats.PL_mean, stats.PW_mean] * 100;
    bar(x, y, 'FaceColor', [0.8, 0.3, 0.3]);
    ylabel('概率 (%)');
    title('质量指标');
    ylim([0, max(y)*1.2]);
    grid on;
    % 添加数值标签
    for i = 1:2
        text(i, y(i)+0.01, sprintf('%.3f%%', y(i)), ...
             'HorizontalAlignment', 'center', 'FontWeight', 'bold');
    end
    
    % 子图7：置信区间
    subplot(3, 4, 10);
    indicators = {'T', 'S', 'P_L', 'P_W'};
    means = [stats.T_mean/20, stats.S_mean/100, stats.PL_mean*10, stats.PW_mean*10];
    ci_lower = [stats.T_ci(1)/20, stats.S_ci(1)/100, stats.PL_ci(1)*10, stats.PW_ci(1)*10];
    ci_upper = [stats.T_ci(2)/20, stats.S_ci(2)/100, stats.PL_ci(2)*10, stats.PW_ci(2)*10];
    
    errorbar(1:4, means, means-ci_lower, ci_upper-means, 'o', ...
             'LineWidth', 2, 'MarkerSize', 8, 'MarkerFaceColor', 'b');
    xlabel('指标');
    ylabel('归一化值');
    title('95%置信区间');
    set(gca, 'XTick', 1:4, 'XTickLabel', indicators);
    grid on;
    
    % 子图8：参数影响
    subplot(3, 4, [11, 12]);
    param_labels = {'p_A', 'p_B', 'p_C', 'e_A', 'e_B', 'e_C', 'e_E'};
    param_values = [params.p.A, params.p.B, params.p.C, ...
                   params.e.A, params.e.B, params.e.C, params.e.E] * 100;
    barh(param_values, 'FaceColor', [0.4, 0.7, 0.4]);
    xlabel('参数值 (%)');
    ylabel('参数');
    title('输入参数');
    set(gca, 'YTick', 1:length(param_labels), 'YTickLabel', param_labels);
    grid on;
    
    sgtitle('问题2：综合分析仪表板', 'FontSize', 16, 'FontWeight', 'bold');
end

function violin_plot(data, position, width, color)
    % 简单的小提琴图实现
    
    % 计算核密度估计
    [f, xi] = ksdensity(data);
    f = f / max(f) * width / 2;  % 归一化到指定宽度
    
    % 绘制小提琴形状
    patch([position - f, position + fliplr(f)], ...
          [xi, fliplr(xi)], color, 'EdgeColor', 'none', 'FaceAlpha', 0.5);
    
    % 添加箱线图元素
    q = quantile(data, [0.25, 0.5, 0.75]);
    hold on;
    plot([position, position], [min(data), max(data)], 'k-', 'LineWidth', 1);
    plot(position, q(2), 'ko', 'MarkerSize', 8, 'MarkerFaceColor', 'white');
    rectangle('Position', [position-width/4, q(1), width/2, q(3)-q(1)], ...
              'EdgeColor', 'k', 'LineWidth', 1.5);
end

function cmap = redblue
    % 创建红蓝渐变色图
    n = 256;
    r = [linspace(0, 1, n/2), ones(1, n/2)]';
    g = [linspace(0, 1, n/2), linspace(1, 0, n/2)]';
    b = [ones(1, n/2), linspace(1, 0, n/2)]';
    cmap = [r, g, b];
end

function save_all_figures()
    % 保存所有图表
    
    % 创建输出文件夹
    if ~exist('figures_problem2', 'dir')
        mkdir('figures_problem2');
    end
    
    % 获取所有图形句柄
    fig_handles = findall(0, 'Type', 'figure');
    
    for i = 1:length(fig_handles)
        fig_name = get(fig_handles(i), 'Name');
        if isempty(fig_name)
            fig_name = sprintf('Figure_%d', i);
        end
        
        % 保存为PNG
        saveas(fig_handles(i), fullfile('figures_problem2', [fig_name, '.png']));
        
        % 保存为FIG（MATLAB格式）
        saveas(fig_handles(i), fullfile('figures_problem2', [fig_name, '.fig']));
    end
    
    fprintf('所有图表已保存至 figures_problem2 文件夹\n');
end