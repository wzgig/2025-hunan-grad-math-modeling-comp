function results = simulate_problem2()
% 问题2：离散事件仿真（单班次，WIP<=2，A/B/C并行，E后置，任意中断重头）
% 目标：复现实验N次，输出期望 T、S、P_L、P_W、YXB，并生成图表
% 作者：awen-团队 / liuliu
rng(20250830);                 % 固定随机种子，保证可复现
cfg   = default_config();      % 题设参数
Nrep  = 1;                   % 蒙特卡洛重复次数（可按算力调大）
allT  = zeros(Nrep,1);
allS  = zeros(Nrep,1);
allPL = zeros(Nrep,1);
allPW = zeros(Nrep,1);
allYXB= zeros(Nrep,4);

for r = 1:Nrep
    out = run_one_rep(cfg);
    allT(r)   = out.T_days;
    allS(r)   = out.S_pass;
    allPL(r)  = out.P_L;
    allPW(r)  = out.P_W;
    allYXB(r,:)= out.YXB;
end

% 汇总统计
results.T_mean   = mean(allT);
results.S_mean   = mean(allS);
results.PL_mean  = mean(allPL);
results.PW_mean  = mean(allPW);
results.YXB_mean = mean(allYXB,1);
results.T_ci95   = quantile(allT,[0.025 0.975]);
results.PL_ci95  = quantile(allPL,[0.025 0.975]);
results.PW_ci95  = quantile(allPW,[0.025 0.975]);

disp('====== Monte Carlo Summary (Nrep) ======');
fprintf('Mean T (days): %.3f  (95%% CI [%.3f, %.3f])\n', results.T_mean, results.T_ci95(1), results.T_ci95(2));
fprintf('Mean S (pass): %.2f /100\n', results.S_mean);
fprintf('Mean P_L: %.4f  (95%% CI [%.4f, %.4f])\n', results.PL_mean, results.PL_ci95(1), results.PL_ci95(2));
fprintf('Mean P_W: %.4f  (95%% CI [%.4f, %.4f])\n', results.PW_mean, results.PW_ci95(1), results.PW_ci95(2));
fprintf('Mean YXB (A,B,C,E): [%.3f, %.3f, %.3f, %.3f]\n', results.YXB_mean);

% 图表：T直方图 & 工位利用率箱线图
figure('Name','Completion Days Histogram'); histogram(allT, 'BinMethod','sturges'); xlabel('T (days)'); ylabel('Count'); title('Distribution of Completion Days');
figure('Name','Station Utilization'); boxchart(categorical({'A','B','C','E'}), allYXB); ylabel('Utilization (per shift)'); title('Station Effective Time Ratio (YXB)');

end

% ========================= 配置与主仿真 =========================

function cfg = default_config()
% 题设参数（时间单位：小时）
cfg.numDevices = 100;      % 需要测试的装置数
cfg.shiftLen   = 12;       % 单班次长度（小时）
cfg.tIn        = 0.5;      % 运入
cfg.tOut       = 0.5;      % 运出
% 工位名称索引
cfg.J.A = 1; cfg.J.B = 2; cfg.J.C = 3; cfg.J.E = 4;
cfg.Jnames = {'A','B','C','E'};

% 标准测试时长
cfg.Ttest = zeros(1,4); 
cfg.Ttest(cfg.J.A) = 2.5;
cfg.Ttest(cfg.J.B) = 2.0;
cfg.Ttest(cfg.J.C) = 2.5;
cfg.Ttest(cfg.J.E) = 3.0;

% 初次/更换后校对时间（分钟转小时）
cfg.Tsetup = zeros(1,4);
cfg.Tsetup(cfg.J.A) = 30/60;
cfg.Tsetup(cfg.J.B) = 20/60;
cfg.Tsetup(cfg.J.C) = 20/60;
cfg.Tsetup(cfg.J.E) = 40/60;

% 本体缺陷概率（Y2） & 综合D
cfg.p_true = zeros(1,5); % A,B,C,E(不用),D
cfg.p_true(cfg.J.A) = 0.025;
cfg.p_true(cfg.J.B) = 0.030;
cfg.p_true(cfg.J.C) = 0.020;
cfg.p_true(5)       = 0.001;  % D

% 测手差错率（Y3）：一半误判，一半漏判——这里按"无条件固定概率"实现
cfg.err = zeros(1,4);
cfg.err(cfg.J.A) = 0.03;  % 3%
cfg.err(cfg.J.B) = 0.04;  % 4%
cfg.err(cfg.J.C) = 0.02;  % 2%
cfg.err(cfg.J.E) = 0.02;  % 2%

