% Q3_two_shifts_robust.m
% 问题3：双分队接续倒班（分钟级）、A/B/C并行、设备跨班共享
% - 班次长度 K ∈ {9,9.5,10,10.5,11,11.5,12} 小时，24/7 连续交替，无间隙
% - 测试不得跨班（<= 边界完成合规，buffer=0）；运入/运出可跨班；更换不得跨班
% - 240h 强制更换；开工硬门槛：U + tau <= 240h；首故障阈值抽样
% - 稳健统计：FPR/FNR、FDR/FOR（micro + Wilson 95%CI）、无条件发生率
% - 可视化：T(K) 误差棒、最佳K分布 & YXB、FPR/FNR/FDR/FOR 条形、甘特图
%
% 作者：<your name>
% 日期：2025-08-31

function Q3_two_shifts_robust
clc; clear; close all;

%% =================== 参数与配置 ===================
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

% —— 仿真配置 ——
cfg = struct();
cfg.parallel_ABC     = true;                 % 同装置 A/B/C 并行
cfg.n_devices        = 100;                  % 每批规模
cfg.n_replications   = 250;                  % 每个K的重复次数（可加大更稳）
cfg.K_list_hours     = [9 9.5 10 10.5 11 11.5 12];  % 候选班长（小时）
cfg.verbose_every    = 25;                   % 进度打印频率（按每个K）
cfg.random_seed_base = 20250831;             % CRN：按rep设种子，跨K复用
cfg.draw_gantt_forK  = 12;                   % 选择画甘特图的K（小时）

% —— 常量 —— 
params.H240 = 240*60;                        % 240小时（分钟）
params.H120 = 120*60;                        % 120小时（分钟）

%% =================== 数据结构（跨K聚合与展示） ===================
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

% 为可视化保留分布（T）
Res.T_all = cell(nK,1);

% 记录最佳K的一次完整时间线用于甘特图
timeline_bestK = []; T_end_bestK = []; bestK_idx = [];

fprintf('=== 问题3：双分队接续倒班（分钟级）仿真开始 ===\n');

for ki = 1:nK
    K = Klist(ki);
    Kmin = round(K*60); % 班长（分钟），用于边界
    fprintf('\n[K = %.1f 小时] Monte Carlo x %d ...\n', K, R);

    % 结果容器（单K）
    T_days   = zeros(R,1);
    S_pass   = zeros(R,1);
    YXB_mat  = zeros(R,4);
    % 宏平均参考（不用于判优）
    PL_macro = zeros(R,1); % FOR 单次比值
    PW_macro = zeros(R,1); % FDR 单次比值

    % 微平均聚合（跨rep 累加计数）
    agg = struct('TP',0,'FP',0,'TN',0,'FN',0,'P',0,'F',0,'N',0);

    % 单K的随机流：按rep复用同一seed（CRN思想：跨K一致）
    for rep = 1:R
        if cfg.verbose_every>0 && mod(rep,cfg.verbose_every)==0
            fprintf('  -> rep %d/%d\n', rep, R);
        end
        rng(cfg.random_seed_base + rep, 'twister');

        % 单次仿真
        sim = run_single_simulation_Q3(params, cfg, Kmin, (K==cfg.draw_gantt_forK) && isempty(timeline_bestK));

        % === per-run 输出 ===
        T_days(rep)   = sim.T_minutes / 1440;
        S_pass(rep)   = sim.n_passed;
        PL_macro(rep) = sim.PL_cond;  % FOR（条件于PASS）
        PW_macro(rep) = sim.PW_cond;  % FDR（条件于FAIL）
        YXB_mat(rep,:)= sim.YXB;

        % === 微平均累积 ===
        agg.TP = agg.TP + sim.TP;
        agg.FP = agg.FP + sim.FP;
        agg.TN = agg.TN + sim.TN;
        agg.FN = agg.FN + sim.FN;
        agg.P  = agg.P  + sim.P;
        agg.F  = agg.F  + sim.F;
        agg.N  = agg.N  + sim.N;

        % 保存甘特样本
        if (K==cfg.draw_gantt_forK) && isempty(timeline_bestK)
            timeline_bestK = sim.timeline;
            T_end_bestK    = sim.T_minutes;
            bestK_idx      = ki;
        end
    end

    % === 统计（micro + Wilson） ===
    [Srow, Tdistro] = summarize_stats_Q3(T_days, S_pass, PL_macro, PW_macro, YXB_mat, agg);
    % 填入结果
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

