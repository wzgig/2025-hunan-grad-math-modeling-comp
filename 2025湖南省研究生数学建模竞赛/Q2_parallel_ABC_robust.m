% Q2_parallel_ABC_robust.m
% 问题二：大型装置测试任务仿真（分钟级、A/B/C 并行、首故障阈值、≥240h 强制更换）
% 统计与展示：FPR/FNR（总体），FDR/FOR（结果口径，micro-average + Wilson CI）
% 可视化：分布图、YXB柱图、收敛曲线、单次运行甘特图
%
% 作者：<your name>
% 日期：2025-08-31

function Q2_parallel_ABC_robust
clc; clear; close all;

%% =================== 参数与配置 ===================
params = struct();

% —— 时间单位 = 分钟 ——
params.tt     = struct('A',150,'B',120,'C',150,'E',180);   % 测试时长
params.setup  = struct('A',30,'B',20,'C',20,'E',40);       % 更换setup
params.t_in   = 30;                                        % 运入
params.t_out  = 30;                                        % 运出
params.buffer = 0;                                        % 班末缓冲
params.shift  = 12*60;                                     % 一班 720 min

% —— 测手差错（误判/漏判各占50%） ——
params.e     = struct('A',0.03,'B',0.04,'C',0.02,'E',0.02);
params.alpha = structfun(@(x)0.5*x, params.e, 'UniformOutput', false); % 漏判
params.beta  = structfun(@(x)0.5*x, params.e, 'UniformOutput', false); % 误判

% —— 先验真实问题概率（独立抽样） ——
params.p0 = struct('A',0.025,'B',0.030,'C',0.020,'D',0.001);

% —— 首故障阈值抽样：0–120h 累计 r1，0–240h 累计 r2 ——
params.fail_r1 = struct('A',0.03,'B',0.04,'C',0.02,'E',0.03);
params.fail_r2 = struct('A',0.05,'B',0.07,'C',0.06,'E',0.05);

% —— 仿真配置 ——
cfg = struct();
cfg.parallel_ABC     = true;     % 同装置 A/B/C 并行
cfg.n_devices        = 100;
cfg.n_replications   = 10000;      % 可调：更大更稳
cfg.max_days         = 100;
cfg.verbose_every    = 20;       % 进度打印频率
cfg.random_seed      = [];       % [] 随机；也可设 20250831 等固定种子
cfg.draw_gantt_from  = 1;        % 取第1次运行绘制甘特图

if ~isempty(cfg.random_seed), rng(cfg.random_seed); else, rng('shuffle'); end

%% =================== 结果容器（含"计数"用于micro-average） ===================
R = struct();
R.T        = zeros(cfg.n_replications,1);
R.S        = zeros(cfg.n_replications,1);
R.PL_macro = zeros(cfg.n_replications,1); % 旧口径（宏平均）FOR
R.PW_macro = zeros(cfg.n_replications,1); % 旧口径（宏平均）FDR
R.YXB      = zeros(cfg.n_replications,4);

% 微平均计数（跨rep 汇总）
agg = struct('TP',0,'FP',0,'TN',0,'FN',0,'P',0,'F',0,'N',0);

% 保存一次完整时间线用于甘特图
timeline_sample = [];

fprintf('开始仿真（%d 次）...\n', cfg.n_replications);
t0 = tic;

for rep = 1:cfg.n_replications
    if cfg.verbose_every>0 && mod(rep,cfg.verbose_every)==0
        fprintf('  -> 完成 %d/%d (%.1fs)\n', rep, cfg.n_replications, toc(t0));
    end

    sim = run_single_simulation(params, cfg, rep==cfg.draw_gantt_from);

    % —— per-run 输出（宏平均参考）——
    R.T(rep)        = sim.T_days;
    R.S(rep)        = sim.n_passed;
    R.PL_macro(rep) = sim.PL_cond;   % FOR = FN/(FN+TN)（条件于PASS）
    R.PW_macro(rep) = sim.PW_cond;   % FDR = FP/(FP+TP)（条件于FAIL）
    R.YXB(rep,:)    = sim.YXB;

    % —— 微平均汇总 ——（跨rep）
    agg.TP = agg.TP + sim.TP;
    agg.FP = agg.FP + sim.FP;
    agg.TN = agg.TN + sim.TN;
    agg.FN = agg.FN + sim.FN;
    agg.P  = agg.P  + sim.P;   % FAIL 总数 = TP+FP
    agg.F  = agg.F  + sim.F;   % PASS 总数 = TN+FN
    agg.N  = agg.N  + sim.N;   % 总样本

    if rep==cfg.draw_gantt_from
        timeline_sample = sim.timeline; % 保存甘特图数据
        T_end_sample    = sim.T_minutes;
    end