% 设备故障累计概率（Y1）：分段线性CDF（0~120h, 120~240h）
% 用 r1=段1累计、r2=段2累计；等可能发生 => 分段均匀风险，抽"阈值累计工时"
cfg.fail_r1 = [0.03, 0.04, 0.02, 0.03]; % A,B,C,E
cfg.fail_r2 = [0.05, 0.07, 0.06, 0.05]; % A,B,C,E
cfg.replace_at_120h = true;             % 班次开始若 L>=120h 则预防性更换
cfg.hard_replace_240h = true;           % L>=240h 强制更换

% 派工优先（Progress, Wait, SPT^-1）
cfg.prior_w = [3, 2, 1];

% 其它
cfg.verbose = false;       % 可切换调试输出
end

function out = run_one_rep(cfg)
% 运行单次仿真：返回指标
% ------------ 全局时间/班次 ------------
t_global = 0;              % 累计小时
dayCount = 0;              % 已完成天数
shiftLen = cfg.shiftLen;
t_shift_end = shiftLen;

% ------------ 设备与工位资源 ------------
WIP_max = 2;
tableSlot = struct('busy',false,'dev',0,'freeAt',0); % 两个测试台"安放位"
tableSlots = repmat(tableSlot,1,2);

% 工位状态
station = struct('busy',false,'dev',0,'J',0,'freeAt',0,...
    'L',0,'failTh',Inf,'down',false,'downFreeAt',0,'name','',...
    'effTime',0);
stations = repmat(station,1,4);
for j=1:4
    stations(j).J = j;
    stations(j).name = cfg.Jnames{j};
    % 初次启用：先做一次setup
    stations(j).down = true;
    stations(j).downFreeAt = cfg.Tsetup(j);
    stations(j).failTh = sample_fail_threshold(cfg, j); % 240h内的潜在故障阈值
end

% ------------ 生成100台装置的"真值" ------------
devs = init_devices(cfg);

% 统计量
doneCount = 0;       % 完成（通过或退出）数量
passCount = 0;       % 通过数量
final_leak = false(cfg.numDevices,1); % 带病通过（用于P_L分子）
final_wrong= false(cfg.numDevices,1); % 无病未过（用于P_W分子）

% 记录有效工作时间（测试占用时长，不含setup/搬运）
effTime_sum = zeros(1,4);
shiftCount = 0;

