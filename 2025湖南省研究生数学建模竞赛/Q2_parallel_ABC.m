% Q2_parallel_ABC.m
% 题目二：大型装置测试任务的事件驱动仿真（A/B/C 并行，同装置可并发；分钟制）
% 关键特性：
% - 两个测试台（benches），四个工位（A,B,C,E）
% - 同一装置的 A/B/C 可在不同工位并行开展，E 需在 A/B/C 全通过后进行
% - 12h 班次（720 min），班末中断不得接续；启动门槛：剩余班时 >= 测试时长 + 缓冲
% - 运入/运出各 30 min；设备 setup：A=30, B=20, C=20, E=40 (分钟)
% - 测手差错：每工位 e_j，误判/漏判各占 50% -> α=β=e_j/2；A/B/C 用贝叶斯更新先验
% - 首故障阈值抽样：0-120h 段概率 r1，120-240h 段补充到 r2，超 240h 强制更换
% - "≥240h 必换"规则：若累计使用将跨越 240h，则禁止开工；运行中触达 240h 立即中断并更换
% - 统计：完成天数 T、通过数 S、漏判率 PL、误判率 PW、各工位有效工时比 YXB
%
% 作者：<your name>
% 日期：2025-08-31

function Q2_parallel_ABC
clc; clear; close all;

%% =================== 参数与配置 ===================
params = struct();

% 时间统一为"分钟"
params.tt = struct('A',150,'B',120,'C',150,'E',180);         % 测试时长
params.setup = struct('A',30,'B',20,'C',20,'E',40);           % 更换设备setup
params.t_in  = 30;                                            % 运入
params.t_out = 30;                                            % 运出
params.buffer_min = 30;                                       % 班末缓冲
params.shift_minutes = 12*60;                                 % 720 min

% 测手差错率 e_j（误判/漏判各一半）
params.e = struct('A',0.03,'B',0.04,'C',0.02,'E',0.02);
params.alpha = structfun(@(x)0.5*x, params.e, 'UniformOutput', false); % 漏判
params.beta  = structfun(@(x)0.5*x, params.e, 'UniformOutput', false); % 误判

% 先验真实问题概率（装置级，独立抽样）
params.p0 = struct('A',0.025,'B',0.030,'C',0.020,'D',0.001);

% 首故障阈值抽样（0-120h 段 r1，0-240h 段 r2），以"分钟"为单位实现
% 注意：这里 r1, r2 均为"累计概率"
params.fail_r1 = struct('A',0.03,'B',0.04,'C',0.02,'E',0.03);
params.fail_r2 = struct('A',0.05,'B',0.07,'C',0.06,'E',0.05);

% 并行策略（同装置 A/B/C 并行）
config = struct();
config.parallel_ABC     = true;
config.n_devices        = 100;
config.n_replications   = 1000;          % 可调
config.max_days         = 100;          % 保险上限
config.verbose_every    = 20;           % 打印进度
config.random_seed      = [];           % []=随机；否则设为固定种子（如 20250831）

if ~isempty(config.random_seed)
    rng(config.random_seed);
else
    rng('shuffle');
end

%% =================== 蒙特卡洛仿真 ===================
results = struct();
results.T   = zeros(config.n_replications,1);
results.S   = zeros(config.n_replications,1);
results.PL  = zeros(config.n_replications,1);
results.PW  = zeros(config.n_replications,1);
results.YXB = zeros(config.n_replications,4);

fprintf('开始仿真（%d 次重复）...\n', config.n_replications);
t0 = tic;
for rep = 1:config.n_replications
    if config.verbose_every>0 && mod(rep, config.verbose_every)==0
        fprintf('  -> 完成 %d/%d (%.1fs)\n', rep, config.n_replications, toc(t0));
    end
    sim = run_single_simulation(params, config);
    results.T(rep)      = sim.completion_days;
    results.S(rep)      = sim.n_passed;
    results.PL(rep)     = sim.miss_rate;
    results.PW(rep)     = sim.false_rate;
    results.YXB(rep,:)  = sim.efficiency;
end

stats = analyze_results(results);
display_results(stats);

% 可视化
visualize_results(results, stats);

% 保存
save('Q2_parallel_ABC_results.mat','results','stats','params','config');
fprintf('已保存结果到 Q2_parallel_ABC_results.mat\n');

end % main