end

%% =================== 统计汇总（稳健：micro-average + Wilson区间） ===================
S = summarize_stats(R, agg);

%% =================== 打印结果 ===================
print_report(S);

%% =================== 可视化 ===================
visualize_distributions(R, S);
visualize_gantt(timeline_sample, T_end_sample, params);

% 保存
save('Q2_parallel_ABC_robust_results.mat','R','S','params','cfg','timeline_sample','T_end_sample');
fprintf('已保存到 Q2_parallel_ABC_robust_results.mat\n');

end % main


%% ======================================================================
%%                          单 次 仿 真
%% ======================================================================
function sim = run_single_simulation(params, cfg, keep_timeline)

% --- 初始化装置 ---
D = init_devices(cfg.n_devices, params);

% --- 初始化系统 ---
sys = init_system(params);

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

% —— 主循环：按"班次"推进，班内按事件推进 ——
while sys.n_done < numel(D) && sys.current_day <= cfg.max_days
    sys.shift_time = 0; % 班内已用分钟

    while sys.shift_time < params.shift
        % 取"班内可发生"的最早事件（若无则可能快进到班末）
        [sys, ev] = pop_event_if_within_shift(sys, params);

        % 处理事件
        if ~isempty(ev)
            [sys, D] = handle_event(sys, D, ev, params, keep_timeline);
        end

        % 调度：喂满 A/B/C/E；给空台分配等待装置（含运入）
        [sys, D] = schedule(sys, D, params);

        % 防止卡死：若没有事件且下一事件在班后/不存在 → 班末
        if isempty(ev)
            t_next = peek_next_event(sys);
            latest = sys.total_time + (params.shift - sys.shift_time);
            if isempty(t_next) || t_next > latest
                sys.shift_time = params.shift;
            end
        end
    end

    % 班末清理（中断不得接续）：计入寿命与工时，释放占用，记录"班末中断"
    [sys, D] = end_of_shift_cleanup(sys, D, params, keep_timeline);

    sys.current_day = sys.current_day + 1;
end

% —— 采集指标 ——（四格表 + 旧口径）
sim = collect_metrics(D, sys, params);

% 补充甘特数据/结束时间
if keep_timeline
    sim.timeline   = sys.timeline;
    sim.T_minutes  = sys.total_time;
else
    sim.timeline   = [];
    sim.T_minutes  = sys.total_time;
end

end


%% ======================================================================
%%                             初始化模块
%% ======================================================================
function D = init_devices(n, params)
D = struct([]);
for i=n:-1:1
    D(i).id = i;

    % 真实缺陷（独立伯努利）
    D(i).true.A = rand()<params.p0.A;
    D(i).true.B = rand()<params.p0.B;
    D(i).true.C = rand()<params.p0.C;
    D(i).true.D = rand()<params.p0.D;
    D(i).bad    = D(i).true.A || D(i).true.B || D(i).true.C || D(i).true.D;

    % 单项测试状态
    D(i).pass.A = false; D(i).pass.B = false; D(i).pass.C = false; D(i).pass.E = false;
    D(i).tries.A= 0;     D(i).tries.B= 0;     D(i).tries.C= 0;     D(i).tries.E= 0;

    % 信念（A/B/C 用于顺序评分；E 不回灌）
    D(i).prob = params.p0;

    % 流程状态
    D(i).status   = 'waiting'; % waiting/testing/arriving/passed/failed
    D(i).location = 'queue';
end
end

function sys = init_system(params)
sys.current_day = 1;
sys.shift_time  = 0;       % 班内已用分钟
sys.total_time  = 0;       % 全局分钟
sys.n_done      = 0;       % 已完成（pass 或 fail）的装置数

% 2 个测试台
sys.benches = struct('occupied',{false,false},'device_id',{0,0},'available_time',{0,0});

