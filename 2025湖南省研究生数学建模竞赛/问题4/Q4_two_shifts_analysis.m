% Q4_two_shifts_analysis.m
% 问题4：基于问题3模型的因素灵敏度分析与改进建议支撑
% - 复用Q3仿真内核（分钟级、双分队接续倒班、A/B/C并行、设备跨班共享）
% - 目标：分析各因素对平均完成时间 T 的影响，生成论文素材（表/图/报告）
%
% 作者：<your name>
% 日期：2025-08-31

function Q4_two_shifts_analysis
clc; clear; close all;

%% =================== 基线参数（与Q3一致） ===================
params = struct();

% —— 时间单位 = 分钟 ——
params.tt     = struct('A',150,'B',120,'C',150,'E',180);   % 测试时长
params.setup  = struct('A',30,'B',20,'C',20,'E',40);       % 更换setup（不得跨班）
params.t_in   = 30;                                        % 运入（允许跨班）
params.t_out  = 30;                                        % 运出（允许跨班）
params.buffer = 0;                                         % 班末缓冲（允许"等于边界"）

% —— 测手差错（误判/漏判各占50%） ——
params.e     = struct('A',0.03,'B',0.04,'C',0.02,'E',0.02);
params.alpha = structfun(@(x)0.5*x, params.e, 'UniformOutput', false); % 漏判
params.beta  = structfun(@(x)0.5*x, params.e, 'UniformOutput', false); % 误判

% —— 先验真实问题概率（独立伯努利） ——
params.p0 = struct('A',0.025,'B',0.030,'C',0.020,'D',0.001);

% —— 首故障阈值抽样：0–120h 累计 r1，0–240h 累计 r2 ——
params.fail_r1 = struct('A',0.03,'B',0.04,'C',0.02,'E',0.03);
params.fail_r2 = struct('A',0.05,'B',0.07,'C',0.06,'E',0.05);

% —— 工位集合（顺序用于输出） ——
params.stations = {'A','B','C','E'};

% —— 常量 —— 
params.H240 = 240*60;                        % 240小时（分钟）
params.H120 = 120*60;                        % 120小时（分钟）

%% =================== 仿真配置（与Q3一致） ===================
cfg = struct();
cfg.parallel_ABC     = true;                 % 同装置 A/B/C 并行
cfg.n_devices        = 100;                  % 每批规模
cfg.n_replications   = 100;                  % 每个K的重复次数
cfg.K_list_hours     = [9 9.5 10 10.5 11 11.5 12];  % 候选班长
% cfg.K_list_hours     = [10.5];  % 候选班长
cfg.verbose_every    = 25;                   % 进度打印频率
cfg.random_seed_base = 20250831;             % CRN：按rep设种子，跨场景复用
cfg.draw_gantt_forK  = 12;                   % 画甘特图的K（小时）
cfg.R_OAT          = 40;   % OAT用更小的重复数；调到 20–50 都可
cfg.n_devices_OAT  = 40;   % OAT用更少设备数；60或40都行
cfg.watchdog_shifts= 5000; % 守望者：连续N班无完成就报警（很大，一般触不到）

fprintf('=== 问题4：基于问题3的灵敏度分析开始 ===\n');

%% =================== 第一步：复用Q3，跨K评估，确定 K* ===================
[Res, timeline_bestK, T_end_bestK, best_idx, T_table] = run_Q3_batch(params, cfg);

bestK = Res.K(best_idx);
Kmin  = round(bestK*60);
fprintf('\n=> 最优 K* = %.1f 小时（按 T 平均最小）\n', bestK);

% 可视化（跨K、最佳K、甘特）
visualize_across_K_Q4(Res, params);
visualize_bestK_details_Q4(Res, best_idx, params);
if ~isempty(timeline_bestK)
    visualize_gantt_Q4(timeline_bestK, T_end_bestK, params, Kmin);
end

% 保存主结果（与Q3一致）
save('Q4_main_results.mat', 'Res', 'params', 'cfg', 'timeline_bestK', 'T_end_bestK', 'best_idx', 'T_table');
writetable(table_from_Res_Q4(Res), 'Q4_main_results.csv');

%% =================== 第二步：问题4 — 单因素灵敏度（OAT, CRN配对） ===================
% 因素表：name、getter/setter句柄、基线值、扰动幅度、单位说明
factors = define_oat_factors_Q4(params, bestK);

% 运行 OAT：固定K=K*，其余同基线；每个因素 ±delta 评估 ΔT
% R = cfg.n_replications;
% === OAT：复用第3问bestK的逐次T作为基线 ===
bestK = Res.K(best_idx);
T_base_runs = T_table(best_idx, :);          % 逐次T（天）
factors = define_oat_factors_Q4(params, bestK);
[OAT_tbl, tornado] = run_OAT_Q4(params, cfg, bestK, factors, T_base_runs);

% 可视化：Tornado（按弹性|E|排序）
visualize_tornado_Q4(tornado);

% 站点时间账本（最佳K）：测试/更换/空闲 堆叠图（论文素材）
stack_data = stack_station_time_Q4(params, cfg, bestK);
visualize_station_stack_Q4(stack_data);

% 导出 OAT 结果
writetable(OAT_tbl, 'Q4_sensitivity_OAT.csv');

%% =================== 第三步：生成论文报告（Markdown） ===================
sanity = analytic_sanity_Q4(params);
pairtbl = compute_pairwise_tests_Q4(Res, T_table, best_idx);
generate_report_Q4(Res, best_idx, params, cfg, sanity, pairtbl, OAT_tbl);

% 保存当前所有图（PDF/PNG）
save_all_figs_Q4();

fprintf('\n=== 问题4：分析完成，已生成 CSV/MD 与图表 ===\n');
end % main


%% ======================================================================
%%               （A）复用Q3：跨K批量评估 + 结果聚合
%% ======================================================================
function [Res, timeline_bestK, T_end_bestK, best_idx, T_table] = run_Q3_batch(params, cfg)
Klist = cfg.K_list_hours;
nK    = numel(Klist);
R     = cfg.n_replications;

