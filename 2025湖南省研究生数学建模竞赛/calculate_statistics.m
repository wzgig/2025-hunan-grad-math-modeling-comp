function stats = calculate_statistics(results)
    % 计算统计指标
    % 输入：
    %   results - 蒙特卡洛仿真结果
    % 输出：
    %   stats - 统计指标
    
    stats = struct();
    
    % ========== T：任务完成天数 ==========
    stats.T_mean = mean(results.T);
    stats.T_std = std(results.T);
    stats.T_min = min(results.T);
    stats.T_max = max(results.T);
    stats.T_median = median(results.T);
    stats.T_ci = calculate_confidence_interval(results.T, 0.95);
    
    % ========== S：通过测试的装置数 ==========
    stats.S_mean = mean(results.S);
    stats.S_std = std(results.S);
    stats.S_min = min(results.S);
    stats.S_max = max(results.S);
    stats.S_median = median(results.S);
    stats.S_ci = calculate_confidence_interval(results.S, 0.95);
    
    % ========== P_L：总漏判概率 ==========
    stats.PL_mean = mean(results.PL);
    stats.PL_std = std(results.PL);
    stats.PL_min = min(results.PL);
    stats.PL_max = max(results.PL);
    stats.PL_median = median(results.PL);
    stats.PL_ci = calculate_confidence_interval(results.PL, 0.95);
    
    % ========== P_W：总误判概率 ==========
    stats.PW_mean = mean(results.PW);
    stats.PW_std = std(results.PW);
    stats.PW_min = min(results.PW);
    stats.PW_max = max(results.PW);
    stats.PW_median = median(results.PW);
    stats.PW_ci = calculate_confidence_interval(results.PW, 0.95);
    
    % ========== YXB：有效工作时间比 ==========
    stats.YXB_mean = mean(results.YXB, 1);
    stats.YXB_std = std(results.YXB, 0, 1);
    stats.YXB_min = min(results.YXB, [], 1);
    stats.YXB_max = max(results.YXB, [], 1);
    stats.YXB_median = median(results.YXB, 1);
    
    % 各组的置信区间
    stats.YXB_ci = zeros(4, 2);
    for i = 1:4
        stats.YXB_ci(i, :) = calculate_confidence_interval(results.YXB(:, i), 0.95);
    end
    
    % ========== 分布分析 ==========
    stats.T_distribution = analyze_distribution(results.T);
    stats.S_distribution = analyze_distribution(results.S);
    
    % ========== 相关性分析 ==========
    stats.correlations = calculate_correlations(results);
    
    % ========== 稳定性分析 ==========
    stats.stability = analyze_stability(results);
    
    % ========== 效率分析 ==========
    stats.efficiency_analysis = analyze_efficiency(results);
end

function ci = calculate_confidence_interval(data, confidence_level)
    % 计算置信区间
    
    alpha = 1 - confidence_level;
    n = length(data);
    
    % 使用t分布（样本较小时）
    if n < 30
        t_critical = tinv(1 - alpha/2, n - 1);
        margin = t_critical * std(data) / sqrt(n);
    else
        % 使用正态分布（大样本）
        z_critical = norminv(1 - alpha/2);
        margin = z_critical * std(data) / sqrt(n);
    end
    
    ci = [mean(data) - margin, mean(data) + margin];
end

function dist_info = analyze_distribution(data)
    % 分析数据分布
    
    dist_info = struct();
    
    % 基本统计量
    dist_info.mean = mean(data);
    dist_info.std = std(data);
    dist_info.skewness = skewness(data);
    dist_info.kurtosis = kurtosis(data);
    
    % 四分位数
    dist_info.quartiles = quantile(data, [0.25, 0.5, 0.75]);
    dist_info.iqr = dist_info.quartiles(3) - dist_info.quartiles(1);
    
    % 异常值检测（使用IQR方法）
    lower_bound = dist_info.quartiles(1) - 1.5 * dist_info.iqr;
    upper_bound = dist_info.quartiles(3) + 1.5 * dist_info.iqr;
    dist_info.outliers = data(data < lower_bound | data > upper_bound);
    dist_info.n_outliers = length(dist_info.outliers);
    
    % 正态性检验（Jarque-Bera检验）
    [h, p] = jbtest(data);
    dist_info.normality_test.h = h;  % 0表示正态，1表示非正态
    dist_info.normality_test.p = p;
    dist_info.is_normal = (h == 0);
    
    % 分布拟合
    if dist_info.is_normal
        dist_info.fitted_dist = 'Normal';
        dist_info.parameters = [dist_info.mean, dist_info.std];
    else
        % 尝试其他分布
        dist_info.fitted_dist = 'Empirical';
        dist_info.parameters = [];
    end
end