%% =================== 选择最优 K* 并打印 ===================
[~,best_idx] = min(Res.T_mean);
bestK = Res.K(best_idx);
fprintf('\n=== 统计汇总（micro + Wilson） ===\n');
for ki = 1:nK
    fprintf('K=%.1f:  T=%.3f±%.3f  S=%.2f±%.2f  [FPR=%.5f,FNR=%.5f]\n', ...
        Res.K(ki), Res.T_mean(ki), Res.T_std(ki), Res.S_mean(ki), Res.S_std(ki), Res.FPR(ki), Res.FNR(ki));
end
fprintf('=> 最优 K* = %.1f 小时（按 T 平均最小）\n', bestK);

%% =================== 可视化：跨K、最佳K、甘特 ===================
visualize_across_K(Res, params);
visualize_bestK_details(Res, best_idx, params);
if ~isempty(timeline_bestK)
    visualize_gantt_Q3(timeline_bestK, T_end_bestK, params, round(Res.K(best_idx)*60));
end

%% =================== 保存 ===================
save('Q3_two_shifts_robust_results.mat', 'Res', 'params', 'cfg', 'timeline_bestK', 'T_end_bestK', 'best_idx');
fprintf('已保存结果至 Q3_two_shifts_robust_results.mat\n');

end % main


%% ======================================================================
%%                          单 次 仿 真（Q3）
%% ======================================================================
function sim = run_single_simulation_Q3(params, cfg, Kmin, keep_timeline)

% 初始化装置
D = init_devices_Q3(cfg.n_devices, params);

% 初始化系统
sys = init_system_Q3(params, Kmin);

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

% 主循环：以"当前班次窗口 [t, shift_end)"为单位推进
while sys.n_done < numel(D)
    % —— 班内循环：处理所有"在本班边界之前"的事件；若队列中最早事件越界，则班末收口 ——
    while true
        [sys, ev] = pop_event_if_within_shift_Q3(sys);  % 仅取 <= shift_end 的事件
        if ~isempty(ev)
            [sys, D] = handle_event_Q3(sys, D, ev, params, keep_timeline);
            % 事件后可立即尝试调度
            [sys, D] = schedule_Q3(sys, D, params);
        else
            % 没有可在本班内发生的事件；尝试调度（可能在本班内产生"完成前"的事件）
            [sys, D] = schedule_Q3(sys, D, params);
            % 若仍不存在"<=shift_end"的事件，则结束本班
            if ~has_event_within_shift(sys)
                break;
            end
        end
    end

    % —— 班末：守卫（不得有测试在进行），并推进到边界，切换到下一班 ——
    sys = end_of_shift_Q3(sys, keep_timeline);
end

% 指标采集（四格表 + 旧口径 + YXB）
sim = collect_metrics_Q3(D, sys, params);

% 时间线
sim.timeline   = sys.timeline;
sim.T_minutes  = sys.total_time;

end


%% ======================================================================
%%                             初始化
%% ======================================================================
function D = init_devices_Q3(n, params)
D = struct([]);
for i=n:-1:1
    D(i).id = i;

    % 真实缺陷
    D(i).true.A = rand()<params.p0.A;
    D(i).true.B = rand()<params.p0.B;
    D(i).true.C = rand()<params.p0.C;
    D(i).true.D = rand()<params.p0.D;
    D(i).bad    = D(i).true.A || D(i).true.B || D(i).true.C || D(i).true.D;

    % 单项状态
    D(i).pass.A = false; D(i).pass.B = false; D(i).pass.C = false; D(i).pass.E = false;
    D(i).tries.A= 0;     D(i).tries.B= 0;     D(i).tries.C= 0;     D(i).tries.E= 0;

    % 信念（A/B/C 用于调度评分；E不回灌）
    D(i).prob = params.p0;

    % 流程状态
    D(i).status   = 'waiting';
    D(i).location = 'queue';