Res = struct();
Res.K                 = Klist(:);
Res.T_mean            = zeros(nK,1);
Res.T_std             = zeros(nK,1);
Res.S_mean            = zeros(nK,1);
Res.S_std             = zeros(nK,1);
Res.FPR               = zeros(nK,1); Res.FPR_lo = zeros(nK,1); Res.FPR_hi = zeros(nK,1);
Res.FNR               = zeros(nK,1); Res.FNR_lo = zeros(nK,1); Res.FNR_hi = zeros(nK,1);
Res.FDR               = zeros(nK,1); Res.FDR_lo = zeros(nK,1); Res.FDR_hi = zeros(nK,1);
Res.FOR               = zeros(nK,1); Res.FOR_lo = zeros(nK,1); Res.FOR_hi = zeros(nK,1);
Res.PL_uncond         = zeros(nK,1); Res.PL_uncond_lo=zeros(nK,1); Res.PL_uncond_hi=zeros(nK,1);
Res.PW_uncond         = zeros(nK,1); Res.PW_uncond_lo=zeros(nK,1); Res.PW_uncond_hi=zeros(nK,1);
Res.YXB_mean          = zeros(nK,4); Res.YXB_std = zeros(nK,4);
Res.T_all = cell(nK,1);

timeline_bestK = []; T_end_bestK = []; bestK_idx = [];

fprintf('=== 问题3基线：双分队接续倒班（分钟级）仿真 ===\n');
T_table = zeros(nK, R);

for ki = 1:nK
    K = Klist(ki);
    Kmin = round(K*60);
    fprintf('\n[K = %.1f 小时] Monte Carlo x %d ...\n', K, R);

    T_days   = zeros(R,1);
    S_pass   = zeros(R,1);
    YXB_mat  = zeros(R,4);
    PL_macro = zeros(R,1);
    PW_macro = zeros(R,1);
    agg = struct('TP',0,'FP',0,'TN',0,'FN',0,'P',0,'F',0,'N',0);

    for rep = 1:R
        if cfg.verbose_every>0 && mod(rep,cfg.verbose_every)==0
            fprintf('  -> rep %d/%d\n', rep, R);
        end
        rng(cfg.random_seed_base + rep, 'twister');
        sim = run_single_simulation_Q4(params, cfg, Kmin, (K==cfg.draw_gantt_forK) && isempty(timeline_bestK));

        T_days(rep)   = sim.T_minutes / 1440;
        S_pass(rep)   = sim.n_passed;
        PL_macro(rep) = sim.PL_cond;
        PW_macro(rep) = sim.PW_cond;
        YXB_mat(rep,:)= sim.YXB;

        agg.TP = agg.TP + sim.TP;  agg.FP = agg.FP + sim.FP;
        agg.TN = agg.TN + sim.TN;  agg.FN = agg.FN + sim.FN;
        agg.P  = agg.P  + sim.P;   agg.F  = agg.F  + sim.F; agg.N = agg.N + sim.N;

        if (K==cfg.draw_gantt_forK) && isempty(timeline_bestK)
            timeline_bestK = sim.timeline;
            T_end_bestK    = sim.T_minutes;
            bestK_idx      = ki;
        end

        T_table(ki, rep) = T_days(rep);
    end

    [Srow, Tdistro] = summarize_stats_Q4(T_days, S_pass, PL_macro, PW_macro, YXB_mat, agg);
    Res.T_mean(ki) = Srow.T_mean; Res.T_std(ki) = Srow.T_std;
    Res.S_mean(ki) = Srow.S_mean; Res.S_std(ki) = Srow.S_std;
    Res.FPR(ki) = Srow.FPR; Res.FPR_lo(ki)=Srow.FPR_lo; Res.FPR_hi(ki)=Srow.FPR_hi;
    Res.FNR(ki) = Srow.FNR; Res.FNR_lo(ki)=Srow.FNR_lo; Res.FNR_hi(ki)=Srow.FNR_hi;
    Res.FDR(ki) = Srow.FDR; Res.FDR_lo(ki)=Srow.FDR_lo; Res.FDR_hi(ki)=Srow.FDR_hi;
    Res.FOR(ki) = Srow.FOR; Res.FOR_lo(ki)=Srow.FOR_lo; Res.FOR_hi(ki)=Srow.FOR_hi;
    Res.PL_uncond(ki) = Srow.PL_uncond; Res.PL_uncond_lo(ki)=Srow.PL_uncond_lo; Res.PL_uncond_hi(ki)=Srow.PL_uncond_hi;
    Res.PW_uncond(ki) = Srow.PW_uncond; Res.PW_uncond_lo(ki)=Srow.PW_uncond_lo; Res.PW_uncond_hi(ki)=Srow.PW_uncond_hi;
    Res.YXB_mean(ki,:) = Srow.YXB_mean; Res.YXB_std(ki,:) = Srow.YXB_std;
    Res.T_all{ki} = Tdistro;
end

[~,best_idx] = min(Res.T_mean);
end


%% ======================================================================
%%               （B）问题4：单因素灵敏度（OAT, CRN配对）
%% ======================================================================
function factors = define_oat_factors_Q4(params, bestK)
% 每个因素含：name, type, base, delta, apply()
k = 1;
add('tau_A', 'min', params.tt.A, 0.10, @(P,sgn) setfield_tt(P,'A',P.tt.A*(1+sgn*0.10)));
add('tau_B', 'min', params.tt.B, 0.10, @(P,sgn) setfield_tt(P,'B',P.tt.B*(1+sgn*0.10)));
add('tau_C', 'min', params.tt.C, 0.10, @(P,sgn) setfield_tt(P,'C',P.tt.C*(1+sgn*0.10)));
add('tau_E', 'min', params.tt.E, 0.10, @(P,sgn) setfield_tt(P,'E',P.tt.E*(1+sgn*0.10)));

add('setup_A', 'min', params.setup.A, 0.20, @(P,sgn) setfield_setup(P,'A',max(1,round(P.setup.A*(1+sgn*0.20)))));
add('setup_B', 'min', params.setup.B, 0.20, @(P,sgn) setfield_setup(P,'B',max(1,round(P.setup.B*(1+sgn*0.20)))));
add('setup_C', 'min', params.setup.C, 0.20, @(P,sgn) setfield_setup(P,'C',max(1,round(P.setup.C*(1+sgn*0.20)))));
add('setup_E', 'min', params.setup.E, 0.20, @(P,sgn) setfield_setup(P,'E',max(1,round(P.setup.E*(1+sgn*0.20)))));

add('r2_E', 'prob', params.fail_r2.E, 0.20, @(P,sgn) setfield_r2(P,'E',clip01(P.fail_r2.E*(1+sgn*0.20))));
add('r1_E', 'prob', params.fail_r1.E, 0.20, @(P,sgn) setfield_r1(P,'E',clip01(P.fail_r1.E*(1+sgn*0.20))));

% 班长K（±0.5h，若越界则略过）
add('K_half', 'hour', bestK, 0.5,  @(P,sgn) P); % 在 run_OAT 内特判

    function add(name, typ, base, delta, applier)
        factors(k).name = name; %#ok<AGROW>
        factors(k).type = typ;
        factors(k).base = base;
        factors(k).delta= delta;
        factors(k).apply= applier;
        k = k+1;
    end