% 4 个工位
for s = ["A","B","C","E"]
    ss = char(s);
    sys.stn.(ss).occupied        = false;
    sys.stn.(ss).device_id       = 0;
    sys.stn.(ss).test_start_time = 0;
    sys.stn.(ss).work_time       = 0;      % 有效测试分钟（用于YXB）
    sys.stn.(ss).life_used       = 0;      % 累计寿命（分钟）
    sys.stn.(ss).blocked_until   = 0;      % 更换setup结束时刻
    sys.stn.(ss).pending_replace = false;  % 是否在更换中
    sys.stn.(ss).L_first_fail    = sample_first_failure(params, ss); % 首故障阈值（分钟）
end

% 事件队列（按 time 升序）
sys.EQ = struct('type',{},'time',{},'dev',{},'st',{});

% 可选时间线（甘特图）
sys.timeline = [];
end

%% 首故障阈值抽样（分钟）
% function L = sample_first_failure(params, s)
% r1 = params.fail_r1.(s);
% r2 = params.fail_r2.(s);
% u  = rand();
% if u < r1
%     L = randi([0,120*60]);                % [0, 120h]
% elseif u < r2
%     L = 120*60 + randi([1,120*60]);       % (120h, 240h]
% else
%     L = inf;                               % 240h 内不故障
% end
% end
function threshold = sample_first_failure(params, s)
    r1 = params.fail_r1.(s);  % 0-120h累积概率
    r2 = params.fail_r2.(s);  % 0-240h累积概率
    u = rand();
    
    if u < r1
        threshold = rand() * 120 * 60;              % 0-120h内均匀分布
    elseif u < r2
        threshold = 120*60 + rand() * 120 * 60;     % 120-240h内均匀分布
    else
        threshold = inf;                             % 240h内不故障
    end
end

%% ======================================================================
%%                             事件处理
%% ======================================================================
function [sys, D] = handle_event(sys, D, ev, params, keep_timeline)
switch ev.type
    case 'transport_done'
        D(ev.dev).status = 'testing';

    case 'test_complete'
        [sys, D] = on_test_complete(sys, D, ev.st, ev.dev, params, keep_timeline);

    case 'equip_failure' % 含自然故障与240h强制更换（统一处理）
        [sys, D] = on_equip_failure(sys, D, ev.st, params, keep_timeline);

    case 'replace_complete'
        s = ev.st;
        sys.stn.(s).blocked_until   = 0;
        sys.stn.(s).pending_replace = false;
        sys.stn.(s).life_used       = 0;
        sys.stn.(s).L_first_fail    = sample_first_failure(params, s);
end
end

function [sys, D] = on_test_complete(sys, D, s, id, params, keep_timeline)
% 真实状态
if s=='E'
    has_problem = D(id).bad;
else
    has_problem = D(id).true.(s);
end

% 判定：α=漏判、β=误判
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

% 记录本段测试（甘特）
if keep_timeline
    seg.station = s; seg.start = sys.stn.(s).test_start_time; seg.finish = sys.total_time;
    seg.device  = id; seg.label = tern(pass,'test-pass','test-fail');
    sys.timeline(end+1) = seg; %#ok<AGROW>
end

% 尝试数 +1；通过或"两次失败"结束该工序
D(id).tries.(s) = D(id).tries.(s) + 1;
if pass
    D(id).pass.(s) = true;
    if s=='E'
        D(id).status = 'passed';
        sys.n_done = sys.n_done + 1;
        sys = release_bench(sys, id, params.t_out);
    end
else
    if D(id).tries.(s) >= 2
        D(id).status = 'failed';
        sys.n_done = sys.n_done + 1;
        sys = release_bench(sys, id, params.t_out);
    end
end

% 释放工位；计入工时与寿命
tt = params.tt.(s);
sys.stn.(s).occupied        = false;
sys.stn.(s).device_id       = 0;
sys.stn.(s).work_time       = sys.stn.(s).work_time + tt;
sys.stn.(s).life_used       = sys.stn.(s).life_used + tt;

% 若寿命到达/超过240h，立即进入强制更换流程（与故障同逻辑）
if sys.stn.(s).life_used >= 240*60 && ~sys.stn.(s).pending_replace
    sys = start_replacement(sys, s, params.setup.(s), keep_timeline);
end
end

function [sys, D] = on_equip_failure(sys, D, s, params, keep_timeline)
% 故障/强制更换：中断当前测试（不计尝试），记录已用时间
id = sys.stn.(s).device_id;
elapsed = sys.total_time - sys.stn.(s).test_start_time;
elapsed = max(0, round(elapsed));
sys.stn.(s).work_time = sys.stn.(s).work_time + elapsed;
sys.stn.(s).life_used = sys.stn.(s).life_used + elapsed;