%% =================== 单次仿真 ===================
function sim = run_single_simulation(params, config)
% 初始化装置与系统
devices = initialize_devices(config.n_devices, params);
sys     = initialize_system(params);

% 起算点：两台装置已到位（不计初次运入/setup）
initial_benches = min(2, numel(devices));
for b = 1:initial_benches
    sys.benches(b).occupied  = true;
    sys.benches(b).device_id = b;
    devices(b).status        = 'testing';         % 就绪可调度
    devices(b).location      = sprintf('bench_%d', b);
end

% 主时间推进：按班次循环，班内按事件推进
while sys.n_completed < numel(devices) && sys.current_day <= config.max_days
    sys.shift_time = 0;  % 本班已用分钟
    while sys.shift_time < params.shift_minutes

        % 弹出"班内可发生"的最近事件（若不存在则可能直接到班末）
        [sys, ev] = pop_event_if_within_shift(sys, params);

        % 处理事件
        if ~isempty(ev)
            [sys, devices] = process_event(sys, devices, ev, params);
        end

        % 强制更换到点后解除（replacement_complete 事件会做）
        % ——调度：给在台装置分配 A/B/C/E；给空台安排下一台（考虑运出/运入）
        [sys, devices] = schedule(sys, devices, params);

        % 若本轮未弹出事件，且下一事件在班后或不存在，则结束本班（快进）
        if isempty(ev)
            next_t = peek_next_event_time(sys);
            latest = sys.total_time + (params.shift_minutes - sys.shift_time);
            if isempty(next_t) || next_t > latest
                sys.shift_time = params.shift_minutes;
            end
        end
    end

    % 班末：中断不得接续——对正在执行的测试按已过时间计入工时与寿命，并清零进行状态
    [sys, devices] = end_of_shift_cleanup(sys, devices);

    sys.current_day = sys.current_day + 1;
end

% 采集指标
sim = collect_metrics(devices, sys, params);

end

%% =================== 初始化：装置、系统 ===================
function devices = initialize_devices(n, params)
devices = struct([]);
for i = n:-1:1
    devices(i).id = i;

    % 真实缺陷（独立伯努利）
    devices(i).true = struct();
    devices(i).true.A = rand() < params.p0.A;
    devices(i).true.B = rand() < params.p0.B;
    devices(i).true.C = rand() < params.p0.C;
    devices(i).true.D = rand() < params.p0.D;
    devices(i).has_any_problem = devices(i).true.A || devices(i).true.B || devices(i).true.C || devices(i).true.D;

    % 单项测试结果/尝试
    devices(i).test_passed   = struct('A',false,'B',false,'C',false,'E',false);
    devices(i).test_attempts = struct('A',0,'B',0,'C',0,'E',0);

    % 先验信念（A/B/C 用）
    devices(i).prob = params.p0;  % A/B/C/D（E不回灌）

    % 运行状态
    devices(i).status   = 'waiting';
    devices(i).location = 'queue';
end
end

function sys = initialize_system(params)
sys.current_day = 1;
sys.shift_time  = 0;         % 班内已用分钟
sys.total_time  = 0;         % 全局绝对时间（分钟）
sys.n_completed = 0;

% 两个测试台
sys.benches = struct('occupied',{false,false},'device_id',{0,0},'available_time',{0,0});

% 四个工位
stations = {'A','B','C','E'};
for i = 1:numel(stations)
    s = stations{i};
    sys.stations.(s).occupied        = false;
    sys.stations.(s).device_id       = 0;
    sys.stations.(s).test_start_time = 0;
    sys.stations.(s).work_time       = 0;          % 有效工作分钟（用于YXB）
    sys.stations.(s).life_used       = 0;          % 累计使用分钟
    sys.stations.(s).blocked_until   = 0;          % 更换设备的setup结束时刻
    sys.stations.(s).pending_replace = false;      % 是否处于更换流程中
    sys.stations.(s).L_first_fail    = sample_failure_usage(params, s); % 首故障里程（分钟）
end

% 事件队列（按 time 升序）
sys.event_queue = struct('type',{},'time',{},'device_id',{},'station',{});
end

%% =================== 故障阈值抽样（分钟） ===================
function L = sample_failure_usage(params, s)
% 返回"本轮设备"发生首个故障的累计使用里程阈值 L（分钟）
% - 以 r1 概率落在 [0, 120h] 均匀；以 (r2-r1) 落在 (120h,240h] 均匀；否则 +Inf
r1 = params.fail_r1.(s);
r2 = params.fail_r2.(s);
u  = rand();