end

function P = setfield_tt(P, s, val)
P.tt.(s) = round(val);
end
function P = setfield_setup(P, s, val)
P.setup.(s) = round(val);
end
function P = setfield_r1(P, s, val)
P.fail_r1.(s) = val;
end
function P = setfield_r2(P, s, val)
P.fail_r2.(s) = val;
end
function x = clip01(x)
x = min(max(x,0),1);
end

function [OAT_tbl, tornado] = run_OAT_Q4(params, cfg, bestK, factors, T_base_runs_from_Q3)
% 改进点：
% - 使用 cfg.R_OAT 和 cfg.n_devices_OAT（不再用全局的大R/100台）
% - 复用第3问 bestK 的逐次 T（T_base_runs_from_Q3）作为基线，不再重跑基线
% - 打印进度
% - watchdog 传入仿真以避免极端场景拖太久

R     = cfg.R_OAT;
Kmin  = round(bestK*60);
runs0 = T_base_runs_from_Q3(:);           % 基线逐次T（天），CRN配对基准
if numel(runs0) ~= R
    % 若第3问的R!=R_OAT，则重采一个小基线（只在不匹配时）
    fprintf('OAT基线与第3问R不匹配，重跑小基线 R=%d...\n', R);
    [Tout0, runs0] = eval_T_bar_Q4(params, cfg, Kmin, R, cfg.n_devices_OAT);
    runs0 = runs0(:);
else
    fprintf('OAT复用第3问的基线逐次T（配对CRN）。\n');
end
T0_mean = mean(runs0);

rows = {};
cnt = 0;
total = numel(factors)*2;

for i=1:numel(factors)
    f = factors(i);
    for sgn = [-1,+1]
        cnt = cnt + 1;
        tag  = sprintf('%s_%s', f.name, tern(sgn>0,'plus','minus'));
        fprintf('  [OAT %2d/%2d] %s ... ', cnt, total, tag);

        P    = params;
        Kuse = bestK;

        if strcmp(f.name,'K_half')
            Kuse = bestK + sgn*0.5;
            if Kuse<=0
                fprintf("skip (K<=0)\n");
                rows(end+1,:) = {tag, f.name, f.base, sgn*f.delta, NaN, NaN, NaN, NaN, NaN, 0}; %#ok<AGROW>
                continue;
            end
        else
            P = f.apply(P, sgn);
        end
        Kmin_use = round(Kuse*60);

        % 评估该场景（小R、小设备），保持CRN（同seed）
        [Tout, Truns] = eval_T_bar_Q4(P, cfg, Kmin_use, R, cfg.n_devices_OAT);

        % 配对差（与runs0长度需一致；若K变化，仍使用同seed生成）
        n = min(numel(Truns), numel(runs0));
        Delta = Truns(1:n) - runs0(1:n);
        if n>=2
            [~,p,ci,~] = ttest(Delta);
            ci_lo = ci(1); ci_hi = ci(2);
        else
            p=NaN; ci_lo=NaN; ci_hi=NaN;
        end

        d_param = local_rel_change_Q4(f, sgn);
        elast   = ((Tout.mean - T0_mean)/T0_mean) / d_param;

        rows(end+1,:) = {tag, f.name, f.base, sgn*f.delta, Tout.mean, Tout.std, ...   % %#ok<AGROW>
                         Tout.mean - T0_mean, elast, p, n};
        fprintf('ΔT=%.4f 天, p=%g (n=%d)\n', Tout.mean - T0_mean, p, n);
    end
end

OAT_tbl = cell2table(rows, 'VariableNames', ...
    {'scenario','factor','base_val','delta','T_mean','T_std','Delta_T','Elasticity','p_value','n'});

% Tornado
fac = unique(OAT_tbl.factor,'stable');
Emax = zeros(numel(fac),1);
for k=1:numel(fac)
    ii = strcmp(OAT_tbl.factor, fac{k});
    Emax(k) = max(abs(OAT_tbl.Elasticity(ii)));
end
[~,ord] = sort(Emax, 'descend');
tornado = table(fac(ord), Emax(ord), 'VariableNames', {'factor','abs_elasticity'});
end


function d = local_rel_change_Q4(f, sgn)
% 返回相对变化幅度（用于弹性），K_half 以 0.5 / K 计
if strcmp(f.name,'K_half')
    d = abs(0.5 / f.base);
elseif strcmp(f.type,'min')
    d = 0.10; % or 0.20按定义
elseif strcmp(f.type,'prob')
    d = 0.20;
else
    d = abs(f.delta / f.base);
end
end

function [Tout, T_runs] = eval_T_bar_Q4(params, cfg, Kmin, R, n_devices_override)
% 固定Kmin，跑R次，返回 T 的均值/方差与逐次（分钟->天）。
% 允许指定OAT的小号设备数；默认用 cfg.n_devices_OAT
if nargin<5 || isempty(n_devices_override)
    n_devices = cfg.n_devices;
else
    n_devices = n_devices_override;
end

T_runs = zeros(R,1);
cfg_local = cfg;
cfg_local.n_devices = n_devices;     % OAT 小设备数
for rep=1:R
    rng(cfg.random_seed_base + rep, 'twister'); % CRN：同seed
    sim = run_single_simulation_Q4(params, cfg_local, Kmin, false);
    T_runs(rep) = sim.T_minutes/1440;
end
Tout.mean = mean(T_runs);
Tout.std  = std(T_runs);
end



%% ======================================================================
%%         （C）时间账本（最佳K）：测试/更换/空闲 堆叠图
%% ======================================================================
function stack = stack_station_time_Q4(params, cfg, bestK)
R = cfg.n_replications;
Kmin = round(bestK*60);

YXB  = zeros(R,4);
REPL = zeros(R,4);
for rep=1:R
    rng(cfg.random_seed_base + rep, 'twister');
    sim = run_single_simulation_Q4(params, cfg, Kmin, false);
    YXB(rep,:)  = sim.YXB;
    REPL(rep,:) = sim.REPL_share; % 更换占比
end
stack.stations = params.stations;
stack.YXB_mean = mean(YXB,1);   stack.YXB_std = std(YXB,0,1);
stack.RP_mean  = mean(REPL,1);  stack.RP_std  = std(REPL,0,1);
stack.ID_mean  = max(0, 1 - stack.YXB_mean - stack.RP_mean);
end


%% ======================================================================
%%                  （D）Q3 仿真内核（增强：更换时间统计）
%% ======================================================================
function sim = run_single_simulation_Q4(params, cfg, Kmin, keep_timeline)
% 初始化装置
D = init_devices_Q4(cfg.n_devices, params);

% 初始化系统
sys = init_system_Q4(params, Kmin);