% 甘特：记录中断段 + 更换段
if keep_timeline
    seg1.station = s; seg1.start = sys.stn.(s).test_start_time; seg1.finish = sys.total_time;
    seg1.device  = id; seg1.label = 'test-cut';
    sys.timeline(end+1) = seg1; %#ok<AGROW>
end

% 释放工位
sys.stn.(s).occupied        = false;
sys.stn.(s).device_id       = 0;
sys.stn.(s).test_start_time = 0;

% 进入更换流程（阻塞工位，推送"完成"事件）
sys = start_replacement(sys, s, params.setup.(s), keep_timeline);
end

function sys = start_replacement(sys, s, setup_min, keep_timeline)
sys.stn.(s).blocked_until   = sys.total_time + setup_min;
sys.stn.(s).pending_replace = true;

% 甘特：更换段
if keep_timeline
    seg.station = s; seg.start = sys.total_time; seg.finish = sys.stn.(s).blocked_until;
    seg.device  = 0; seg.label = 'replace';
    sys.timeline(end+1) = seg; %#ok<AGROW>
end

% 推入"replace_complete"
ev = make_event('replace_complete', sys.stn.(s).blocked_until, 0, s);
sys = push_event(sys, ev);
end


%% ======================================================================
%%                                调 度
%% ======================================================================
function [sys, D] = schedule(sys, D, params)

% —— 给空台安排下一台（FIFO） ——
for b=1:2
    if ~sys.benches(b).occupied
        id = pick_next_waiting(D);
        if id>0
            sys.benches(b).occupied  = true;
            sys.benches(b).device_id = id;
            D(id).status = 'arriving';
            D(id).location = sprintf('bench_%d', b);
            t_arrive = max(sys.benches(b).available_time, sys.total_time) + params.t_in;
            sys = push_event(sys, make_event('transport_done', t_arrive, id, ''));
        end
    end
end

% —— 可调度集合（在台且testing） ——
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

% —— 排序：越接近E越优先，其次单位时间淘汰贡献 —— 
score = zeros(size(cand));
for k=1:numel(cand)
    id = cand(k);
    passABC = double(D(id).pass.A) + double(D(id).pass.B) + double(D(id).pass.C);
    score_exit = 0;
    for s = ["A","B","C"]
        ss = char(s);
        if ~D(id).pass.(ss) && D(id).tries.(ss)<2
            p     = D(id).prob.(ss);
            alpha = params.alpha.(ss); beta = params.beta.(ss);
            Pexit = p*(1-alpha)^2 + (1-p)*beta^2; % 两次"判问题"淘汰概率
            score_exit = max(score_exit, Pexit / params.tt.(ss));
        end
    end
    score(k) = 10*passABC + score_exit;
end
[~,ord] = sort(score,'descend');
cand = cand(ord);

% —— 尝试启动 A/B/C 并行；若都通过则启动 E ——
for k=1:numel(cand)
    id = cand(k);

    % A/B/C 并行尝试
    for s = ["A","B","C"]
        ss = char(s);
        if ~D(id).pass.(ss) && D(id).tries.(ss)<2
            if can_start(sys, ss) && can_finish_shift(sys, params, params.tt.(ss)) ...
                                  && has_enough_life(sys, ss, params.tt.(ss))
                sys = start_test(sys, id, ss, params);
            end
        end
    end

    % E
    if D(id).pass.A && D(id).pass.B && D(id).pass.C && ~D(id).pass.E && D(id).tries.E<2
        if can_start(sys,'E') && can_finish_shift(sys, params, params.tt.E) ...
                              && has_enough_life(sys,'E', params.tt.E)
            sys = start_test(sys, id, 'E', params);
        end
    end
end
end

function ok = can_start(sys, s)
ok = ~sys.stn.(s).occupied && ~sys.stn.(s).pending_replace ...
     && sys.total_time >= sys.stn.(s).blocked_until ...
     && (sys.stn.(s).life_used < 240*60);
end

function ok = can_finish_shift(sys, params, tt)
ok = (params.shift - sys.shift_time) >= (tt + params.buffer);
end

function ok = has_enough_life(sys, s, tt)
ok = (240*60 - sys.stn.(s).life_used) >= tt;
end

function id = pick_next_waiting(D)
id = 0;
for i=1:numel(D)
    if strcmp(D(i).status,'waiting')
        id = i; return;
    end