function correlations = calculate_correlations(results)
    % 计算各指标间的相关性
    
    correlations = struct();
    
    % 创建数据矩阵
    data_matrix = [results.T, results.S, results.PL, results.PW, results.YXB];
    
    % 计算相关系数矩阵
    [R, P] = corrcoef(data_matrix);
    
    correlations.matrix = R;
    correlations.p_values = P;
    
    % 变量名称
    correlations.variables = {'T', 'S', 'P_L', 'P_W', 'YXB_A', 'YXB_B', 'YXB_C', 'YXB_E'};
    
    % 找出强相关（|r| > 0.7）
    strong_correlations = [];
    for i = 1:size(R, 1)
        for j = i+1:size(R, 2)
            if abs(R(i, j)) > 0.7
                strong_correlations(end+1, :) = [i, j, R(i, j), P(i, j)];
            end
        end
    end
    correlations.strong = strong_correlations;
    
    % 主成分分析
    [coeff, score, latent, ~, explained] = pca(zscore(data_matrix));
    correlations.pca.coefficients = coeff;
    correlations.pca.scores = score;
    correlations.pca.eigenvalues = latent;
    correlations.pca.explained_variance = explained;
    
    % 找出解释大部分方差的主成分数
    cumulative_variance = cumsum(explained);
    correlations.pca.n_components_90 = find(cumulative_variance >= 90, 1);
end

function stability = analyze_stability(results)
    % 分析仿真的稳定性
    
    stability = struct();
    
    % 移动平均和标准差
    window_size = min(20, floor(length(results.T) / 5));
    
    stability.T_moving_mean = movmean(results.T, window_size);
    stability.T_moving_std = movstd(results.T, window_size);
    
    stability.S_moving_mean = movmean(results.S, window_size);
    stability.S_moving_std = movstd(results.S, window_size);
    
    % 收敛性分析
    n_points = length(results.T);
    batch_sizes = round(linspace(10, n_points, min(20, n_points/5)));
    
    stability.convergence.T_mean = zeros(size(batch_sizes));
    stability.convergence.S_mean = zeros(size(batch_sizes));
    
    for i = 1:length(batch_sizes)
        batch_size = batch_sizes(i);
        stability.convergence.T_mean(i) = mean(results.T(1:batch_size));
        stability.convergence.S_mean(i) = mean(results.S(1:batch_size));
    end
    
    stability.convergence.batch_sizes = batch_sizes;
    
    % 变异系数（CV）
    stability.cv.T = std(results.T) / mean(results.T);
    stability.cv.S = std(results.S) / mean(results.S);
    stability.cv.PL = std(results.PL) / mean(results.PL);
    stability.cv.PW = std(results.PW) / mean(results.PW);
    
    % 稳定性评价
    max_cv = max([stability.cv.T, stability.cv.S]);
    if max_cv < 0.1
        stability.assessment = '优秀';
    elseif max_cv < 0.2
        stability.assessment = '良好';
    elseif max_cv < 0.3
        stability.assessment = '一般';
    else
        stability.assessment = '较差';
    end
end

function efficiency = analyze_efficiency(results)
    % 分析效率相关指标
    
    efficiency = struct();
    
    % 计算总体效率
    efficiency.overall = mean(mean(results.YXB));
    efficiency.overall_std = std(mean(results.YXB, 2));
    
    % 各工位效率
    station_names = {'A', 'B', 'C', 'E'};
    for i = 1:4
        efficiency.stations.(station_names{i}).mean = mean(results.YXB(:, i));
        efficiency.stations.(station_names{i}).std = std(results.YXB(:, i));
        efficiency.stations.(station_names{i}).cv = std(results.YXB(:, i)) / mean(results.YXB(:, i));
    end
    
    % 瓶颈分析
    [min_eff, bottleneck_idx] = min(mean(results.YXB, 1));
    efficiency.bottleneck.station = station_names{bottleneck_idx};
    efficiency.bottleneck.efficiency = min_eff;
    
    % 平衡度分析（效率的标准差）
    efficiency.balance = std(mean(results.YXB, 1));
    
    % 效率与完成时间的关系
    [r, p] = corrcoef(mean(results.YXB, 2), results.T);
    efficiency.correlation_with_T = r(1, 2);
    efficiency.correlation_p_value = p(1, 2);
    
    % 效率分布
    efficiency.distribution = struct();
    efficiency.distribution.bins = 0:0.05:1;
    for i = 1:4
        efficiency.distribution.(station_names{i}) = ...
            histcounts(results.YXB(:, i), efficiency.distribution.bins);
    end
    
    % 改进潜力评估
    theoretical_max = 1.0;  % 理论最大效率
    efficiency.improvement_potential = theoretical_max - efficiency.overall;
    
    % 资源利用率
    efficiency.resource_utilization = struct();
    efficiency.resource_utilization.test_benches = calculate_bench_utilization(results);
    
    % 等待时间分析（基于效率推算）
    efficiency.waiting_time_ratio = 1 - efficiency.overall;
end

function bench_util = calculate_bench_utilization(results)
    % 估算测试台利用率
    
    % 基于完成时间和装置数量估算
    avg_device_time = mean(results.T) * 12 / 100;  % 平均每个装置占用的小时数
    theoretical_min_time = 100 * 8 / 2 / 12;  % 理论最短天数（2个测试台并行）
    
    bench_util = theoretical_min_time / mean(results.T);
    bench_util = min(bench_util, 1);  % 不超过100%
end