% 起算点：两台装置已在位（不计首批运入/setup）
k = min(2, numel(D));
for b=1:k
    sys.benches(b).occupied  = true;
    sys.benches(b).device_id = b;
    D(b).status              = 'testing';
    D(b).location            = sprintf('bench_%d', b);
end

% 时间线记录（用于甘特图）
if keep_timeline
    sys.timeline = struct('station',{},'start',{},'finish',{},'device',{},'label',{});
else
    sys.timeline = [];
end

% 在函数开头：
idle_shifts = 0; last_done = 0;

% 在 while sys.n_done < numel(D) 的循环里，end_of_shift_Q4() 之后加：
if sys.n_done == last_done
    idle_shifts = idle_shifts + 1;
else
    idle_shifts = 0; last_done = sys.n_done;
end
if idle_shifts > cfg.watchdog_shifts
    error('Watchdog: 连续%d个班无完成事件，可能参数导致极慢/阻塞。', cfg.watchdog_shifts);
end


% 主循环：以当前班窗口推进
while sys.n_done < numel(D)
    while true
        [sys, ev] = pop_event_if_within_shift_Q4(sys);
        if ~isempty(ev)
            [sys, D] = handle_event_Q4(sys, D, ev, params, keep_timeline);
            [sys, D] = schedule_Q4(sys, D, params);
        else
            [sys, D] = schedule_Q4(sys, D, params);
            if ~has_event_within_shift_Q4(sys), break; end
        end
    end
    sys = end_of_shift_Q4(sys, keep_timeline);
end

% 指标采集（四格表 + 旧口径 + YXB + 更换占比）
sim = collect_metrics_Q4(D, sys, params);
sim.timeline   = sys.timeline;
sim.T_minutes  = sys.total_time;
end

function D = init_devices_Q4(n, params)
D = struct([]);
for i=n:-1:1
    D(i).id = i;
    D(i).true.A = rand()<params.p0.A;
    D(i).true.B = rand()<params.p0.B;
    D(i).true.C = rand()<params.p0.C;
    D(i).true.D = rand()<params.p0.D;
    D(i).bad    = D(i).true.A || D(i).true.B || D(i).true.C || D(i).true.D;
    D(i).pass.A = false; D(i).pass.B = false; D(i).pass.C = false; D(i).pass.E = false;
    D(i).tries.A= 0;     D(i).tries.B= 0;     D(i).tries.C= 0;     D(i).tries.E= 0;
    D(i).prob = params.p0;
    D(i).status   = 'waiting';
    D(i).location = 'queue';
end
end

function sys = init_system_Q4(params, Kmin)
sys.total_time = 0;
sys.shift_end  = Kmin;
sys.shift_length = Kmin;
sys.H240 = params.H240;
sys.H120 = params.H120;
sys.n_done     = 0;

sys.benches = struct('occupied',{false,false},'device_id',{0,0},'available_time',{0,0});

for s = ["A","B","C","E"]
    ss = char(s);
    sys.stn.(ss).occupied        = false;
    sys.stn.(ss).device_id       = 0;
    sys.stn.(ss).test_start_time = 0;
    sys.stn.(ss).work_time       = 0;      % 测试分钟
    sys.stn.(ss).life_used       = 0;      % 累计寿命
    sys.stn.(ss).pending_replace = false;
    sys.stn.(ss).blocked_until   = 0;
    sys.stn.(ss).L_first_fail    = sample_first_failure_Q4(params, ss);
    % —— Q4新增：更换统计 —— 
    sys.stn.(ss).replace_time    = 0;      % 更换占用分钟（不计入work_time）
    sys.stn.(ss).n_replace       = 0;      % 更换次数
    sys.stn.(ss).last_setup      = 0;      % 最近一次更换时长，用于时间线
end

sys.EQ = struct('type',{},'time',{},'dev',{},'st',{});
sys.timeline = [];
end

function L = sample_first_failure_Q4(params, s)
r1 = params.fail_r1.(s);
r2 = params.fail_r2.(s);
u  = rand();
if u < r1
    L = randi([0, params.H120]);
elseif u < r2
    L = params.H120 + randi([1, params.H120]);
else
    L = inf;
end
end

function [sys, D] = handle_event_Q4(sys, D, ev, params, keep_timeline)
switch ev.type
    case 'transport_done'
        D(ev.dev).status = 'testing';

    case 'test_complete'
        [sys, D] = on_test_complete_Q4(sys, D, ev.st, ev.dev, params, keep_timeline);

    case 'equip_failure'
        [sys, D] = on_equip_failure_Q4(sys, D, ev.st, params, keep_timeline);

    case 'replace_complete'
        s = ev.st;
        % 时间线（若是跨班安排的更换，则在完成时回填一段 replace）
        if keep_timeline && sys.stn.(s).last_setup>0
            seg.station = s; seg.start = ev.time - sys.stn.(s).last_setup; seg.finish = ev.time;
            seg.device  = 0; seg.label = 'replace';
            sys.timeline(end+1) = seg; %#ok<AGROW>
        end
        % 完成更换：解锁、寿命清零、重采样首故障阈值
        sys.stn.(s).pending_replace = false;
        sys.stn.(s).blocked_until   = 0;
        sys.stn.(s).life_used       = 0;
        sys.stn.(s).L_first_fail    = sample_first_failure_Q4(params, s);
end
end

function [sys, D] = on_test_complete_Q4(sys, D, s, id, params, keep_timeline)
% 真值
if s=='E', has_problem = D(id).bad; else, has_problem = D(id).true.(s); end
alpha = params.alpha.(s); beta = params.beta.(s);
if has_problem, pass = rand()<alpha; else, pass = rand()>=beta; end

% 贝叶斯（A/B/C）
if s~='E'
    p = D(id).prob.(s);
    if pass
        p = (p*alpha) / (p*alpha + (1-p)*(1-beta));
    else
        p = (p*(1-alpha)) / (p*(1-alpha) + (1-p)*beta);
    end
    D(id).prob.(s) = p;
end

% 时间线
if keep_timeline
    seg.station = s; seg.start = sys.stn.(s).test_start_time; seg.finish = sys.total_time;
    seg.device = id; seg.label = tern(pass,'test-pass','test-fail');
    sys.timeline(end+1) = seg; %#ok<AGROW>
end

% 结束逻辑
D(id).tries.(s) = D(id).tries.(s) + 1;
if pass
    D(id).pass.(s) = true;
    if s=='E'
        D(id).status = 'passed';
        sys.n_done = sys.n_done + 1;
        sys = release_bench_Q4(sys, id, params.t_out);
    end