end
end

function sys = init_system_Q3(params, Kmin)
sys.total_time = 0;                % 全局分钟
sys.shift_end  = Kmin;             % 当前班次的结束时刻（分钟）
% >>> 新增：保存班长与 120h/240h 常量到 sys <<<
sys.shift_length = Kmin;           % 班次长度（分钟）
sys.H240 = params.H240;            % 240h（分钟）
sys.H120 = params.H120;            % 120h（分钟）
sys.n_done     = 0;

% 2 个测试台
sys.benches = struct('occupied',{false,false},'device_id',{0,0},'available_time',{0,0});

% 工位
for s = ["A","B","C","E"]
    ss = char(s);
    sys.stn.(ss).occupied        = false;
    sys.stn.(ss).device_id       = 0;
    sys.stn.(ss).test_start_time = 0;
    sys.stn.(ss).work_time       = 0;      % 纯测试分钟累计
    sys.stn.(ss).life_used       = 0;      % 累计寿命（分钟）
    sys.stn.(ss).pending_replace = false;  % 待更换（阻塞）
    sys.stn.(ss).blocked_until   = 0;      % 更换将完成的时刻
    sys.stn.(ss).L_first_fail    = sample_first_failure_Q3(params, ss); % 首故障阈值（分钟）
end

% 事件队列（按 time 升序）
sys.EQ = struct('type',{},'time',{},'dev',{},'st',{});

% 时间线（甘特）
sys.timeline = [];
end

function L = sample_first_failure_Q3(params, s)
r1 = params.fail_r1.(s);
r2 = params.fail_r2.(s);
u  = rand();
if u < r1
    L = randi([0, params.H120]);                   % [0, 120h]
elseif u < r2
    L = params.H120 + randi([1, params.H120]);     % (120h, 240h]
else
    L = inf;                                       % 240h 内不故障
end
end


%% ======================================================================
%%                               事件处理
%% ======================================================================
function [sys, D] = handle_event_Q3(sys, D, ev, params, keep_timeline)
switch ev.type
    case 'transport_done'
        D(ev.dev).status = 'testing';

    case 'test_complete'
        [sys, D] = on_test_complete_Q3(sys, D, ev.st, ev.dev, params, keep_timeline);

    case 'equip_failure'
        [sys, D] = on_equip_failure_Q3(sys, D, ev.st, params, keep_timeline);

    case 'replace_complete'
        s = ev.st;
        % 完成更换：解锁、寿命清零、重采样首故障阈值
        sys.stn.(s).pending_replace = false;
        sys.stn.(s).blocked_until   = 0;
        sys.stn.(s).life_used       = 0;
        sys.stn.(s).L_first_fail    = sample_first_failure_Q3(params, s);
end
end

function [sys, D] = on_test_complete_Q3(sys, D, s, id, params, keep_timeline)
% 判定真值：E 对 any，其它对单项
if s=='E'
    has_problem = D(id).bad;
else
    has_problem = D(id).true.(s);
end

% 判定（α=漏判、β=误判）
alpha = params.alpha.(s); beta = params.beta.(s);
if has_problem
    pass = rand() < alpha;         % 漏判通过
else
    pass = rand() >= beta;         % 正确通过（1-β）
end

% 贝叶斯更新（A/B/C）
if s~='E'
    p = D(id).prob.(s);
    if pass
        p = (p*alpha) / (p*alpha + (1-p)*(1-beta));
    else
        p = (p*(1-alpha)) / (p*(1-alpha) + (1-p)*beta);
    end
    D(id).prob.(s) = p;
end