if u < r1
    L = randi([0, 120*60]);                    % 包含0，允许开机即退
elseif u < r2
    L = 120*60 + randi([1, 120*60]);           % (120h, 240h]
else
    L = inf;                                   % 240h 内不会故障
end
end

%% =================== 事件处理 ===================
function [sys, devices] = process_event(sys, devices, ev, params)
switch ev.type
    case 'transport_complete'
        % 运入结束，装置可被调度
        devices(ev.device_id).status = 'testing';

    case 'test_complete'
        [sys, devices] = on_test_complete(sys, devices, ev, params);

    case 'equipment_failure'
        [sys, devices] = on_equipment_failure(sys, devices, ev, params);

    case 'replacement_complete'
        s = ev.station;
        % 更换完成，重置设备寿命与阈值，解除阻塞
        sys.stations.(s).blocked_until   = 0;
        sys.stations.(s).pending_replace = false;
        sys.stations.(s).life_used       = 0;
        sys.stations.(s).L_first_fail    = sample_failure_usage(params, s);
end
end

function [sys, devices] = on_test_complete(sys, devices, ev, params)
id = ev.device_id; s = ev.station;

% 判定真实状态
if s=='E'
    has_problem = devices(id).has_any_problem;
else
    has_problem = devices(id).true.(s);
end

% 生成测手判定（α=漏判，β=误判）
alpha = params.alpha.(s);
beta  = params.beta.(s);
if has_problem
    pass = rand() < alpha;              % 漏判通过
else
    pass = rand() >= beta;              % 正确通过（1-β）
end

% 贝叶斯更新（仅 A/B/C）
if s~='E'
    p = devices(id).prob.(s);
    if pass
        p = (p*alpha) / (p*alpha + (1-p)*(1-beta));
    else
        p = (p*(1-alpha)) / (p*(1-alpha) + (1-p)*beta);
    end
    devices(id).prob.(s) = p;
end

% 尝试数 +1；通过或累积两次失败 -> 结束该工序
devices(id).test_attempts.(s) = devices(id).test_attempts.(s) + 1;
if pass
    devices(id).test_passed.(s) = true;
    if s=='E'
        devices(id).status = 'passed';
        sys.n_completed = sys.n_completed + 1;
        % 释放测试台：安排运出时间
        sys = release_bench_with_checkout(sys, id, params.t_out);
    end
else
    if devices(id).test_attempts.(s) >= 2
        % 连续两次未通过 -> 装置失败，流程结束
        devices(id).status = 'failed';
        sys.n_completed = sys.n_completed + 1;
        sys = release_bench_with_checkout(sys, id, params.t_out);
    end
end

% 释放工位；统计有效工时与寿命
tt = params.tt.(s);
sys.stations.(s).occupied        = false;
sys.stations.(s).device_id       = 0;
sys.stations.(s).work_time       = sys.stations.(s).work_time + tt;
sys.stations.(s).life_used       = sys.stations.(s).life_used + tt;

% 若刚好撞到 240h 上限（life_used==14400），立即进入强制更换流程
if sys.stations.(s).life_used >= 240*60 && ~sys.stations.(s).pending_replace
    sys = start_replacement_now(sys, s, params.setup.(s));
end

end

function [sys, devices] = on_equipment_failure(sys, devices, ev, params)
% 设备故障或"强制更换"触发的统一处理：中断当前测试（不计尝试），安排更换
s  = ev.station;
id = sys.stations.(s).device_id;           % 可能为 0（理论上不应出现）

% 已消耗的本次测试时间（到故障时刻）
elapsed = sys.total_time - sys.stations.(s).test_start_time;
elapsed = max(0, round(elapsed));          % 整数分钟

% 记入有效工时与寿命
sys.stations.(s).work_time = sys.stations.(s).work_time + elapsed;
sys.stations.(s).life_used = sys.stations.(s).life_used + elapsed;

% 释放工位，清除本次测试状态（不增加尝试数）
sys.stations.(s).occupied        = false;
sys.stations.(s).device_id       = 0;
sys.stations.(s).test_start_time = 0;