else
    if D(id).tries.(s) >= 2
        D(id).status = 'failed';
        sys.n_done = sys.n_done + 1;
        sys = release_bench_Q4(sys, id, params.t_out);
    end
end

% 释放工位；计入测试工时与寿命
tt = params.tt.(s);
sys.stn.(s).occupied        = false;
sys.stn.(s).device_id       = 0;
sys.stn.(s).work_time       = sys.stn.(s).work_time + tt;
sys.stn.(s).life_used       = sys.stn.(s).life_used + tt;

% 触发强制更换
if sys.stn.(s).life_used >= params.H240 && ~sys.stn.(s).pending_replace
    sys = start_replacement_Q4(sys, s, params.setup.(s), keep_timeline);
end
end

function [sys, D] = on_equip_failure_Q4(sys, D, s, params, keep_timeline)
id = sys.stn.(s).device_id;
elapsed = sys.total_time - sys.stn.(s).test_start_time;
elapsed = max(0, round(elapsed));
sys.stn.(s).work_time = sys.stn.(s).work_time + elapsed;
sys.stn.(s).life_used = sys.stn.(s).life_used + elapsed;

if keep_timeline
    seg.station = s; seg.start = sys.stn.(s).test_start_time; seg.finish = sys.total_time;
    seg.device = id; seg.label = 'test-cut';
    sys.timeline(end+1) = seg; %#ok<AGROW>
end

sys.stn.(s).occupied        = false;
sys.stn.(s).device_id       = 0;
sys.stn.(s).test_start_time = 0;

sys = start_replacement_Q4(sys, s, params.setup.(s), keep_timeline);
end

function sys = start_replacement_Q4(sys, s, setup_min, keep_timeline)
rem = sys.shift_end - sys.total_time;
sys.stn.(s).pending_replace = true;
sys.stn.(s).n_replace       = sys.stn.(s).n_replace + 1;
sys.stn.(s).last_setup      = setup_min;
sys.stn.(s).replace_time    = sys.stn.(s).replace_time + setup_min;

if rem >= setup_min
    % 本班内完成
    sys.stn.(s).blocked_until = sys.total_time + setup_min;
    ev = make_event_Q4('replace_complete', sys.stn.(s).blocked_until, 0, s);
    sys = push_event_Q4(sys, ev);
    % 时间线立即记录更换段
    if keep_timeline
        seg.station = s; seg.start = sys.total_time; seg.finish = sys.total_time + setup_min;
        seg.device  = 0; seg.label = 'replace';
        sys.timeline(end+1) = seg; %#ok<AGROW>
    end
else
    % 跨班：安排到下一班开始做
    sys.stn.(s).blocked_until = sys.shift_end + setup_min;
    ev = make_event_Q4('replace_complete', sys.stn.(s).blocked_until, 0, s);
    sys = push_event_Q4(sys, ev);
    % 时间线在 replace_complete 时回填
end
end

function [sys, D] = schedule_Q4(sys, D, params)
% 空台进人
for b=1:2
    if ~sys.benches(b).occupied
        id = pick_next_waiting_Q4(D);
        if id>0
            sys.benches(b).occupied  = true;
            sys.benches(b).device_id = id;
            D(id).status   = 'arriving';
            D(id).location = sprintf('bench_%d', b);
            t_arrive = max(sys.benches(b).available_time, sys.total_time) + params.t_in;
            sys = push_event_Q4(sys, make_event_Q4('transport_done', t_arrive, id, ''));
        end
    end
end

% 在台候选
cand = [];
for b=1:2
    if sys.benches(b).occupied
        id = sys.benches(b).device_id;
        if strcmp(D(id).status,'testing'), cand(end+1)=id; end %#ok<AGROW>
    end
end
if isempty(cand), return; end

rem = sys.shift_end - sys.total_time;

% 评分
score = zeros(size(cand));
fits  = false(size(cand));
for k=1:numel(cand)
    id = cand(k);
    passABC = double(D(id).pass.A) + double(D(id).pass.B) + double(D(id).pass.C);

    can_any = false;
    if D(id).pass.A && D(id).pass.B && D(id).pass.C && ~D(id).pass.E && D(id).tries.E<2
        if rem >= params.tt.E && can_finish_life_Q4(sys,'E',params.tt.E)
            can_any = true;
        end
    end
    for s = ["A","B","C"]
        ss = char(s);
        if ~D(id).pass.(ss) && D(id).tries.(ss)<2
            if rem >= params.tt.(ss) && can_finish_life_Q4(sys, ss, params.tt.(ss))
                can_any = true; break;
            end
        end
    end
    fits(k) = can_any;

    score_exit = 0;
    for s = ["A","B","C"]
        ss = char(s);
        if ~D(id).pass.(ss) && D(id).tries.(ss)<2 ...
                && rem >= params.tt.(ss) && can_finish_life_Q4(sys, ss, params.tt.(ss))
            p     = D(id).prob.(ss);
            alpha = params.alpha.(ss); beta = params.beta.(ss);
            Pexit = p*(1-alpha)^2 + (1-p)*beta^2;
            score_exit = max(score_exit, Pexit / params.tt.(ss));
        end
    end
    score(k) = 10*passABC + score_exit;
end

if rem < 120, return; end

[~,ord] = sort(score,'descend');
cand = cand(ord);
fits = fits(ord);

for k=1:numel(cand)
    if ~fits(k), continue; end
    id = cand(k);

    % E
    if D(id).pass.A && D(id).pass.B && D(id).pass.C && ~D(id).pass.E && D(id).tries.E<2
        if can_start_Q4(sys,'E') && rem >= params.tt.E && can_finish_life_Q4(sys,'E',params.tt.E)
            sys = start_test_Q4(sys, id, 'E', params);
            rem = sys.shift_end - sys.total_time;
        end
    end

    % A/B/C 并行
    for s = ["A","B","C"]
        ss = char(s);
        if ~D(id).pass.(ss) && D(id).tries.(ss)<2
            if can_start_Q4(sys, ss) && rem >= params.tt.(ss) && can_finish_life_Q4(sys, ss, params.tt.(ss))
                sys = start_test_Q4(sys, id, ss, params);
                rem = sys.shift_end - sys.total_time;
            end
        end
    end
end
end

function ok = can_start_Q4(sys, s)
ok = ~sys.stn.(s).occupied && ~sys.stn.(s).pending_replace ...
     && sys.total_time >= sys.stn.(s).blocked_until ...
     && (sys.stn.(s).life_used < sys.H240);
end
function ok = can_finish_life_Q4(sys, s, tt)
ok = (sys.H240 - sys.stn.(s).life_used) >= tt;
end
function id = pick_next_waiting_Q4(D)
id = 0;
for i=1:numel(D)
    if strcmp(D(i).status,'waiting'), id=i; return; end