% ------------ 主循环 ------------
while doneCount < cfg.numDevices
    % 开班
    shiftCount = shiftCount + 1;
    t = 0;           % 班内时间（0~shiftLen）
    t_shift_end = shiftLen;
    dayCount = dayCount + (shiftCount>1 && mod(shiftCount-1,1)==0); %#ok<NASGU>
    
    % 班次开始：预防性更换（并行执行setup）
    for j=1:4
        if stations(j).down==false && cfg.replace_at_120h && stations(j).L >= 120
            stations(j).down = true;
            stations(j).downFreeAt = max(t, stations(j).freeAt) + cfg.Tsetup(j);
            stations(j).L = 0;
            stations(j).failTh = sample_fail_threshold(cfg,j);
        end
        % 若上一班未完成的setup，这里继续"占用到 downFreeAt"
    end

    % 尽可能把待测装置运入（WIP<=2；运入可与测试并行）
    [devs, tableSlots, in_events] = try_bringin(cfg, devs, tableSlots, t);
    % in_events 给出每个新入场装置的 t_avail = t + 0.5
    
    % 班内事件推进：我们用"小步迭代" + 计算最近事件时间（完成/故障/运入/运出/setup结束）
    while t < t_shift_end && doneCount < cfg.numDevices
        % 1) 释放完成的setup
        for j=1:4
            if stations(j).down && stations(j).downFreeAt <= t
                stations(j).down = false;
                stations(j).freeAt = t;
            end
        end
        
        % 2) 若有空闲工位，按优先级派发 A/B/C/E
        %    注意：禁止启动会跨班的测试（t + Ttest(j) > t_shift_end）
        for j=1:4
            if ~stations(j).down && ~stations(j).busy && (t + cfg.Ttest(j) <= t_shift_end)
                cand = eligible_devices(cfg, devs, tableSlots, j, t);
                if ~isempty(cand)
                    di = select_by_priority(cfg, devs, cand, t);
                    % 启动测试：检查是否会在当前设备的故障阈值前失败
                    [willFail, tFail] = will_fail_this_run(cfg, stations(j), j);
                    dur = cfg.Ttest(j);
                    if willFail && (t + tFail < t + dur) && (t + tFail <= t_shift_end)
                        % 计划在t+tFail发生故障 => 此次测试将被中断作废
                        stations(j).busy = true; stations(j).dev = di;
                        stations(j).freeAt = t + tFail; % 故障发生时间
                        stations(j).event = "fail";
                    else
                        % 正常完成
                        stations(j).busy = true; stations(j).dev = di;
                        stations(j).freeAt = t + dur;
                        stations(j).event = "done";
                    end
                end
            end
        end
        
        % 3) 找到系统的"下一事件时间"
        t_next = t_shift_end;
        % 工位事件（完成/故障）
        for j=1:4
            if stations(j).busy
                t_next = min(t_next, stations(j).freeAt);
            elseif stations(j).down
                t_next = min(t_next, stations(j).downFreeAt);
            end
        end
        % 运入/运出完成（不会阻塞工位，但影响"可派工"资格）
        for k=1:2
            if tableSlots(k).busy && tableSlots(k).freeAt > t
                t_next = min(t_next, tableSlots(k).freeAt);
            end
        end
        
        if t_next <= t + 1e-9
            t_next = min(t_shift_end, t + 1e-4); % 防止停滞
        end
        
        % 4) 推进到 t_next，并在推进段内累计"有效测试时间"
        dt = t_next - t;
        for j=1:4
            if stations(j).busy && stations(j).event ~= "idle"
                % 有效测试占用（不含setup/搬运）
                workable = min(dt, max(0, stations(j).freeAt - t));
                effTime_sum(j) = effTime_sum(j) + workable;
                stations(j).L = stations(j).L + workable; % 累计使用时长
            end
        end
        t = t_next;
        
        % 5) 处理到点事件
        % 5.1 工位事件
        for j=1:4
            if stations(j).busy && abs(stations(j).freeAt - t) < 1e-7
                di = stations(j).dev;
                if stations(j).event == "fail"
                    % 发生故障：作废当前测试（不计一次"未通过"），进入更换+setup
                    stations(j).busy = false; stations(j).dev = 0;
                    % 强制更换：立即开始setup（若跨班则下一班再做）
                    setup_dur = cfg.Tsetup(j);
                    if t + setup_dur <= t_shift_end
                        stations(j).down = true; stations(j).downFreeAt = t + setup_dur;
                    else
                        stations(j).down = true; stations(j).downFreeAt = t_shift_end + setup_dur; % 下一班继续
                    end
                    stations(j).L = 0;
                    stations(j).failTh = sample_fail_threshold(cfg, j);
                else
                    % 测试完成 => 判定通过/未通过
                    stations(j).busy = false; stations(j).dev = 0;
                    [devs, passed, failed] = judge_and_update(cfg, devs, di, j);
                    if failed
                        if devs(di).attempts(j) >= 2
                            % 该工位两次未过 => 装置退出
                            [devs, tableSlots] = finish_device(cfg, devs, tableSlots, di, false, t);
                            doneCount = doneCount + 1;
                            if devs(di).isHealthy % 无病却未过 => 误判
                                final_wrong(di) = true;
                            end
                        end
                    else
                        % 若E通过 => 该装置整体完成
                        if j==cfg.J.E && devs(di).E_passed
                            [devs, tableSlots] = finish_device(cfg, devs, tableSlots, di, true, t);
                            doneCount = doneCount + 1; passCount = passCount + 1;
                            if devs(di).thetaE_true
                                final_leak(di) = true; % 带病通过（漏判）
                            end
                        end
                    end
                end
            end
        end
        
        % 5.2 释放setup完成
        for j=1:4
            if stations(j).down && abs(stations(j).downFreeAt - t) < 1e-7
                stations(j).down = false;
                stations(j).freeAt = t;
            end
        end
        
        % 5.3 运入/运出完成
        for k=1:2
            if tableSlots(k).busy && abs(tableSlots(k).freeAt - t) < 1e-7
                tableSlots(k).busy = false;
                if tableSlots(k).dev>0 && devs(tableSlots(k).dev).inHall==false
                    % 运出完毕 => 彻底离场，释放台位
                    tableSlots(k).dev = 0;
                end
            end
        end
        
        % 6) 尝试继续运入新装置（若有空位且班内有0.5h剩余）
        [devs, tableSlots] = try_bringin(cfg, devs, tableSlots, t);
        
        % 7) 若某装置A/B/C都通过且未排E，尝试排E
        for di=find([devs.inHall] & ~[devs.completed])
            if all(devs(di).ABC_passed) && ~devs(di).E_enqueued
                devs(di).E_enqueued = true; % "资格已获得"，等待E工位按优先派工
            end
        end
    end % 班内循环
    
    % 班末：所有未完成的测试不会被"强停"（我们本就禁止跨班启动）
    % 下一班自动继续（含未完成setup）