end
end

%% 启动测试：三路事件竞争（完成 / 首故障 / 240h）
function sys = start_test(sys, id, s, params)
sys.stn.(s).occupied        = true;
sys.stn.(s).device_id       = id;
sys.stn.(s).test_start_time = sys.total_time;

tt = params.tt.(s);
L  = sys.stn.(s).L_first_fail;
U  = sys.stn.(s).life_used;

% 距首故障/240h 的剩余分钟（至少1，避免0长事件）
if isfinite(L)
    to_fail = max(1, L - U);
else
    to_fail = inf;
end
to240  = max(1, 240*60 - U);
t_hit  = min([tt, to_fail, to240]);

if t_hit == tt
    ev = make_event('test_complete', sys.total_time + t_hit, id, s);
else
    ev = make_event('equip_failure', sys.total_time + t_hit, id, s);
end
sys = push_event(sys, ev);
end


%% ======================================================================
%%                           班 末 清 理
%% ======================================================================
function [sys, D] = end_of_shift_cleanup(sys, D, params, keep_timeline)
for s = ["A","B","C","E"]
    ss = char(s);
    if sys.stn.(ss).occupied
        id = sys.stn.(ss).device_id;
        elapsed = sys.total_time - sys.stn.(ss).test_start_time;
        elapsed = max(0, round(elapsed));

        % 记录"班末中断"
        if keep_timeline
            seg.station = ss; seg.start = sys.stn.(ss).test_start_time; seg.finish = sys.total_time;
            seg.device  = id; seg.label = 'shift-cut';
            sys.timeline(end+1) = seg; %#ok<AGROW>
        end

        sys.stn.(ss).work_time = sys.stn.(ss).work_time + elapsed;
        sys.stn.(ss).life_used = sys.stn.(ss).life_used + elapsed;

        sys.stn.(ss).occupied        = false;
        sys.stn.(ss).device_id       = 0;
        sys.stn.(ss).test_start_time = 0;

        % 下班后若已到 240h，下一时刻会触发更换阻塞
        if sys.stn.(ss).life_used >= 240*60 && ~sys.stn.(ss).pending_replace
            % 立即进入更换队列（setup 时间将在下一事件推进）
            sys = start_replacement(sys, ss, 0, keep_timeline);
        end
    end
end
end


%% ======================================================================
%%                             bench 工具
%% ======================================================================
function sys = release_bench(sys, id, t_out)
for b=1:2
    if sys.benches(b).device_id == id
        sys.benches(b).occupied       = false;
        sys.benches(b).device_id      = 0;
        sys.benches(b).available_time = max(sys.benches(b).available_time, sys.total_time) + t_out;
        return;
    end
end
end


%% ======================================================================
%%                           事 件 队 列
%% ======================================================================
function [sys, ev] = pop_event_if_within_shift(sys, params)
ev = [];
if isempty(sys.EQ), return; end
nxt = sys.EQ(1);
latest = sys.total_time + (params.shift - sys.shift_time);
if nxt.time <= latest
    ev = nxt; sys.EQ(1) = [];
    dt = ev.time - sys.total_time;
    sys.shift_time = sys.shift_time + dt;
    sys.total_time = ev.time;
end
end

function t = peek_next_event(sys)
if isempty(sys.EQ), t=[]; else, t = sys.EQ(1).time; end
end

function sys = push_event(sys, ev)
if isempty(sys.EQ)
    sys.EQ = ev; return;
end
t = [sys.EQ.time];
k = find(ev.time < t, 1, 'first');
if isempty(k), sys.EQ(end+1) = ev;
else,          sys.EQ = [sys.EQ(1:k-1), ev, sys.EQ(k:end)];
end
end

function ev = make_event(type, time, dev, st)
ev.type = type; ev.time = round(time); ev.dev = dev; ev.st = st;
end


%% ======================================================================
%%                           指 标 采 集
%% ======================================================================
function sim = collect_metrics(D, sys, params)
% 收集模拟过程中的关键指标，返回包含统计信息的结构体
% 输入:
%   D - 样本数据结构体数组，包含status和bad字段
%   sys - 系统信息结构体，包含时间、工位等信息
%   params - 参数结构体，包含班次时长等配置
% 输出:
%   sim - 包含各类统计指标的结构体

sim = struct();

%% 1. 基础时间与样本量统计
sim.T_minutes = sys.total_time;       % 总时长(分钟)
sim.T_days    = sys.current_day - 1;  % 完成天数
sim.N         = numel(D);             % 总样本量