% 安排"更换完成"事件，阻塞该工位至完成
sys = start_replacement_now(sys, s, params.setup.(s));
end

function sys = start_replacement_now(sys, s, setup_min)
sys.stations.(s).blocked_until   = sys.total_time + setup_min;
sys.stations.(s).pending_replace = true;

% 推入"replacement_complete"事件（让时间能推进到这个点）
ev = make_event('replacement_complete', sys.stations.(s).blocked_until, 0, s);
sys = push_event(sys, ev);
end

%% =============== 调度（A/B/C 并行 + 近E优先 + 门槛检查） ===============
function [sys, devices] = schedule(sys, devices, params)

% 1) 给空台安排下一台（按队列顺序；考虑 bench.available_time 和运入 30 分钟）
for b = 1:2
    if ~sys.benches(b).occupied
        id = pick_next_waiting_device(devices);
        if id > 0
            sys.benches(b).occupied  = true;
            sys.benches(b).device_id = id;
            devices(id).status       = 'arriving';
            devices(id).location     = sprintf('bench_%d', b);

            t_arrive = max(sys.benches(b).available_time, sys.total_time) + 30; % 运入
            sys = push_event(sys, make_event('transport_complete', t_arrive, id, ''));
        end
    end
end

% 2) 在台可调度装置集合
cand = [];
for b = 1:2
    if sys.benches(b).occupied
        id = sys.benches(b).device_id;
        if strcmp(devices(id).status,'testing')
            cand(end+1) = id; %#ok<AGROW>
        end
    end
end
if isempty(cand), return; end

% 3) 给候选装置排序（越接近E优先，其次单位时间淘汰贡献）
scores = zeros(size(cand));
for k = 1:numel(cand)
    id = cand(k);
    passABC = double(devices(id).test_passed.A) + double(devices(id).test_passed.B) + double(devices(id).test_passed.C);

    % 单位时间淘汰贡献（基于当前信念 p）
    score_exit = 0;
    for s = ["A","B","C"]
        ss = char(s);
        if ~devices(id).test_passed.(ss) && devices(id).test_attempts.(ss)<2
            p     = devices(id).prob.(ss);
            alpha = params.alpha.(ss); beta = params.beta.(ss);
            Pexit = p*(1-alpha)^2 + (1-p)*beta^2;    % 两次"判问题"被淘汰
            score_exit = max(score_exit, Pexit / params.tt.(ss));
        end
    end
    scores(k) = 10*passABC + score_exit;  % 接近E的权重更大
end
[~, ord] = sort(scores, 'descend');
cand = cand(ord);

% 4) 尝试启动 A/B/C（并行），若全部通过则尽量启动 E
for k = 1:numel(cand)
    id = cand(k);

    % 4.1 A/B/C 并行尝试
    for s = ["A","B","C"]
        ss = char(s);
        if ~devices(id).test_passed.(ss) && devices(id).test_attempts.(ss)<2
            if can_start_station(sys, ss, params)
                tt = params.tt.(ss);
                if can_finish_this_shift(sys, params, tt) && has_enough_life(sys, ss, tt)
                    sys = start_test(sys, devices, id, ss, params);
                end
            end
        end
    end

    % 4.2 若 A/B/C 均已通过，启动 E
    if devices(id).test_passed.A && devices(id).test_passed.B && devices(id).test_passed.C ...
            && ~devices(id).test_passed.E && devices(id).test_attempts.E < 2
        if can_start_station(sys, 'E', params)
            ttE = params.tt.E;
            if can_finish_this_shift(sys, params, ttE) && has_enough_life(sys, 'E', ttE)
                sys = start_test(sys, devices, id, 'E', params);
            end
        end
    end
end

end

function ok = can_start_station(sys, s, params)
% 工位空闲、未被更换阻塞、且当前时间 >= blocked_until
ok = ~sys.stations.(s).occupied ...
     && ~sys.stations.(s).pending_replace ...
     && sys.total_time >= sys.stations.(s).blocked_until;
% 额外：若寿命已达或超 240h（理论上 pending_replace 已为真），也不应该开工
ok = ok && (sys.stations.(s).life_used < 240*60);
end

function ok = can_finish_this_shift(sys, params, tt)
% 班内窗口：剩余班时 >= 测试时长 + 缓冲
rem_shift = params.shift_minutes - sys.shift_time;
ok = (rem_shift >= tt + params.buffer_min);
end