% 时间线：记录完成段
if keep_timeline
    seg.station = s; seg.start = sys.stn.(s).test_start_time; seg.finish = sys.total_time;
    seg.device = id; seg.label = tern(pass,'test-pass','test-fail');
    sys.timeline(end+1) = seg; %#ok<AGROW>
end

% 尝试数 +1；通过或"两次失败"结束该工序
D(id).tries.(s) = D(id).tries.(s) + 1;
if pass
    D(id).pass.(s) = true;
    if s=='E'
        D(id).status = 'passed';
        sys.n_done = sys.n_done + 1;
        sys = release_bench_Q3(sys, id, params.t_out);
    end
else
    if D(id).tries.(s) >= 2
        D(id).status = 'failed';
        sys.n_done = sys.n_done + 1;
        sys = release_bench_Q3(sys, id, params.t_out);
    end
end

% 释放工位；计入工时与寿命
tt = params.tt.(s);
sys.stn.(s).occupied        = false;
sys.stn.(s).device_id       = 0;
sys.stn.(s).work_time       = sys.stn.(s).work_time + tt;
sys.stn.(s).life_used       = sys.stn.(s).life_used + tt;

% 若寿命达 240h，进入强制更换（不得跨班：若本班不足则延后到下一班）
if sys.stn.(s).life_used >= params.H240 && ~sys.stn.(s).pending_replace
    sys = start_replacement_Q3(sys, s, params.setup.(s));
end
end

function [sys, D] = on_equip_failure_Q3(sys, D, s, params, keep_timeline)
% 故障/强制更换：中断当前测试（不计尝试），累计已用
id = sys.stn.(s).device_id;
elapsed = sys.total_time - sys.stn.(s).test_start_time;
elapsed = max(0, round(elapsed));
sys.stn.(s).work_time = sys.stn.(s).work_time + elapsed;
sys.stn.(s).life_used = sys.stn.(s).life_used + elapsed;

% 时间线：记录中断段
if keep_timeline
    seg.station = s; seg.start = sys.stn.(s).test_start_time; seg.finish = sys.total_time;
    seg.device = id; seg.label = 'test-cut';
    sys.timeline(end+1) = seg; %#ok<AGROW>
end

% 释放工位
sys.stn.(s).occupied        = false;
sys.stn.(s).device_id       = 0;
sys.stn.(s).test_start_time = 0;

% 进入更换流程（不得跨班）
sys = start_replacement_Q3(sys, s, params.setup.(s));
end

function sys = start_replacement_Q3(sys, s, setup_min)
% 若本班剩余时间足以完成更换，立即开始并在本班内完成
rem = sys.shift_end - sys.total_time;
if rem >= setup_min
    sys.stn.(s).pending_replace = true;
    sys.stn.(s).blocked_until   = sys.total_time + setup_min;
    ev = make_event_Q3('replace_complete', sys.stn.(s).blocked_until, 0, s);
    sys = push_event_Q3(sys, ev);
else
    % 否则推迟到下一班开始再做：在下一班开始时刻起用 setup_min 完成
    sys.stn.(s).pending_replace = true;
    sys.stn.(s).blocked_until   = sys.shift_end + setup_min;
    ev = make_event_Q3('replace_complete', sys.stn.(s).blocked_until, 0, s);
    sys = push_event_Q3(sys, ev);
end
end


%% ======================================================================
%%                                调 度
%% ======================================================================
function [sys, D] = schedule_Q3(sys, D, params)
% 1) 给空测试台安排下一台（FIFO）
for b=1:2
    if ~sys.benches(b).occupied
        id = pick_next_waiting_Q3(D);
        if id>0
            sys.benches(b).occupied  = true;
            sys.benches(b).device_id = id;
            D(id).status   = 'arriving';
            D(id).location = sprintf('bench_%d', b);
            t_arrive = max(sys.benches(b).available_time, sys.total_time) + params.t_in; % 可跨班
            sys = push_event_Q3(sys, make_event_Q3('transport_done', t_arrive, id, ''));
        end
    end