%% 2. 判定结果计数（PASS/FAIL）
pass_idx = strcmp({D.status}, 'passed');  % PASS判定索引
fail_idx = strcmp({D.status}, 'failed');  % FAIL判定索引

sim.n_passed = sum(pass_idx);  % PASS判定总数
sim.n_failed = sum(fail_idx);  % FAIL判定总数

% 预测标签总量（用于微平均统计）
sim.P = sim.n_failed;  % 预测为FAIL的总数 = TP + FP
sim.F = sim.n_passed;  % 预测为PASS的总数 = TN + FN

%% 3. 四格表统计（基于真值与预测结果）
% 真值定义：bad=true为异常，bad=false为正常
% 预测定义：FAIL为阳性，PASS为阴性
bad = [D.bad];                   % 真值数组（逻辑型）
pred_fail = fail_idx;            % 预测为FAIL的逻辑数组
pred_pass = pass_idx;            % 预测为PASS的逻辑数组

sim.TP = sum( bad  & pred_fail );  % 真阳性：异常且预测为FAIL
sim.FP = sum(~bad  & pred_fail );  % 假阳性：正常但预测为FAIL
sim.TN = sum(~bad  & pred_pass );  % 真阴性：正常且预测为PASS
sim.FN = sum( bad  & pred_pass );  % 假阴性：异常但预测为PASS

%% 4. 条件概率指标（宏平均参考）
% FOR（假漏判率）：判定为PASS中实际异常的比例
if sim.n_passed > 0
    sim.PL_cond = sim.FN / (sim.FN + sim.TN);  % FOR = FN/(FN+TN)
else
    sim.PL_cond = 0;  % 无PASS判定时置0
end

% FDR（假发现率）：判定为FAIL中实际正常的比例
if sim.n_failed > 0
    sim.PW_cond = sim.FP / (sim.FP + sim.TP);  % FDR = FP/(FP+TP)
else
    sim.PW_cond = 0;  % 无FAIL判定时置0
end

%% 5. 有效工时比（各工位工作时间占比）
stations = {'A', 'B', 'C', 'E'};               % 工位列表
total_mins = max(1, sim.T_days) * params.shift;  % 总日历班时（避免除零）
sim.YXB = zeros(1, length(stations));           % 初始化有效工时比数组

for i = 1:length(stations)
    % 有效工时比 = 工位工作时间 / 总日历班时
    sim.YXB(i) = sys.stn.(stations{i}).work_time / total_mins;
end

%% 6. 时间线数据
sim.timeline = sys.timeline;

end
%% ======================================================================
%%                      统 计 汇 总（Micro + Wilson）
%% ======================================================================
function S = summarize_stats(R, agg)
S = struct();

% —— per-run（宏平均，仅作参考）——
S.T_mean   = mean(R.T);           S.T_std   = std(R.T);
S.S_mean   = mean(R.S);           S.S_std   = std(R.S);
S.PL_macro_mean = mean(R.PL_macro);  S.PL_macro_std = std(R.PL_macro);
S.PW_macro_mean = mean(R.PW_macro);  S.PW_macro_std = std(R.PW_macro);
S.YXB_mean = mean(R.YXB,1);       S.YXB_std = std(R.YXB,0,1);

% —— 微平均（稳健）：四格总数 ——
TP=agg.TP; FP=agg.FP; TN=agg.TN; FN=agg.FN;
P = agg.P; F = agg.F; N = agg.N;

% 总体指标（基于真值）：FPR/FNR
S.FPR_k = FP; S.FPR_n = FP+TN;  [S.FPR, S.FPR_lo, S.FPR_hi] = wilson_ci(FP, FP+TN);
S.FNR_k = FN; S.FNR_n = FN+TP;  [S.FNR, S.FNR_lo, S.FNR_hi] = wilson_ci(FN, FN+TP);

% 结果口径（FDR/FOR）
S.FDR_k = FP; S.FDR_n = FP+TP;  [S.FDR, S.FDR_lo, S.FDR_hi] = wilson_ci(FP, FP+TP);
S.FOR_k = FN; S.FOR_n = FN+TN;  [S.FOR, S.FOR_lo, S.FOR_hi] = wilson_ci(FN, FN+TN);