end

% 汇总输出
out.T_days = ceil(t_global/24 + shiftCount*(cfg.shiftLen==24)); %#ok<NASGU> % 这里直接以班次数/12h折算
% 更准确地以班次数 => 天数
out.T_days = ceil(shiftCount * cfg.shiftLen / 24);
out.S_pass = passCount;
if passCount>0
    out.P_L = sum(final_leak)/passCount;
else
    out.P_L = 0;
end
if cfg.numDevices - passCount>0
    out.P_W = sum(final_wrong)/(cfg.numDevices - passCount);
else
    out.P_W = 0;
end
out.YXB = effTime_sum / (cfg.shiftLen * shiftCount); % 每班有效占比

end

% ========================= 设备/工位 辅助函数 =========================

function devs = init_devices(cfg)
% 初始化100台装置的真值、状态
N = cfg.numDevices;
devs = struct('id',0,'inHall',false,'table',0,'tAvail',0,'completed',false,...
    'theta',[0 0 0 0 0],... % A,B,C,E(不用),D
    'attempts',zeros(1,4),...
    'A_passed',false,'B_passed',false,'C_passed',false,'ABC_passed',false,...
    'E_enqueued',false,'E_passed',false,'thetaE_true',false,'isHealthy',true);
devs = repmat(devs,1,N);
for i=1:N
    devs(i).id = i;
    % 抽取本体真值（A/B/C/D）
    devs(i).theta(1) = rand < cfg.p_true(1);
    devs(i).theta(2) = rand < cfg.p_true(2);
    devs(i).theta(3) = rand < cfg.p_true(3);
    devs(i).theta(5) = rand < cfg.p_true(5); % D
    devs(i).isHealthy = ~(devs(i).theta(1) || devs(i).theta(2) || devs(i).theta(3) || devs(i).theta(5));
end
end

function [devs, tableSlots, in_events] = try_bringin(cfg, devs, tableSlots, t_now)
% 若有空位，尽量从"未进场"的装置队列中带入；运入耗时0.5h，可与其他并行
in_events = [];
for k=1:2
    if ~tableSlots(k).busy && tableSlots(k).dev==0
        % 找到下一个未进场且未完成的装置
        idx = find(~[devs.inHall] & ~[devs.completed], 1, 'first');
        if ~isempty(idx)
            di = idx;
            tableSlots(k).busy = true;
            tableSlots(k).dev  = di;
            tableSlots(k).freeAt= t_now + cfg.tIn; % 运入结束时刻
            devs(di).inHall = true;
            devs(di).table  = k;
            devs(di).tAvail = t_now + cfg.tIn;
            in_events = [in_events; [di, devs(di).tAvail]]; %#ok<AGROW>
        end
    end
end
end

function cand = eligible_devices(cfg, devs, tableSlots, j, t_now)
% 返回在工位 j 上"此刻可开工"的装置列表
% 条件：
% - 在场 & 已完成运入 (t_now >= tAvail)
% - 未完成整体
% - A/B/C：该工位尚未通过且尝试次数<2
% - E：A/B/C均通过，E未通过且尝试次数<2
inHall = [devs.inHall];
ready  = [devs.tAvail] <= t_now;
notDone= ~[devs.completed];
ids = find(inHall & ready & notDone);
cand = [];

for d = ids
    switch j
        case {cfg.J.A, cfg.J.B, cfg.J.C}
            if ~getfield(devs(d),[cfg.Jnames{j} '_passed']) && devs(d).attempts(j) < 2
                cand = [cand, d]; %#ok<AGROW>
            end
        case cfg.J.E
            if all([devs(d).A_passed, devs(d).B_passed, devs(d).C_passed]) ...
               && ~devs(d).E_passed && devs(d).attempts(j) < 2
                cand = [cand, d]; %#ok<AGROW>
            end
    end