end

% 2) 选择在台可调度的装置
cand = [];
for b=1:2
    if sys.benches(b).occupied
        id = sys.benches(b).device_id;
        if strcmp(D(id).status,'testing')
            cand(end+1) = id; %#ok<AGROW>
        end
    end
end
if isempty(cand), return; end

% 3) 班内剩余
rem = sys.shift_end - sys.total_time;

% 4) 评分：近E优先 + 单位时间淘汰贡献（只考虑 fits-in-window 的工序）
score = zeros(size(cand));
fits  = false(size(cand));
for k=1:numel(cand)
    id = cand(k);
    passABC = double(D(id).pass.A) + double(D(id).pass.B) + double(D(id).pass.C);

    % 计算本装置是否还有任何"可在本班完成"的工序（含E）
    can_any = false;
    if D(id).pass.A && D(id).pass.B && D(id).pass.C && ~D(id).pass.E && D(id).tries.E<2
        if rem >= params.tt.E && can_finish_life_Q3(sys,'E',params.tt.E)
            can_any = true;
        end
    end
    for s = ["A","B","C"]
        ss = char(s);
        if ~D(id).pass.(ss) && D(id).tries.(ss)<2
            if rem >= params.tt.(ss) && can_finish_life_Q3(sys, ss, params.tt.(ss))
                can_any = true; break;
            end
        end
    end
    fits(k) = can_any;

    % 分值
    score_exit = 0;
    for s = ["A","B","C"]
        ss = char(s);
        if ~D(id).pass.(ss) && D(id).tries.(ss)<2 ...
                && rem >= params.tt.(ss) && can_finish_life_Q3(sys, ss, params.tt.(ss))
            p     = D(id).prob.(ss);
            alpha = params.alpha.(ss); beta = params.beta.(ss);
            Pexit = p*(1-alpha)^2 + (1-p)*beta^2; % 两次"未通过"淘汰概率近似
            score_exit = max(score_exit, Pexit / params.tt.(ss));
        end
    end
    score(k) = 10*passABC + score_exit; % "近E优先"权重大
end

% 5) 若本班剩余 < 120min，则不再启动任何测试（仅做运入/运出）
if rem < 120
    return;
end

% 6) 按分值排序，逐个装置尝试启动 A/B/C 并行与 E
[~,ord] = sort(score,'descend');
cand = cand(ord);
fits = fits(ord);

for k=1:numel(cand)
    if ~fits(k), continue; end
    id = cand(k);

    % E（优先尝试）
    if D(id).pass.A && D(id).pass.B && D(id).pass.C && ~D(id).pass.E && D(id).tries.E<2
        if can_start_Q3(sys,'E') && rem >= params.tt.E && can_finish_life_Q3(sys,'E',params.tt.E)
            sys = start_test_Q3(sys, id, 'E', params);
            rem = sys.shift_end - sys.total_time; % 更新剩余
        end
    end

    % A/B/C 并行尝试
    for s = ["A","B","C"]
        ss = char(s);
        if ~D(id).pass.(ss) && D(id).tries.(ss)<2
            if can_start_Q3(sys, ss) && rem >= params.tt.(ss) && can_finish_life_Q3(sys, ss, params.tt.(ss))
                sys = start_test_Q3(sys, id, ss, params);
                rem = sys.shift_end - sys.total_time;
            end
        end
    end
end
end

function ok = can_start_Q3(sys, s)
% 工位空闲、非待更换、未被阻塞（更换完成后才可用）、寿命未已到240h
ok = ~sys.stn.(s).occupied && ~sys.stn.(s).pending_replace ...
     && sys.total_time >= sys.stn.(s).blocked_until ...
     && (sys.stn.(s).life_used < sys.H240);
end

function ok = can_finish_life_Q3(sys, s, tt)
ok = (sys.H240 - sys.stn.(s).life_used) >= tt;
end

function id = pick_next_waiting_Q3(D)
id = 0;
for i=1:numel(D)
    if strcmp(D(i).status,'waiting')
        id = i; return;
    end