end
end

function sys = start_test_Q4(sys, id, s, params)
sys.stn.(s).occupied        = true;
sys.stn.(s).device_id       = id;
sys.stn.(s).test_start_time = sys.total_time;

tt = params.tt.(s);
L  = sys.stn.(s).L_first_fail;
U  = sys.stn.(s).life_used;

to_fail = isfinite(L) * max(1, L - U) + (~isfinite(L))*inf;
to240   = max(1, sys.H240 - U);
t_hit   = min([tt, to_fail, to240]);

if t_hit == tt
    ev = make_event_Q4('test_complete', sys.total_time + t_hit, id, s);
else
    ev = make_event_Q4('equip_failure', sys.total_time + t_hit, id, s);
end
sys = push_event_Q4(sys, ev);
end

function sys = end_of_shift_Q4(sys, keep_timeline)
for s = ["A","B","C","E"]
    ss = char(s);
    if sys.stn.(ss).occupied
        id = sys.stn.(ss).device_id;
        elapsed = sys.shift_end - sys.stn.(ss).test_start_time;
        elapsed = max(0, round(elapsed));
        sys.stn.(ss).work_time = sys.stn.(ss).work_time + elapsed;
        sys.stn.(ss).life_used = sys.stn.(ss).life_used + elapsed;
        if keep_timeline
            seg.station = ss; seg.start = sys.stn.(ss).test_start_time; seg.finish = sys.shift_end;
            seg.device  = id; seg.label = 'shift-cut';
            sys.timeline(end+1) = seg; %#ok<AGROW>
        end
        sys.stn.(ss).occupied        = false;
        sys.stn.(ss).device_id       = 0;
        sys.stn.(ss).test_start_time = 0;
    end
end
sys.total_time = sys.shift_end;
sys.shift_end  = sys.total_time + sys.shift_length;
end

function [sys, ev] = pop_event_if_within_shift_Q4(sys)
ev = [];
if isempty(sys.EQ), return; end
nxt = sys.EQ(1);
if nxt.time <= sys.shift_end
    ev = nxt; sys.EQ(1) = [];
    dt = ev.time - sys.total_time; %#ok<NASGU>
    sys.total_time = ev.time;
end
end
function tf = has_event_within_shift_Q4(sys)
if isempty(sys.EQ), tf=false; else, tf = sys.EQ(1).time <= sys.shift_end; end
end
function sys = push_event_Q4(sys, ev)
if isempty(sys.EQ), sys.EQ = ev; return; end
t = [sys.EQ.time];
k = find(ev.time < t, 1, 'first');
if isempty(k), sys.EQ(end+1)=ev; else, sys.EQ = [sys.EQ(1:k-1), ev, sys.EQ(k:end)]; end
end
function ev = make_event_Q4(type, time, dev, st)
ev.type = type; ev.time = round(time); ev.dev = dev; ev.st = st;
end

function sys = release_bench_Q4(sys, id, t_out)
for b=1:2
    if sys.benches(b).device_id == id
        sys.benches(b).occupied       = false;
        sys.benches(b).device_id      = 0;
        sys.benches(b).available_time = max(sys.benches(b).available_time, sys.total_time) + t_out;
        return;
    end
end
end

function sim = collect_metrics_Q4(D, sys, params)
sim = struct();
sim.T_minutes = sys.total_time;
sim.N         = numel(D);

pass_idx = strcmp({D.status}, 'passed');
fail_idx = strcmp({D.status}, 'failed');
n_passed = sum(pass_idx);
n_failed = sum(fail_idx);

sim.n_passed = n_passed;
sim.n_failed = n_failed;

sim.P = n_failed;      % 预测 FAIL = TP + FP
sim.F = n_passed;      % 预测 PASS = TN + FN

bad       = [D.bad];
pred_fail = fail_idx; 
pred_pass = pass_idx;

sim.TP = sum( bad  & pred_fail );
sim.FP = sum(~bad  & pred_fail );
sim.TN = sum(~bad  & pred_pass );
sim.FN = sum( bad  & pred_pass );

% 宏平均参考
sim.PL_cond = (n_passed>0) * sim.FN / max(1,(sim.FN + sim.TN));
sim.PW_cond = (n_failed>0) * sim.FP / max(1,(sim.FP + sim.TP));

% 每班归一的有效工时比 + 更换占比
Kmin = sys.shift_length;
total_shifts = max(1, ceil(sim.T_minutes / Kmin));
sim.YXB = zeros(1,4); sim.REPL_share = zeros(1,4);
for i=1:4
    s = params.stations{i};
    sim.YXB(i)        = sys.stn.(s).work_time     / (total_shifts * Kmin);
    sim.REPL_share(i) = sys.stn.(s).replace_time / (total_shifts * Kmin);
end
end


%% ======================================================================
%%                      （E）统计、CI、可视化、报告
%% ======================================================================
function [S, Tdist] = summarize_stats_Q4(T_days, S_pass, PL_macro, PW_macro, YXB_mat, agg)
S = struct();
S.T_mean   = mean(T_days); S.T_std   = std(T_days);
S.S_mean   = mean(S_pass); S.S_std   = std(S_pass);
S.PL_macro_mean = mean(PL_macro);  S.PL_macro_std = std(PL_macro);
S.PW_macro_mean = mean(PW_macro);  S.PW_macro_std = std(PW_macro);
S.YXB_mean = mean(YXB_mat,1); S.YXB_std = std(YXB_mat,0,1);
TP=agg.TP; FP=agg.FP; TN=agg.TN; FN=agg.FN; N=agg.N;
[S.FPR, S.FPR_lo, S.FPR_hi] = wilson_ci_Q4(FP, FP+TN);
[S.FNR, S.FNR_lo, S.FNR_hi] = wilson_ci_Q4(FN, FN+TP);
[S.FDR, S.FDR_lo, S.FDR_hi] = wilson_ci_Q4(FP, FP+TP);
[S.FOR, S.FOR_lo, S.FOR_hi] = wilson_ci_Q4(FN, FN+TN);
[S.PL_uncond, S.PL_uncond_lo, S.PL_uncond_hi] = wilson_ci_Q4(FN, N);
[S.PW_uncond, S.PW_uncond_lo, S.PW_uncond_hi] = wilson_ci_Q4(FP, N);
Tdist = T_days;
end
function [p, lo, hi] = wilson_ci_Q4(k, n)
if n<=0, p=0; lo=0; hi=0; return; end
z = 1.96; phat = k/n; den = 1 + z^2/n;
center = (phat + z^2/(2*n)) / den;
half   = (z/den) * sqrt( (phat*(1-phat)/n) + (z^2/(4*n^2)) );
p  = phat; lo = max(0, center - half); hi = min(1, center + half);
end