% 无条件（per device）
S.PL_uncond_k = FN; S.PL_uncond_n = N; [S.PL_uncond, S.PL_uncond_lo, S.PL_uncond_hi] = wilson_ci(FN, N);
S.PW_uncond_k = FP; S.PW_uncond_n = N; [S.PW_uncond, S.PW_uncond_lo, S.PW_uncond_hi] = wilson_ci(FP, N);

% 每万台换算
S.per10k = struct();
S.per10k.PL = 1e4 * S.PL_uncond;
S.per10k.PW = 1e4 * S.PW_uncond;

end

% Wilson 区间（95%）
function [p, lo, hi] = wilson_ci(k, n)
if n<=0
    p=0; lo=0; hi=0; return;
end
z = 1.96;
phat = k/n;
den = 1 + z^2/n;
center = (phat + z^2/(2*n)) / den;
half   = (z/den) * sqrt( (phat*(1-phat)/n) + (z^2/(4*n^2)) );
p  = phat;
lo = max(0, center - half);
hi = min(1, center + half);
end


%% ======================================================================
%%                          打 印 报 告
%% ======================================================================
function print_report(S)
fprintf('\n================= 稳健统计汇总（micro + Wilson） =================\n');
fprintf('完成天数 T: %.2f ± %.2f\n', S.T_mean, S.T_std);
fprintf('通过数   S: %.2f ± %.2f\n', S.S_mean, S.S_std);

% 总体（基于真值）
fprintf('\n[总体能力]（基于真值）\n');
fprintf('FPR = FP/(FP+TN) = %.6f  (95%%CI: %.6f~%.6f)\n', S.FPR, S.FPR_lo, S.FPR_hi);
fprintf('FNR = FN/(FN+TP) = %.6f  (95%%CI: %.6f~%.6f)\n', S.FNR, S.FNR_lo, S.FNR_hi);

% 结果口径（当前产出）
fprintf('\n[结果产出]（与当前运营更相关）\n');
fprintf('FDR = FP/(FP+TP) = %.6f  (95%%CI: %.6f~%.6f)\n', S.FDR, S.FDR_lo, S.FDR_hi);
fprintf('FOR = FN/(FN+TN) = %.6f  (95%%CI: %.6f~%.6f)\n', S.FOR, S.FOR_lo, S.FOR_hi);

% 无条件（工程直观）
fprintf('\n[无条件发生率]（per device）\n');
fprintf('漏判 P_L = FN/N = %.6f  (95%%CI: %.6f~%.6f)   ≈ 每万台 %.2f\n', ...
    S.PL_uncond, S.PL_uncond_lo, S.PL_uncond_hi, S.per10k.PL);
fprintf('误判 P_W = FP/N = %.6f  (95%%CI: %.6f~%.6f)   ≈ 每万台 %.2f\n', ...
    S.PW_uncond, S.PW_uncond_lo, S.PW_uncond_hi, S.per10k.PW);

% 旧口径（宏平均，参考）
fprintf('\n[宏平均参考]（单次比值的均值±STD；不稳健，仅作对照）\n');
fprintf('FOR(宏)= %.6f ± %.6f   FDR(宏)= %.6f ± %.6f\n', ...
    S.PL_macro_mean, S.PL_macro_std, S.PW_macro_mean, S.PW_macro_std);

% YXB
fprintf('\n有效工时比 YXB (A,B,C,E):\n');
fprintf('  均值:  [%.3f, %.3f, %.3f, %.3f]\n', S.YXB_mean(1), S.YXB_mean(2), S.YXB_mean(3), S.YXB_mean(4));
fprintf('  Std :  [%.3f, %.3f, %.3f, %.3f]\n', S.YXB_std(1),  S.YXB_std(2),  S.YXB_std(3),  S.YXB_std(4));
fprintf('=====================================================================\n');
end


%% ======================================================================
%%                          可 视 化 组 件
%% ======================================================================
function visualize_distributions(R, S)
figure('Position',[60,60,1400,820],'Color','w');

% T 分布
subplot(2,3,1);
histogram(R.T, 20,'FaceColor',[0.3 0.5 0.8],'EdgeColor','none'); grid on;
xlabel('完成天数 T'); ylabel('频数');
title(sprintf('T分布 (\\mu=%.2f, \\sigma=%.2f)', S.T_mean, S.T_std),'FontWeight','bold');