function ok = has_enough_life(sys, s, tt)
% 240h 窗口：剩余寿命 >= 测试时长（禁止"注定腰斩"的无效开工）
rem_240 = 240*60 - sys.stations.(s).life_used;
ok = rem_240 >= tt;
end

function id = pick_next_waiting_device(devices)
id = 0;
for i = 1:numel(devices)
    if strcmp(devices(i).status,'waiting')
        id = i; return;
    end
end
end

%% =================== 启动测试：三路事件竞争 ===================
function sys = start_test(sys, devices, id, s, params)
% 标注工位占用
sys.stations.(s).occupied        = true;
sys.stations.(s).device_id       = id;
sys.stations.(s).test_start_time = sys.total_time;

% 三路"最先到达"的事件：测试完成 / 首故障阈值 / 240h 强制更换
tt       = params.tt.(s);
L        = sys.stations.(s).L_first_fail;
U        = sys.stations.(s).life_used;

if isfinite(L)
    to_fail = max(1, L - U);  % 距首故障剩余分钟，至少1
else
    to_fail = inf;
end
to_240  = max(1, 240*60 - U);                       % 距240上限剩余分钟，至少1
t_hit   = min([tt, to_fail, to_240]);

if t_hit == tt
    ev = make_event('test_complete', sys.total_time + t_hit, id, s);
else
    ev = make_event('equipment_failure', sys.total_time + t_hit, id, s);
end
sys = push_event(sys, ev);
end

%% =================== 班末清理（中断不得接续） ===================
function [sys, devices] = end_of_shift_cleanup(sys, devices)
% 对每个仍在执行的工位，计算已用时并计入寿命/工时，释放占用（不计尝试）
for s = ["A","B","C","E"]
    ss = char(s);
    if sys.stations.(ss).occupied
        id = sys.stations.(ss).device_id;
        elapsed = sys.total_time - sys.stations.(ss).test_start_time;
        elapsed = max(0, round(elapsed));

        sys.stations.(ss).work_time = sys.stations.(ss).work_time + elapsed;
        sys.stations.(ss).life_used = sys.stations.(ss).life_used + elapsed;

        sys.stations.(ss).occupied        = false;
        sys.stations.(ss).device_id       = 0;
        sys.stations.(ss).test_start_time = 0;

        % 班末不会触发更换（到240由运行时事件处理；若等于240，下次调度将禁止开工并触发replace）
        if sys.stations.(ss).life_used >= 240*60 && ~sys.stations.(ss).pending_replace
            sys = start_replacement_now(sys, ss, 0); % 班末可立即进入更换队列（setup 计入下一事件推进）
        end
    end
end
end

%% =================== bench 释放与运出 ===================
function sys = release_bench_with_checkout(sys, id, t_out)
for b = 1:2
    if sys.benches(b).device_id == id
        sys.benches(b).occupied      = false;
        sys.benches(b).device_id     = 0;
        sys.benches(b).available_time = max(sys.benches(b).available_time, sys.total_time) + t_out;
        break;
    end
end
end

%% =================== 事件队列工具 ===================
function [sys, ev] = pop_event_if_within_shift(sys, params)
ev = [];
if isempty(sys.event_queue), return; end
nxt = sys.event_queue(1);
latest = sys.total_time + (params.shift_minutes - sys.shift_time);
if nxt.time <= latest
    ev = nxt; sys.event_queue(1) = [];
    dt = ev.time - sys.total_time;
    sys.shift_time = sys.shift_time + dt;
    sys.total_time = ev.time;
end
end

function t = peek_next_event_time(sys)
if isempty(sys.event_queue), t = []; else, t = sys.event_queue(1).time; end
end

function sys = push_event(sys, ev)
if isempty(sys.event_queue)
    sys.event_queue = ev; return;
end
t = [sys.event_queue.time];
k = find(ev.time < t, 1, 'first');
if isempty(k)
    sys.event_queue(end+1) = ev;
else
    sys.event_queue = [sys.event_queue(1:k-1) ev sys.event_queue(k:end)];
end
end

function ev = make_event(type, time, id, s)
ev = struct('type',type,'time',round(time),'device_id',id,'station',s);
end