end
end

function sys = start_test_Q3(sys, id, s, params)
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
    ev = make_event_Q3('test_complete', sys.total_time + t_hit, id, s);
else
    ev = make_event_Q3('equip_failure', sys.total_time + t_hit, id, s);
end
sys = push_event_Q3(sys, ev);
end


%% ======================================================================
%%                           班 末 处 理（Q3）
%% ======================================================================
function sys = end_of_shift_Q3(sys, keep_timeline)
    % 守卫：正常不应有在测工位；若有则截断为 'shift-cut'
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

    % 推进到边界时刻
    sys.total_time = sys.shift_end;

    % 连续无间隙切到下一班：直接用固定班长推进
    sys.shift_end = sys.total_time + sys.shift_length;
end

%% ======================================================================
%%                           事 件 队 列
%% ======================================================================
function [sys, ev] = pop_event_if_within_shift_Q3(sys)
ev = [];
if isempty(sys.EQ), return; end
nxt = sys.EQ(1);
if nxt.time <= sys.shift_end
    ev = nxt; sys.EQ(1) = [];
    % 推进时间
    dt = ev.time - sys.total_time;
    sys.total_time = ev.time; %#ok<NASGU>  % 此处不需要 shift_time 概念
end
end

function tf = has_event_within_shift(sys)
if isempty(sys.EQ)
    tf = false;
else
    tf = sys.EQ(1).time <= sys.shift_end;
end
end

function sys = push_event_Q3(sys, ev)
if isempty(sys.EQ)
    sys.EQ = ev; return;
end
t = [sys.EQ.time];
k = find(ev.time < t, 1, 'first');
if isempty(k), sys.EQ(end+1) = ev;
else,          sys.EQ = [sys.EQ(1:k-1), ev, sys.EQ(k:end)];
end
end

function ev = make_event_Q3(type, time, dev, st)
ev.type = type; ev.time = round(time); ev.dev = dev; ev.st = st;
end


%% ======================================================================
%%                             bench 工具
%% ======================================================================
function sys = release_bench_Q3(sys, id, t_out)
for b=1:2
    if sys.benches(b).device_id == id
        sys.benches(b).occupied       = false;
        sys.benches(b).device_id      = 0;
        sys.benches(b).available_time = max(sys.benches(b).available_time, sys.total_time) + t_out; % 可跨班
        return;
    end
end
end


%% ======================================================================
%%                           指 标 采 集
%% ======================================================================
function sim = collect_metrics_Q3(D, sys, params)
sim = struct();
sim.T_minutes = sys.total_time;
sim.N         = numel(D);

pass_idx = strcmp({D.status}, 'passed');
fail_idx = strcmp({D.status}, 'failed');
n_passed = sum(pass_idx);
n_failed = sum(fail_idx);

sim.n_passed = n_passed;
sim.n_failed = n_failed;

% 供微平均使用的总量
sim.P = n_failed;      % 预测 FAIL = TP + FP
sim.F = n_passed;      % 预测 PASS = TN + FN

% 四格表（以最终 PASS=阴性，FAIL=阳性）
bad       = [D.bad];
pred_fail = fail_idx; 
pred_pass = pass_idx;

sim.TP = sum( bad  & pred_fail );
sim.FP = sum(~bad  & pred_fail );
sim.TN = sum(~bad  & pred_pass );
sim.FN = sum( bad  & pred_pass );

% 单次（宏平均参考）FOR/FDR
if n_passed>0
    sim.PL_cond = sim.FN / (sim.FN + sim.TN);   % FOR
else
    sim.PL_cond = 0;
end
if n_failed>0
    sim.PW_cond = sim.FP / (sim.FP + sim.TP);   % FDR
else
    sim.PW_cond = 0;
end