end
end

function di = select_by_priority(cfg, devs, cand, t_now)
% 优先级：3*进度 + 2*等待 + 1*SPT^-1（当前工位时长相同=>此项常数，可忽略）
% 这里用：进度=已通过A/B/C个数/3；等待=在场后等待的相对时长
prog = zeros(1,length(cand));
wait = zeros(1,length(cand));
for k=1:length(cand)
    d = cand(k);
    prog(k) = (devs(d).A_passed + devs(d).B_passed + devs(d).C_passed)/3;
    wait(k) = max(0, t_now - devs(d).tAvail);
end
% 归一化（避免尺度影响）
if max(wait)>0, wait = wait / max(wait); end
score = cfg.prior_w(1)*prog + cfg.prior_w(2)*wait; % + w3*SPT^-1(常数)
[~,ix] = max(score);
di = cand(ix);
end

function [willFail, tFail] = will_fail_this_run(cfg, st, j)
% 给定工位j当前累计使用L与"下一个故障阈值failTh"，判断本次测试是否在阈值前触发
% st.failTh：距上次更换以来的"发生故障的累计工时"阈值（<=240h），>240表示本周期无故障
remain = st.failTh - st.L;
if remain <= 0
    willFail = true; tFail = max(1e-3, remain); % 立刻故障
else
    willFail = remain < cfg.Ttest(j);
    tFail    = remain;
end
end

function th = sample_fail_threshold(cfg, j)
% 从"分段线性CDF"抽故障累计工时阈值（若阈值>240 => 本周期不故障）
r1 = cfg.fail_r1(j); r2 = cfg.fail_r2(j);
U  = rand;
if U <= r1
    th = 120 * (U / r1);                    % 映射到[0,120]
elseif U <= r2
    th = 120 + 120 * ((U - r1)/(r2 - r1)); % 映射到(120,240]
else
    th = 1e9; % 本周期不故障（>240h）
end
end

function [devs, passed, failed] = judge_and_update(cfg, devs, di, j)
% 完成一次测试后的判定；返回是否通过/未通过；并更新装置状态与"E真值"
% 规则：若真有问题，默认"应当失败"；但若发生漏判（FN）则通过
%       若真无问题，默认"应当通过"；但若发生误判（FP）则失败
passed = false; failed = false;
devs(di).attempts(j) = devs(di).attempts(j) + 1;

% 对应工位的真/假
isTrue = false;
switch j
    case {1,2,3} % A/B/C
        isTrue = devs(di).theta(j)==1;
    case 4       % E 的真值由 "A/B/C残留 或 D"为真
        % 进入E时的残留：A/B/C若之前"通过"且其真值为1 => 说明是漏判残留
        resA = devs(di).A_passed && devs(di).theta(1)==1;
        resB = devs(di).B_passed && devs(di).theta(2)==1;
        resC = devs(di).C_passed && devs(di).theta(3)==1;
        isTrue = (resA || resB || resC || devs(di).theta(5));
        devs(di).thetaE_true = isTrue; % 记录"最终真值"用于PL
end

% 差错率：固定"一半误判，一半漏判"
err = cfg.err(j);
FN = 0.5 * err; % 漏判：有病却判通过
FP = 0.5 * err; % 误判：无病却判不通过

if isTrue
    % 默认失败；若漏判 => 通过
    if rand < FN
        passed = true; failed = false;
    else
        passed = false; failed = true;
    end
else
    % 默认通过；若误判 => 失败
    if rand < FP
        passed = false; failed = true;
    else
        passed = true; failed = false;
    end
end

% 更新装置通过状态（A/B/C/E）
if passed
    switch j
        case 1, devs(di).A_passed = true;
        case 2, devs(di).B_passed = true;
        case 3, devs(di).C_passed = true;
        case 4, devs(di).E_passed = true;
    end
end
devs(di).ABC_passed = devs(di).A_passed && devs(di).B_passed && devs(di).C_passed;

end

function [devs, tableSlots] = finish_device(cfg, devs, tableSlots, di, finalPass, t_now)
% 装置退场：安排运出0.5h（与其他并行）；释放时刻= t_now + 0.5
k = devs(di).table;
if k>0
    tableSlots(k).busy  = true;         % 运出
    tableSlots(k).freeAt= t_now + cfg.tOut;
end
devs(di).inHall = false;
devs(di).completed = true;
devs(di).table = 0;
end