%% =================== 结果采集与统计 ===================
function sim = collect_metrics(devices, sys, params)
sim = struct();
sim.completion_days = sys.current_day - 1;   % 以"满天数"计
pass_idx = strcmp({devices.status}, 'passed');
fail_idx = strcmp({devices.status}, 'failed');

sim.n_passed = sum(pass_idx);

% 漏判率：通过集合中仍存在真实问题的比例
if any(pass_idx)
    n_missed = sum([devices(pass_idx).has_any_problem]);
    sim.miss_rate = n_missed / sum(pass_idx);
else
    sim.miss_rate = 0;
end

% 误判率：淘汰集合中其实无问题的比例
if any(fail_idx)
    n_false = sum(~[devices(fail_idx).has_any_problem]);
    sim.false_rate = n_false / sum(fail_idx);
else
    sim.false_rate = 0;
end

% 有效工时比 YXB（按总日历班时归一）
stations = {'A','B','C','E'};
total_hours = max(1, sim.completion_days) * (params.shift_minutes);
sim.efficiency = zeros(1,4);
for i=1:4
    sim.efficiency(i) = sys.stations.(stations{i}).work_time / total_hours;
end
end

function stats = analyze_results(results)
stats.T_mean   = mean(results.T);    stats.T_std   = std(results.T);
stats.S_mean   = mean(results.S);    stats.S_std   = std(results.S);
stats.PL_mean  = mean(results.PL);   stats.PL_std  = std(results.PL);
stats.PW_mean  = mean(results.PW);   stats.PW_std  = std(results.PW);
stats.YXB_mean = mean(results.YXB,1);
stats.YXB_std  = std(results.YXB,0,1);
end

function display_results(s)
fprintf('\n========== 仿真结果（并行A/B/C） ==========\n');
fprintf('完成天数   T: %.2f ± %.2f\n', s.T_mean, s.T_std);
fprintf('通过装置数 S: %.2f ± %.2f\n', s.S_mean, s.S_std);
fprintf('漏判率   P_L: %.4f ± %.4f\n', s.PL_mean, s.PL_std);
fprintf('误判率   P_W: %.4f ± %.4f\n', s.PW_mean, s.PW_std);
fprintf('有效工时比 YXB (A,B,C,E):\n');
fprintf('  A: %.3f ± %.3f\n', s.YXB_mean(1), s.YXB_std(1));
fprintf('  B: %.3f ± %.3f\n', s.YXB_mean(2), s.YXB_std(2));
fprintf('  C: %.3f ± %.3f\n', s.YXB_mean(3), s.YXB_std(3));
fprintf('  E: %.3f ± %.3f\n', s.YXB_mean(4), s.YXB_std(4));
fprintf('===========================================\n');
end

function visualize_results(results, stats)
figure('Position',[80,80,1200,780],'Color','w');

subplot(2,3,1);
histogram(results.T, 20);
xlabel('完成天数 T'); ylabel('频数');
title(sprintf('T分布 (\\mu=%.2f, \\sigma=%.2f)', stats.T_mean, stats.T_std));
grid on;

subplot(2,3,2);
histogram(results.S, 15);
xlabel('通过装置数 S'); ylabel('频数');
title(sprintf('S分布 (\\mu=%.1f, \\sigma=%.1f)', stats.S_mean, stats.S_std));
grid on;

subplot(2,3,3);
histogram(results.PL, 20);
xlabel('漏判率 P_L'); ylabel('频数');
title(sprintf('P_L分布 (\\mu=%.4f)', stats.PL_mean));
grid on;

subplot(2,3,4);
histogram(results.PW, 20);
xlabel('误判率 P_W'); ylabel('频数');
title(sprintf('P_W分布 (\\mu=%.4f)', stats.PW_mean));
grid on;

subplot(2,3,5);
bar(stats.YXB_mean); hold on;
errorbar(1:4, stats.YXB_mean, stats.YXB_std, 'k.', 'LineWidth',1);
set(gca,'XTick',1:4,'XTickLabel',{'A','B','C','E'});
xlabel('工位'); ylabel('有效工时比');
title('YXB（均值±标准差）'); grid on;

subplot(2,3,6);
plot(cumsum(results.T)./(1:length(results.T))','LineWidth',1.2);
xlabel('仿真次数'); ylabel('累积平均 T');
title('收敛性'); grid on;

sgtitle('问题2：A/B/C并行的分钟级事件驱动仿真', 'FontWeight','bold');
end