function T = table_from_Res_Q4(Res)
T = table(Res.K, Res.T_mean, Res.T_std, Res.S_mean, Res.S_std, ...
    Res.FPR, Res.FPR_lo, Res.FPR_hi, Res.FNR, Res.FNR_lo, Res.FNR_hi, ...
    Res.FDR, Res.FDR_lo, Res.FDR_hi, Res.FOR, Res.FOR_lo, Res.FOR_hi, ...
    Res.YXB_mean(:,1), Res.YXB_mean(:,2), Res.YXB_mean(:,3), Res.YXB_mean(:,4), ...
    'VariableNames', {'K_h','T_mean','T_std','S_mean','S_std', ...
    'FPR','FPR_lo','FPR_hi','FNR','FNR_lo','FNR_hi', ...
    'FDR','FDR_lo','FDR_hi','FOR','FOR_lo','FOR_hi', ...
    'YXB_A','YXB_B','YXB_C','YXB_E'});
end

function visualize_across_K_Q4(Res, params)
figure('Position',[60,60,1400,520],'Color','w');

subplot(1,2,1); hold on; box on; grid on;
errorbar(Res.K, Res.T_mean, Res.T_std, '-o', 'LineWidth',1.4, 'MarkerFaceColor',[0.2 0.5 0.8]);
xlabel('班次长度 K（小时）'); ylabel('完工时间 T（天）');
title('T(K)：均值 ± Std','FontWeight','bold');

subplot(1,2,2); hold on; box on; grid on;
plot(Res.K, Res.FPR, '-s', 'LineWidth',1.4, 'MarkerFaceColor',[0.7 0.3 0.3]);
plot(Res.K, Res.FNR, '-d', 'LineWidth',1.4, 'MarkerFaceColor',[0.3 0.7 0.3]);
legend({'FPR','FNR'}, 'Location','northwest');
xlabel('班次长度 K（小时）'); ylabel('比例');
title('总体能力（FPR/FNR）随 K','FontWeight','bold');
sgtitle('问题3：跨K对比（micro + Wilson）','FontWeight','bold');
end

function visualize_bestK_details_Q4(Res, best_idx, params)
figure('Position',[70,70,1400,860],'Color','w');

subplot(2,2,1); 
histogram(Res.T_all{best_idx}, 20, 'FaceColor',[0.3 0.6 0.9], 'EdgeColor','none'); grid on; box on;
xlabel('T（天）'); ylabel('频数');
title(sprintf('最佳K=%.1f 的 T 分布 (\\mu=%.3f, \\sigma=%.3f)', Res.K(best_idx), Res.T_mean(best_idx), Res.T_std(best_idx)),'FontWeight','bold');

subplot(2,2,2); 
bar(Res.YXB_mean(best_idx,:), 'FaceColor',[0.8 0.4 0.4]); hold on;
errorbar(1:4, Res.YXB_mean(best_idx,:), Res.YXB_std(best_idx,:), 'k.', 'LineWidth',1.2);
set(gca,'XTick',1:4,'XTickLabel',params.stations);
ylabel('有效工时比（每班归一）'); grid on; box on;
title('YXB（最佳K）','FontWeight','bold');

subplot(2,2,3); hold on; box on; grid on;
vals = [Res.FDR(best_idx) Res.FOR(best_idx)];
los  = [Res.FDR_lo(best_idx) Res.FOR_lo(best_idx)];
his  = [Res.FDR_hi(best_idx) Res.FOR_hi(best_idx)];
eb   = [vals-los; his-vals];
bar(vals, 0.6, 'FaceColor',[0.6 0.6 0.9]);
errorbar(1:2, vals, eb(1,:), eb(2,:), 'k.', 'LineWidth',1.2);
set(gca,'XTick',1:2,'XTickLabel',{'FDR','FOR'});
ylabel('比例'); title('结果口径（最佳K）','FontWeight','bold');

subplot(2,2,4); hold on; box on; grid on;
vals = [Res.FPR(best_idx) Res.FNR(best_idx)];
los  = [Res.FPR_lo(best_idx) Res.FNR_lo(best_idx)];
his  = [Res.FPR_hi(best_idx) Res.FNR_hi(best_idx)];
eb   = [vals-los; his-vals];
bar(vals, 0.6, 'FaceColor',[0.6 0.9 0.6]);
errorbar(1:2, vals, eb(1,:), eb(2,:), 'k.', 'LineWidth',1.2);
set(gca,'XTick',1:2,'XTickLabel',{'FPR','FNR'});
ylabel('比例'); title('总体能力（最佳K）','FontWeight','bold');

sgtitle(sprintf('最佳K=%.1f 的细节指标', Res.K(best_idx)),'FontWeight','bold');
end

function visualize_gantt_Q4(timeline, T_end, params, Kmin)
if isempty(timeline), return; end
stations = params.stations;
cmap = containers.Map( ...
    {'test-pass','test-fail','test-cut','replace','shift-cut'}, ...
    {[0.2 0.7 0.3],[0.85 0.3 0.3],[0.95 0.7 0.2],[0.3 0.5 0.85],[0.7 0.7 0.7]});
figure('Position',[80,80,1400,500],'Color','w'); 
for si = 1:4
    s = stations{si};
    subplot(4,1,si); hold on; box on; grid on;
    sel = arrayfun(@(z) strcmp(z.station,s), timeline);
    segs = timeline(sel);
    for k=1:numel(segs)
        st = segs(k).start; ed = segs(k).finish;
        if ed<=st, continue; end
        yv= [0.25 0.25 0.75 0.75];
        if isKey(cmap, segs(k).label), c = cmap(segs(k).label); else, c=[0.5 0.5 0.5]; end
        patch([st ed ed st], yv, c, 'EdgeColor','none','FaceAlpha',0.95);
        if ed-st >= params.tt.(s)/2 && segs(k).device>0
            text(st + 5, 0.5, sprintf('#%d',segs(k).device), 'Color','w', 'FontSize',8, 'VerticalAlignment','middle');
        end
    end
    for t = 0:Kmin:T_end
        plot([t t], [0.2 0.8], ':', 'Color',[0.2 0.2 0.2], 'LineWidth',0.5);
    end
    xlim([0 T_end]); ylim([0 1]); yticks([]);
    title(sprintf('工位 %s 时间线', s),'FontWeight','bold');
    if si==4, xlabel('时间（分钟）'); end
end
sgtitle('单次运行甘特图（测试/故障/更换/换班）','FontWeight','bold');
end