% 有效工时比（每班归一：总班次数 × Kmin）
% 通过 shift_end 与 total_time 推不出 Kmin，需从 sys.shift_length 取
Kmin = sys.shift_length;
total_shifts = max(1, ceil(sim.T_minutes / Kmin));
sim.YXB = zeros(1,4);
for i=1:4
    s = params.stations{i};
    sim.YXB(i) = sys.stn.(s).work_time / (total_shifts * Kmin);
end

end


%% ======================================================================
%%                      统 计 汇 总（Micro + Wilson）
%% ======================================================================
function [S, Tdist] = summarize_stats_Q3(T_days, S_pass, PL_macro, PW_macro, YXB_mat, agg)
S = struct();

% per-run（宏平均仅作参考）
S.T_mean   = mean(T_days); S.T_std   = std(T_days);
S.S_mean   = mean(S_pass); S.S_std   = std(S_pass);
S.PL_macro_mean = mean(PL_macro);  S.PL_macro_std = std(PL_macro);
S.PW_macro_mean = mean(PW_macro);  S.PW_macro_std = std(PW_macro);
S.YXB_mean = mean(YXB_mat,1); S.YXB_std = std(YXB_mat,0,1);

% 微平均（稳健）：四格总数
TP=agg.TP; FP=agg.FP; TN=agg.TN; FN=agg.FN;
P = agg.P; F = agg.F; N = agg.N;

% 总体能力（基于真值）：FPR/FNR
[S.FPR, S.FPR_lo, S.FPR_hi] = wilson_ci_Q3(FP, FP+TN);
[S.FNR, S.FNR_lo, S.FNR_hi] = wilson_ci_Q3(FN, FN+TP);

% 结果口径（运营）
[S.FDR, S.FDR_lo, S.FDR_hi] = wilson_ci_Q3(FP, FP+TP);
[S.FOR, S.FOR_lo, S.FOR_hi] = wilson_ci_Q3(FN, FN+TN);

% 无条件（per device）
[S.PL_uncond, S.PL_uncond_lo, S.PL_uncond_hi] = wilson_ci_Q3(FN, N);
[S.PW_uncond, S.PW_uncond_lo, S.PW_uncond_hi] = wilson_ci_Q3(FP, N);

Tdist = T_days;
end

function [p, lo, hi] = wilson_ci_Q3(k, n)
if n<=0, p=0; lo=0; hi=0; return; end
z = 1.96;
phat = k/n;
den  = 1 + z^2/n;
center = (phat + z^2/(2*n)) / den;
half   = (z/den) * sqrt( (phat*(1-phat)/n) + (z^2/(4*n^2)) );
p  = phat;
lo = max(0, center - half);
hi = min(1, center + half);
end


%% ======================================================================
%%                          可 视 化：跨 K
%% ======================================================================
function visualize_across_K(Res, params)
figure('Position',[60,60,1400,520],'Color','w');

% T(K) 均值 ± std
subplot(1,2,1); hold on; box on; grid on;
errorbar(Res.K, Res.T_mean, Res.T_std, '-o', 'LineWidth',1.4, 'MarkerFaceColor',[0.2 0.5 0.8]);
xlabel('班次长度 K（小时）'); ylabel('完工时间 T（天）');
title('T(K)：均值 ± Std','FontWeight','bold');

% FPR/FNR 随 K（能力）
subplot(1,2,2); hold on; box on; grid on;
vals = [Res.FPR Res.FNR];
plot(Res.K, vals(:,1), '-s', 'LineWidth',1.4, 'MarkerFaceColor',[0.7 0.3 0.3]);
plot(Res.K, vals(:,2), '-d', 'LineWidth',1.4, 'MarkerFaceColor',[0.3 0.7 0.3]);
legend({'FPR','FNR'}, 'Location','northwest');
xlabel('班次长度 K（小时）'); ylabel('比例');
title('总体能力（FPR/FNR）随 K','FontWeight','bold');

sgtitle('问题3：跨K对比（micro + Wilson）','FontWeight','bold');
end


%% ======================================================================
%%                   可 视 化：最佳 K 的细节
%% ======================================================================
function visualize_bestK_details(Res, best_idx, params)
figure('Position',[70,70,1400,860],'Color','w');