% S 分布
subplot(2,3,2);
histogram(R.S, 15,'FaceColor',[0.4 0.7 0.5],'EdgeColor','none'); grid on;
xlabel('通过装置数 S'); ylabel('频数');
title(sprintf('S分布 (\\mu=%.1f, \\sigma=%.1f)', S.S_mean, S.S_std),'FontWeight','bold');

% 宏平均 FOR/FDR（仅参考）
subplot(2,3,3);
hold on; box on; grid on;
bar([mean(R.PL_macro) mean(R.PW_macro)], 0.6);
errorbar(1:2, [mean(R.PL_macro) mean(R.PW_macro)], ...
         [std(R.PL_macro) std(R.PW_macro)], 'k.', 'LineWidth',1.2);
set(gca,'XTick',1:2,'XTickLabel',{'FOR(宏)','FDR(宏)'});
ylabel('比例'); title('旧口径（宏平均）','FontWeight','bold');

% 微平均（Wilson）能力与产出
subplot(2,3,4);
vals = [S.FPR S.FNR S.FDR S.FOR];
los  = [S.FPR_lo S.FNR_lo S.FDR_lo S.FOR_lo];
his  = [S.FPR_hi S.FNR_hi S.FDR_hi S.FOR_hi];
eb   = [vals-los; his-vals];
bar(vals, 'FaceColor',[0.5 0.5 0.9]); hold on; grid on; box on;
errorbar(1:4, vals, eb(1,:), eb(2,:), 'k.', 'LineWidth',1.2);
set(gca,'XTick',1:4,'XTickLabel',{'FPR','FNR','FDR','FOR'});
ylabel('比例'); title('稳健估计（micro + Wilson95%CI）','FontWeight','bold');

% YXB
subplot(2,3,5);
bar(S.YXB_mean, 'FaceColor',[0.8 0.4 0.4]); hold on;
errorbar(1:4, S.YXB_mean, S.YXB_std, 'k.', 'LineWidth',1.2);
set(gca,'XTick',1:4,'XTickLabel',{'A','B','C','E'});
ylabel('有效工时比'); title('YXB（均值±STD）','FontWeight','bold'); grid on; box on;

% 收敛性
subplot(2,3,6);
plot(cumsum(R.T)./(1:length(R.T))','LineWidth',1.4); grid on; box on;
xlabel('仿真次数'); ylabel('累积均值'); title('T 的收敛性','FontWeight','bold');

sgtitle('问题2：稳健统计与分布图（A/B/C并行，分钟级）','FontWeight','bold');
end

function visualize_gantt(timeline, T_end, params)
if isempty(timeline), return; end

% 将时间段按工位分组，并赋色
stations = {'A','B','C','E'};
colormap_map = containers.Map( ...
    {'test-pass','test-fail','test-cut','replace','shift-cut'}, ...
    {[0.2 0.7 0.3],[0.85 0.3 0.3],[0.95 0.7 0.2],[0.3 0.5 0.85],[0.7 0.7 0.7]});

figure('Position',[80,80,1400,420],'Color','w'); 
tmin = 0; tmax = T_end;

for si = 1:4
    s = stations{si};
    subplot(4,1,si); hold on; box on; grid on;

    % 取该工位的所有片段
    segs = timeline(strcmp({timeline.station}, s));
    for k = 1:numel(segs)
        st = segs(k).start; ed = segs(k).finish;
        if ed<=st, continue; end
        y = 1;                    % 单条时间线
        x = [st ed ed st];
        yv= [0.25 0.25 0.75 0.75];
        if isKey(colormap_map, segs(k).label)
            c = colormap_map(segs(k).label);
        else
            c = [0.5 0.5 0.5];
        end
        patch(x, yv, c, 'EdgeColor','none','FaceAlpha',0.95);
        % 标注设备编号（可选：只在较长片段上标）
        if ed-st >= params.tt.(s)/2
            text(st + 5, 0.5, sprintf('#%d',segs(k).device), 'Color','w', 'FontSize',8, 'VerticalAlignment','middle');
        end
    end

    xlim([tmin tmax]);
    ylim([0 1]); yticks([]); 
    title(sprintf('工位 %s 的时间线', s),'FontWeight','bold');
    if si==4
        xlabel('时间（分钟）');
    end
end
sgtitle('单次运行甘特图（测试/故障/更换/班末中断）','FontWeight','bold');
end


%% ======================================================================
%%                         小 工 具
%% ======================================================================
function out = tern(cond, a, b)
% 轻量三元工具，便于写甘特标签
if cond, out=a; else, out=b; end
end