function visualize_tornado_Q4(tornado)
figure('Position',[90,90,780,520],'Color','w');
barh(tornado.abs_elasticity, 'FaceColor',[0.3 0.6 0.9]); grid on; box on;
set(gca,'YTick',1:height(tornado),'YTickLabel',tornado.factor);
xlabel('|\Delta T / T| / |\Delta 参数 / 参数| （弹性）');
title('问题4：单因素灵敏度 Tornado 图（CRN, ±扰动）','FontWeight','bold');
end

function visualize_station_stack_Q4(stack)
figure('Position',[100,100,960,520],'Color','w');

test = stack.YXB_mean(:)';                 % 测试占比
repl = stack.RP_mean(:)';                  % 更换占比
idle = max(0, 1 - test - repl);            % 空闲占比（保底非负）

M = [test; repl; idle]';                   % 4×3 矩阵：每站三层
bh = bar(M, 'stacked'); grid on; box on;   % 正确的堆叠方式
bh(1).FaceColor = [0.30 0.70 0.40];        % 测试
bh(2).FaceColor = [0.30 0.50 0.85];        % 更换
bh(3).FaceColor = [0.80 0.80 0.80];        % 空闲

xticklabels({'A','B','C','E'});
ylabel('每班归一占比'); ylim([0 1]);
legend({'测试','更换','空闲'}, 'Location','southoutside','Orientation','horizontal');
title('最佳K下的工位时间占比：测试/更换/空闲','FontWeight','bold');
end

function approx = analytic_sanity_Q4(params)
bA = params.beta.A; bB = params.beta.B; bC = params.beta.C; bE = params.beta.E;
FPR_approx = bA^2 + bB^2 + bC^2 + (1 - (bA^2+bB^2+bC^2))*bE^2;
aA = params.alpha.A; aB = params.alpha.B; aC = params.alpha.C; aE = params.alpha.E;
alpha_bar = mean([aA,aB,aC]);
FNR_approx = alpha_bar * aE;
approx = struct('FPR', FPR_approx, 'FNR', FNR_approx);
end

function pairtbl = compute_pairwise_tests_Q4(Res, T_table, best_idx)
ref = best_idx; K = Res.K(:); nK = numel(K);
pairtbl = cell(nK-1, 6);
row = 1;
for ki=1:nK
    if ki==ref, continue; end
    Delta = T_table(ki,:) - T_table(ref,:);
    [~,p,ci,~] = ttest(Delta);
    pairtbl(row,:) = { K(ki), mean(Delta), ci(1), ci(2), p, numel(Delta) };
    row = row + 1;
end
end

function generate_report_Q4(Res, best_idx, params, cfg, sanity, pairtbl, OAT_tbl)
fid = fopen('report_Q4.md','w');
fprintf(fid, '# 问题4：因素灵敏度分析与改进建议（基于问题3模型）\n\n');
fprintf(fid, '## 工作节拍与规则\n');
fprintf(fid, '- 双分队接续倒班，24/7 无间隙；测试不得跨班（<=合规），运入/运出可跨班，更换不得跨班；设备寿命跨班连续，开工需满足 `U+τ≤240h`。\n\n');

fprintf(fid, '## 最优班次长度\n');
fprintf(fid, '- 候选 K∈%s；按平均完工时间最小得到 **K* = %.1f h**。\n\n', mat2str(cfg.K_list_hours), Res.K(best_idx));

fprintf(fid, '## 主要指标（K=%.1f h）\n', Res.K(best_idx));
fprintf(fid, '- T(mean±std) = %.3f±%.3f 天；S(mean±std) = %.1f±%.1f。\n', ...
    Res.T_mean(best_idx), Res.T_std(best_idx), Res.S_mean(best_idx), Res.S_std(best_idx));
fprintf(fid, '- FPR = %.4g [%.4g, %.4g]；FNR = %.4g [%.4g, %.4g]（Wilson95%%CI）。\n\n', ...
    Res.FPR(best_idx), Res.FPR_lo(best_idx), Res.FPR_hi(best_idx), ...
    Res.FNR(best_idx), Res.FNR_lo(best_idx), Res.FNR_hi(best_idx));

fprintf(fid, '## 解析近似（量级解释）\n');
fprintf(fid, '- 近似 FPR≈**%.6f**，FNR≈**%.6f**（两次同站误判；坏项漏判×E漏判）。与仿真同量级，解释"为何很小"。\n\n', sanity.FPR, sanity.FNR);

fprintf(fid, '## 显著性（CRN 配对，K* vs 其他K）\n');
fprintf(fid, '|K(h)|ΔT_mean(天)|95%%CI_low|95%%CI_high|p-value|n|\n|---:|---:|---:|---:|---:|---:|\n');
for r=1:size(pairtbl,1)
    fprintf(fid,'|%.1f|%.4f|%.4f|%.4f|%.3g|%d|\n', pairtbl{r,1}, pairtbl{r,2}, pairtbl{r,3}, pairtbl{r,4}, pairtbl{r,5}, pairtbl{r,6});
end
fprintf(fid, '\n');

fprintf(fid, '## 单因素灵敏度（OAT, CRN, ±扰动）\n');
fprintf(fid, '- 表 `Q4_sensitivity_OAT.csv` 给出每个因素的 ΔT、弹性与p值；下图为 Tornado 排序图。\n\n');

fprintf(fid, '## 建议（按优先级）\n');
fprintf(fid, '1. **缩短 E 工位名义时长 τ_E**（流程并行/自动化）：若 YXB_E 较高，τ_E 降 10%% 通常带来 ≈(YXB_E×10%%) 的 T 下降。\n');
fprintf(fid, '2. **缩短 E 工位更换时间 c_E**（快速换模/SMED）：既降停机又降低"更换不得跨班"导致的窗口损失。\n');
fprintf(fid, '3. **采用 K=%.1f h 的班长**（装箱更紧）：与 {120,150,180,20,30,40} 更相容。\n', Res.K(best_idx));
fprintf(fid, '4. **班初优先完成待更换**、班末按"能装下"规则装箱，固定为标准作业卡。\n\n');

fprintf(fid, '_注：全部结果使用共同随机数（CRN）控制方差，FPR/FNR 报告 Wilson95%%区间。_\n');
fclose(fid);
disp('已生成 report_Q4.md');
end

function save_all_figs_Q4()
figs = findall(0,'Type','figure');
for k=1:numel(figs)
    try
        figure(figs(k));
        name = sprintf('fig_%02d', k);
        set(gcf,'PaperPositionMode','auto');
        print(gcf, '-dpdf', [name '.pdf']);
        print(gcf, '-dpng', '-r300', [name '.png']);
    catch
    end
end
end

function out = tern(cond, a, b)
if cond, out=a; else, out=b; end
end