% T 分布（最佳K）
subplot(2,2,1); 
histogram(Res.T_all{best_idx}, 20, 'FaceColor',[0.3 0.6 0.9], 'EdgeColor','none'); grid on; box on;
xlabel('T（天）'); ylabel('频数');
title(sprintf('最佳K=%.1f 的 T 分布 (\\mu=%.3f, \\sigma=%.3f)', Res.K(best_idx), Res.T_mean(best_idx), Res.T_std(best_idx)),'FontWeight','bold');

% YXB（最佳K）
subplot(2,2,2); 
bar(Res.YXB_mean(best_idx,:), 'FaceColor',[0.8 0.4 0.4]); hold on;
errorbar(1:4, Res.YXB_mean(best_idx,:), Res.YXB_std(best_idx,:), 'k.', 'LineWidth',1.2);
set(gca,'XTick',1:4,'XTickLabel',params.stations);
ylabel('有效工时比（每班归一）'); grid on; box on;
title('YXB（最佳K）','FontWeight','bold');

% FDR/FOR（运营）条形 + Wilson CI
subplot(2,2,3); hold on; box on; grid on;
vals = [Res.FDR(best_idx) Res.FOR(best_idx)];
los  = [Res.FDR_lo(best_idx) Res.FOR_lo(best_idx)];
his  = [Res.FDR_hi(best_idx) Res.FOR_hi(best_idx)];
eb   = [vals-los; his-vals];
bar(vals, 0.6, 'FaceColor',[0.6 0.6 0.9]);
errorbar(1:2, vals, eb(1,:), eb(2,:), 'k.', 'LineWidth',1.2);
set(gca,'XTick',1:2,'XTickLabel',{'FDR','FOR'});
ylabel('比例'); title('结果口径（最佳K）','FontWeight','bold');

% FPR/FNR（能力）条形 + Wilson CI
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


%% ======================================================================
%%                       可 视 化：甘 特 图
%% ======================================================================
function visualize_gantt_Q3(timeline, T_end, params, Kmin)
if isempty(timeline), return; end

stations = params.stations;
cmap = containers.Map( ...
    {'test-pass','test-fail','test-cut','replace','shift-cut'}, ...
    {[0.2 0.7 0.3],[0.85 0.3 0.3],[0.95 0.7 0.2],[0.3 0.5 0.85],[0.7 0.7 0.7]});

figure('Position',[80,80,1400,500],'Color','w'); 
for si = 1:4
    s = stations{si};
    subplot(4,1,si); hold on; box on; grid on;

    segs = timeline(strcmp({timeline.station}, s));
    for k = 1:numel(segs)
        st = segs(k).start; ed = segs(k).finish;
        if ed<=st, continue; end
        yv= [0.25 0.25 0.75 0.75];
        if isKey(cmap, segs(k).label), c = cmap(segs(k).label); else, c=[0.5 0.5 0.5]; end
        patch([st ed ed st], yv, c, 'EdgeColor','none','FaceAlpha',0.95);
        if ed-st >= params.tt.(s)/2 && segs(k).device>0
            text(st + 5, 0.5, sprintf('#%d',segs(k).device), 'Color','w', 'FontSize',8, 'VerticalAlignment','middle');
        end
    end

    % 画出班次边界
    for t = 0:Kmin:T_end
        plot([t t], [0.2 0.8], ':', 'Color',[0.2 0.2 0.2], 'LineWidth',0.5);
    end

    xlim([0 T_end]); ylim([0 1]); yticks([]);
    title(sprintf('工位 %s 时间线', s),'FontWeight','bold');
    if si==4, xlabel('时间（分钟）'); end
end
sgtitle('单次运行甘特图（测试/故障/更换/换班）','FontWeight','bold');
end


%% ======================================================================
%%                               小 工 具
%% ======================================================================
function out = tern(cond, a, b)
if cond, out=a; else, out=b; end
end
