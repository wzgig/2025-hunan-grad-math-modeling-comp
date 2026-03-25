# Monte Carlo Algorithm Flowchart Design

## Human
*2025-09-01T02:01:39.464535+00:00*
我现在要绘制蒙特卡洛的算法流程图，请你阅读代码，给我提供指导

## 附件:


```

#%%
# =========================
# 单元0：依赖与全局开关
# =========================
import numpy as np
import pandas as pd
import math
import random
from dataclasses import dataclass, asdict
import matplotlib.pyplot as plt
import seaborn as sns
from dataclasses import dataclass
import emf
import os
from pandas import ExcelWriter

np.random.seed(2025)      # 固定随机种子，便于复现
random.seed(2025)

# 时间粒度（单位：分钟）。题目用10分钟一个刻度，这里直接用min为单位更直观
DT = 10                    # 每步10分钟
SHIFT_MIN = 12*60          # 班长：12小时 = 720分钟
INOUT_MIN = 30             # 进/出各30分钟（计入在场容量，但不占用测试小组）
N_DEV = 100                # 装置总数

#%%
# =========================
# 单元1：工具函数
# =========================

def clip01(x: float) -> float:
    """把概率截断到[0,1]，防止极端参数溢出"""
    return 0.0 if x < 0 else (1.0 if x > 1 else x)

def pct(x: float) -> str:
    """把小数转成百分比字符串"""
    return f"{100*x:.2f}%"

def shift_window(t: int) -> tuple[int,int]:
    """给定时刻t（分钟），返回当前班次起止[min,max)"""
    s = (t // SHIFT_MIN)
    start = s*SHIFT_MIN
    end   = (s+1)*SHIFT_MIN
    return start, end

def fit_in_shift(t_start: int, duration: int) -> int:
    """
    不跨班策略：若 t_start+duration 超出当前班次，则移动到下一班次开头
    返回可开工的实际起点
    """
    start, end = shift_window(t_start)
    if t_start + duration <= end:
        return t_start
    else:
        return end  # 下一班次起始

def uniform_minutes(low_min: int, high_min: int) -> int:
    """均匀分布取整分钟"""
    return int(np.random.uniform(low_min, high_min))

def choice_weighted(keys, probs):
    """按权重选择元素"""
    return np.random.choice(keys, p=np.array(probs)/np.sum(probs))
def label_result(is_bad: bool, alarm: bool) -> tuple[str, str]:
    """
    返回 (结果, 正确性)
    结果: '通过' 或 '报警'
    正确性: 'TP(真坏报警)/FN(真坏误放)/FP(真好误报)/TN(真好放过)'
    """
    if alarm:
        return '报警', ('TP' if is_bad else 'FP')
    else:
        return '通过', ('FN' if is_bad else 'TN')


#%%
# =========================
# 单元2：质量核 + 滚动贝叶斯 + 反解各工位 FP/FN
# =========================

def clip01(x: float) -> float:
    return 0.0 if x < 0 else (1.0 if x > 1 else x)

def solve_fp_fn(p_true_bad: float, r_total: float) -> tuple[float, float]:
    """错样本对半：(1-p)FP = pFN = r/2"""
    half_r = 0.5 * r_total
    FP = half_r / max(1e-12, (1 - p_true_bad))
    FN = half_r / max(1e-12, p_true_bad)
    return clip01(FP), clip01(FN)

def pass_likelihood(fp: float, fn: float) -> tuple[float, float]:
    """两次机制下的“等效一次通过率”：真好=1-FP^2；真坏=FN*(2-FN)"""
    good_pass = 1 - fp**2
    bad_pass  = fn*(2 - fn)
    return clip01(good_pass), clip01(bad_pass)

def bayes_update_after_step(dist: dict, step: str, fp: float, fn: float) -> dict:
    """
    dist: {'H','A','B','C'} 到某工位前的真实成分
    step: 'A' or 'B' or 'C'
    返回：通过该工位后的真实成分（归一）
    """
    good_pass, bad_pass = pass_likelihood(fp, fn)
    num = {}
    for k in ['H','A','B','C']:
        if k == step:
            L = bad_pass   # 该步真坏
        else:
            L = good_pass  # 该步真好
        num[k] = dist[k]*L
    s = sum(num.values()) or 1.0
    return {k: num[k]/s for k in num}

# ——这里替换成你的题面参数（先验与总差错率）——
pA, pB, pC, pD = 0.025, 0.03, 0.02, 0.001
rA, rB, rC, rE = 0.03, 0.04, 0.02, 0.02

# 1) 反解 A/B/C 的 FP/FN（用到站前的先验pA,pB,pC）
FP_A, FN_A = solve_fp_fn(pA, rA)
FP_B, FN_B = solve_fp_fn(pB, rB)
FP_C, FN_C = solve_fp_fn(pC, rC)

# 2) 滚动贝叶斯：通过 A→B→C 后的真实成分（忽略双故障）
dist = {'H': 1 - (pA+pB+pC), 'A': pA, 'B': pB, 'C': pC}
dist = bayes_update_after_step(dist, 'A', FP_A, FN_A)
dist = bayes_update_after_step(dist, 'B', FP_B, FN_B)
dist = bayes_update_after_step(dist, 'C', FP_C, FN_C)

# 3) 到 E 时的“真坏总体比例” pE（A/B/C 通过后的坏 + 先验D）
pE = dist['A'] + dist['B'] + dist['C'] + pD

# 4) 反解 E 的 FP/FN（供仿真中区分真好/真坏使用）
FP_E, FN_E = solve_fp_fn(pE, rE)

# 打包，便于后续调用
FPFN = {'A': (FP_A, FN_A), 'B': (FP_B, FN_B), 'C': (FP_C, FN_C), 'E': (FP_E, FN_E)}


#%%
# =========================
# 单元3（更新）：本题需要的参数 + 校准/阈值
# =========================

# ——基础加工时长（分钟）——
TA, TB, TC, TE = 150, 120, 150, 180

# ——题面Y1：阶段累计故障概率（到120h、到240h）——
P120 = {'A':0.03, 'B':0.04, 'C':0.02, 'E':0.03}   # 0~120小时的累计概率
P240 = {'A':0.05, 'B':0.07, 'C':0.06, 'E':0.05}   # 0~240小时的累计概率
SEG_MIN = 120*60                                   # 阶段长度（分钟）

# ——第1问给出的先验/总差错率（到站前的真坏比例与总差错率）——
pA, pB, pC, pD = 0.025, 0.03, 0.02, 0.001
rA, rB, rC, rE = 0.03, 0.04, 0.02, 0.02

# ——用于抽“真实状态”的先验分布（忽略双故障）——
prior_states = ['H','A','B','C','D']
prior_probs  = [1-(pA+pB+pC+pD), pA, pB, pC, pD]

# ——新增：校准时间（更换后首次使用要加的时间，分钟）——
CAL_T = {'A': 30, 'B': 20, 'C': 20, 'E': 40}   # 自行按题设微调

# ——新增：更换策略阈值（累计使用时长，分钟）——
U_MIN = 120*60      # 120小时，可选的“预防性更换”阈值（是否启用看策略）
U_MAX = 240*60      # 240小时，强制更换阈值（达到必换）
USE_PREVENTIVE = False   # 先默认关闭预防性更换；需要时改 True

#%%
# =========================
# 单元3.1：按累计用时计算“一次尝试”的失败概率，并可抽样失败时刻
# =========================
def fail_prob_piecewise(group: str, used0_min: int, dur_min: int) -> tuple[float, int|None]:
    """
    输入：
      group      : 'A'/'B'/'C'/'E'
      used0_min  : 本组自上次更换以来的累计用时（分钟）
      dur_min    : 本次尝试的计划加工时长（分钟）
    输出：
      (p_fail, t_fail_sample)
      p_fail        : 本次尝试在 dur_min 内发生至少一次故障的概率
      t_fail_sample : 若发生故障，失败发生的相对时刻样本（均匀）；否则 None
    说明：
      - 0~120h 段的单位概率密度 = P120[group] / SEG_MIN
      - 120~240h 段的“增量累计概率” = (P240-P120)，其单位密度 = (P240-P120)/SEG_MIN
      - 若一次尝试跨段：把 dur 切成 d1+d2，p = 1 - (1-p1)*(1-p2)
      - “等可能” → 条件在某段失败，则该段内均匀抽取时刻
    """
    d1 = d2 = 0
    # 剩余在段1内的容量
    remain1 = max(0, SEG_MIN - used0_min)
    d1 = min(dur_min, remain1)
    d2 = dur_min - d1

    # 段1/段2的单位密度
    lam1 = P120[group] / SEG_MIN
    lam2 = max(P240[group] - P120[group], 0.0) / SEG_MIN

    p1 = lam1 * d1
    p2 = lam2 * d2
    p_fail = 1 - (1 - p1)*(1 - p2)

    # 随机给出一个失败时刻样本（供“记录日志”用）；不在这里抽也行，可在one_attempt里抽
    t_fail = None
    if np.random.rand() < p_fail:
        # 先判断落在哪段：按条件概率分配
        if d1 > 0 and d2 > 0:
            # 段1先试；若没中，再试段2
            if np.random.rand() < p1:
                t_fail = np.random.uniform(0, d1)
            else:
                t_fail = d1 + np.random.uniform(0, d2)
        elif d1 > 0:
            t_fail = np.random.uniform(0, d1)
        else:
            t_fail = np.random.uniform(0, d2)
    return float(p_fail), (int(t_fail) if t_fail is not None else None)

#%%
# =========================
# 单元4：
# =========================
@dataclass
class AttemptResult:
    used: int           # 本次尝试占用总时长（含故障后的调试）
    alarm: bool
    failed_mid: bool
    fail_at: int|None   # 故障发生时刻（相对本次尝试起点）
    debug: int|None     # 故障后的调试/复位耗时（分钟）

def one_attempt(duration_min: int,
                group: str,
                used0_min: int,
                fp: float, fn: float,
                is_bad: bool) -> AttemptResult:
    p_fail, t_fail = fail_prob_piecewise(group, used0_min, duration_min)
    if np.random.rand() < p_fail:
        tf  = int(t_fail if t_fail is not None else 0)
        dbg = CAL_T[group]          # 在单元3里设置：DEBUG_T = {'A':10,'B':10,'C':10,'E':15}
        return AttemptResult(used=tf + dbg, alarm=False, failed_mid=True,
                             fail_at=tf, debug=dbg)
    else:
        alarm_prob = (1 - fn) if is_bad else fp
        alarm = (np.random.rand() < alarm_prob)
        return AttemptResult(used=duration_min, alarm=alarm, failed_mid=False,
                             fail_at=None, debug=0)

#%%
# =========================
# 单元5：并行ABC（同台并行；任一两次失败→立刻早退）
# =========================
@dataclass
class ABCOutcome:
    finish_min: int
    passed_all: bool
    early_exit_step: str|None
    logs: list
    fails: list
    busy_by_group: dict  # 各组在本装置上的忙碌时长（分钟）
    finish_time_by_group: dict  # ★ 新增：{'A':绝对完成时刻, 'B':..., 'C':...}
# =========================
# 单元5（新增）：滚动/错峰 ABC（同台串行；任一两次报警→早退）
# =========================
@dataclass
class RollingABCOutcome:
    finish_min: int                     # 本台ABC总时长（相对 device_ready）
    passed_all: bool                    # 三步是否都通过
    logs: list                          # 与并行版一致：记录每段 start/end/attempt/result/ok
    fails: list                         # 故障段
    busy_by_group: dict                 # {'A':用时, 'B':..., 'C':...}
    finish_time_by_group: dict          # {'A':绝对完成时刻, ...}

def run_rolling_ABC(device_state: str,
                    used0_dict: dict[str, int],
                    device_ready: int,                 # 本台设备可开工时刻（= t_after_in）
                    team_ready_init: dict[str, int]    # {'A':ra,'B':rb,'C':rc}，已包含校准
                    ) -> RollingABCOutcome:
    # 真坏/真好、基准时长、误判率
    is_bad = {'A': device_state == 'A',
              'B': device_state == 'B',
              'C': device_state == 'C'}
    dur  = {'A': TA, 'B': TB, 'C': TC}
    fpfn = FPFN

    # 状态
    logs, fails = [], []
    busy   = {'A':0,'B':0,'C':0}
    used0  = used0_dict.copy()
    ready  = team_ready_init.copy()     # 每组自己的 ready（含校准后）
    d_i    = device_ready               # 设备就绪时间（同台串行）
    todo   = {'A','B','C'}
    alarm_cnt = {'A':0,'B':0,'C':0}

    while todo:
        # 1) 看谁能最早开始：S_g = fit_in_shift(max(ready[g], d_i), dur[g])
        cand = {g: fit_in_shift(max(ready[g], d_i), dur[g]) for g in todo}
        g_star = min(cand, key=cand.get)
        S = cand[g_star]

        # 2) 做一次尝试
        fp, fn = fpfn[g_star]
        ar = one_attempt(dur[g_star], g_star, used0[g_star], fp, fn, is_bad[g_star])

        # 故障段（中途失败）
        if ar.failed_mid:
            fail_s = S + (ar.fail_at or 0)
            fail_e = fail_s + (ar.debug or 0)
            fails.append(dict(step=g_star, fail_start=fail_s - device_ready, fail_end=fail_e - device_ready))

        F = S + ar.used
        busy[g_star]  += ar.used
        used0[g_star] += ar.used

        # 结果与正确性标签
        res, ok = label_result(is_bad[g_star], ar.alarm)
        # 这里的 attempt：1 或 2（若第一次报警、第二次再来）
        attempt_no = 1 + alarm_cnt[g_star]
        logs.append(dict(step=g_star, start=S - device_ready, end=F - device_ready,
                         attempt=attempt_no, result=res, ok=ok))

        # 3) 资源就绪更新
        ready[g_star] = F
        d_i = F

        if ar.alarm:
            alarm_cnt[g_star] += 1
            if alarm_cnt[g_star] >= 2:
                # 早退：直接返回（保持接口风格与并行版一致）
                return RollingABCOutcome(
                    finish_min=F - device_ready, passed_all=False,
                    logs=logs, fails=fails, busy_by_group=busy,
                    finish_time_by_group={'A': ready.get('A', device_ready),
                                          'B': ready.get('B', device_ready),
                                          'C': ready.get('C', device_ready)}
                )
            # 否则该组留在 todo 里（第二次再测）
        else:
            # 通过：把该组从 todo 移除
            todo.remove(g_star)

    # 三步都通过
    return RollingABCOutcome(
        finish_min=d_i - device_ready, passed_all=True,
        logs=logs, fails=fails, busy_by_group=busy,
        finish_time_by_group={'A': ready['A'], 'B': ready['B'], 'C': ready['C']}
    )

def run_parallel_ABC(device_state: str,
                     used0_dict: dict[str, int],
                     start_offset: dict[str,int]|None = None) -> ABCOutcome:

    # 该装置在ABC上的“真坏/真好”
    is_bad = {'A': device_state == 'A',
              'B': device_state == 'B',
              'C': device_state == 'C'}
    dur  = {'A': TA, 'B': TB, 'C': TC}
    fpfn = FPFN  # {'A':(FP_A,FN_A), ...}

    # 在函数开头加入一个计数器（放在 logs/fails 初始化附近）
    attempt_cnt = {'A':0,'B':0,'C':0}
    logs, fails = [], []
    busy       = {'A': 0, 'B': 0, 'C': 0}
    alarm_cnt  = {'A': 0, 'B': 0, 'C': 0}
    active     = {'A': True, 'B': True, 'C': True}
    inflight   = {}                # 当前进行中的“一次尝试”
    used0      = used0_dict.copy() # 三组的起始累计用时（分钟）
    if start_offset is None:
        start_offset = {'A':0,'B':0,'C':0}
    t_start = {g: int(start_offset.get(g, 0)) for g in ['A','B','C']}  # ★ 每组可不同
    t_now      = 0
    finish_time_by_group = {}   # ★ 新增：记录每组完成的相对时刻

    # 三条线同时开出第一轮尝试
    for g in ['A', 'B', 'C']:
        fp, fn = fpfn[g]
        inflight[g] = one_attempt(dur[g], g, used0[g], fp, fn, is_bad[g])

    while True:
        # === 真并行推进：谁先结束谁触发事件 ===
        finish_at = {g: t_start[g] + inflight[g].used for g in active if active[g]}
        g_star    = min(finish_at, key=finish_at.get)    # 最早结束者
        t_next    = finish_at[g_star]
        ar        = inflight[g_star]
        t_now     = t_next

        if ar.failed_mid:
            # 故障段 = [故障发生时刻, 故障发生时刻 + 调试时间]
            fail_s = t_start[g_star] + (ar.fail_at or 0)
            fail_e = fail_s + (ar.debug or 0)
            fails.append(dict(step=g_star, fail_start=fail_s, fail_end=fail_e))

            busy[g_star]  += (t_now - t_start[g_star])
            used0[g_star] += ar.used

            # 在该线重新开一次
            fp, fn = fpfn[g_star]
            t_start[g_star] = t_now
            inflight[g_star] = one_attempt(dur[g_star], g_star, used0[g_star], fp, fn, is_bad[g_star])

        else:
            # 完成本次质量尝试（本次尝试的加工段日志）
            attempt_cnt[g_star] += 1                      # 第几次质检（1或2）
            res, ok = label_result(is_bad[g_star], ar.alarm)

            logs.append(dict(
                step=g_star,
                start=t_start[g_star],
                end=t_now,
                attempt=attempt_cnt[g_star],              # ← 新：尝试序号
                result=res,                               # ← 新：结果（通过/报警）
                ok=ok                                     # ← 新：正确性（TP/FN/FP/TN）
            ))

            busy[g_star]  += (t_now - t_start[g_star])
            used0[g_star] += ar.used

            if ar.alarm:
                alarm_cnt[g_star] += 1
                if alarm_cnt[g_star] >= 2:
                    # 早退：把其它仍在跑的并行线补到 t_now（注意这些补齐行是“加工段”，没有三列）
                    for h in ['A','B','C']:
                        if h != g_star and active[h]:
                            busy[h] += (t_now - t_start[h])
                            logs.append(dict(step=h, start=t_start[h], end=t_now))
                    # 补齐完成时刻：三组都算成早退时刻
                    for h in ['A','B','C']:
                        finish_time_by_group.setdefault(h, t_now)

                    return ABCOutcome(finish_min=t_now, passed_all=False,
                                    early_exit_step=g_star, logs=logs, fails=fails,
                                    busy_by_group=busy, finish_time_by_group=finish_time_by_group)

                # 否则再开一次尝试（保持你原代码）
                fp, fn = fpfn[g_star]
                t_start[g_star] = t_now
                inflight[g_star] = one_attempt(dur[g_star], g_star, used0[g_star], fp, fn, is_bad[g_star])
            else:
                # 该步通过，停这条线（保持你原代码）
                finish_time_by_group[g_star] = t_now   # ★ 记录该组完成时刻
                active[g_star] = False
                inflight.pop(g_star)
                if not any(active.values()):
                    for h in ['A','B','C']:
                        finish_time_by_group.setdefault(h, t_now)

                    return ABCOutcome(finish_min=t_now, passed_all=True,
                                    early_exit_step=None, logs=logs, fails=fails,
                                    busy_by_group=busy, finish_time_by_group=finish_time_by_group)


# # ——单台调试：只跑ABC，看看日志长什么样——
# # 构造一个假的“真实状态”和三组的累计用时（都为0）
# _fake_state = 'H'   # 或 'A' / 'B' / 'C'
# _abc = run_parallel_ABC(_fake_state, used0_dict={'A':0,'B':0,'C':0})

# print("ABC 日志前5条：")
# for rec in _abc.logs[:5]:
#     print(rec)

# # 还可以快速数一下有多少条带了 result/attempt/ok
# print("含 result 的条数：", sum('result' in x for x in _abc.logs))
# print("含 attempt 的条数：", sum('attempt' in x for x in _abc.logs))
# print("含 ok 的条数：", sum('ok' in x for x in _abc.logs))


#%%
# =========================
# 单元6：E工序（一次→若报问题再二次；按真好/真坏选概率）
# =========================
@dataclass
class EOutcome:
    used_min: int
    passed: bool
    logs: list
    fails: list

def run_E(device_state: str, used0_E: int) -> EOutcome:
    is_bad_E = (device_state in ['A','B','C','D'])
    fp_e, fn_e = FPFN['E']
    logs, fails, used = [], [], 0
    used0 = used0_E

    def attempt_until_quality():
        nonlocal used, used0
        while True:
            ar = one_attempt(TE, 'E', used0, fp_e, fn_e, is_bad_E)
            used  += ar.used
            used0 += ar.used
            if ar.failed_mid:
                fails.append(dict(step='E', fail_start=used-ar.used, fail_end=used))
            else:
                return ar
            
    attempt_e = 0
    a1 = attempt_until_quality()
    attempt_e += 1
    res, ok = label_result(is_bad_E, a1.alarm)
    logs.append(dict(step='E', start=0, end=used,
                    attempt=attempt_e, result=res, ok=ok))
    if not a1.alarm:
        return EOutcome(used_min=used, passed=True, logs=logs, fails=fails)
    
    a2 = attempt_until_quality()
    attempt_e += 1
    res, ok = label_result(is_bad_E, a2.alarm)
    logs.append(dict(step='E', start=0, end=used,
                    attempt=attempt_e, result=res, ok=ok))
    return EOutcome(used_min=used, passed=(not a2.alarm), logs=logs, fails=fails)

# # ——单台调试：只跑E，看看日志长什么样——
# # 构造一个假的“真实状态”和E组累计用时（0）
# _e = run_E('H', used0_E=0)
# print("E 日志：", _e.logs[:3])
# print("E 含 result：", sum('result' in x for x in _e.logs))

#%%
# =========================
# 单元7：单台装置的完整时间轴（含两台在场&不跨班）
# =========================

@dataclass
class DeviceResult:
    device_id: int
    true_state: str            # H/A/B/C/D（用于计算PL/PW）
    passed: bool               # 是否最终通过
    t_in: int                  # 进场时刻
    t_abc_end: int             # ABC阶段结束（或早退）时刻
    t_e_end: int|None          # E结束时刻（若早退则None）
    t_out: int                 # 出场时刻
    schedule_rows: list        # 该装置的进度行（开始/结束）
    failure_rows: list         # 该装置的故障行

def simulate_one_device(device_id: int,
                        hall_slot_ready_min: int,
                        team_ready: dict[str,int],
                        team_used: dict[str,int],     # ← 新增：累计用时
                        team_used_sum: dict[str,int],   # ★ 新增
                        need_cal: dict[str,bool]      # ← 新增：是否待校准
                        ) -> tuple[DeviceResult, int,
                                   dict[str,int], dict[str,int], dict[str,bool]]:
    """
    返回：
      DeviceResult,
      更新后的 hall_slot_ready_min,
      更新后的 team_ready, team_used, need_cal
    """

    # 1) 随机抽取“真实状态”（仅用于统计PL/PW）
    true_state = choice_weighted(prior_states, prior_probs)

    # 2) 进场（不跨班；并受“在场名额ready”约束）
    t_in = fit_in_shift(max(hall_slot_ready_min, 0), INOUT_MIN)
    t_after_in = t_in + INOUT_MIN

    # ——小工具：检查是否需要更换→标记待校准，并返回“含校准”的可用时刻——
    def apply_replacement_and_ready(g: str, t_ready: int) -> int:
        # 强制更换：累计用时达到240h
        if team_used[g] >= U_MAX:
            team_used_sum[g] += team_used[g]   # ★ 先把上一段加到本轮累计
            team_used[g] = 0
            need_cal[g]  = True
        # 预防性更换（可选）：累计用时达到120h
        if USE_PREVENTIVE and team_used[g] >= U_MIN:
            team_used_sum[g] += team_used[g]   # ★ 先把上一段加到本轮累计
            team_used[g] = 0
            need_cal[g]  = True
        # 若待校准，则首次使用前把校准时间叠加到ready
        return t_ready + (CAL_T[g] if need_cal[g] else 0)

    # 3) ABC 同步起步：三组都要“就位”，并考虑是否待校准
    ra = apply_replacement_and_ready('A', team_ready['A'])
    rb = apply_replacement_and_ready('B', team_ready['B'])
    rc = apply_replacement_and_ready('C', team_ready['C'])
        # ★ 每个小组自己的不跨班起点（绝对时刻）
    SA = fit_in_shift(max(t_after_in, ra), TA)
    SB = fit_in_shift(max(t_after_in, rb), TB)
    SC = fit_in_shift(max(t_after_in, rc), TC)
    # ★ 取最早的起点作为基准，把其它起点转成偏移量
    t0_abc = min(SA, SB, SC)
    start_offset = {'A': SA - t0_abc, 'B': SB - t0_abc, 'C': SC - t0_abc}


    # 使用了“待校准”机会，标记已完成
    if need_cal['A']: need_cal['A'] = False
    if need_cal['B']: need_cal['B'] = False
    if need_cal['C']: need_cal['C'] = False

    # 4) 跑并行ABC（注意把三组的“起始累计用时”传入）
    abc = run_parallel_ABC(
        true_state,
        used0_dict={'A': team_used['A'], 'B': team_used['B'], 'C': team_used['C']},
        start_offset=start_offset         # ★ 每组独立起步
    )



    # 记录进度与故障（只在第一轮要输出全表）
    sched_rows, fail_rows = [], []
    for r in abc.logs:
        sched_rows.append(dict(
            device=device_id, team=r['step'],
            start=t0_abc + r['start'], end=t0_abc + r['end'],
            result=r.get('result'),         # ← 新：通过/报警
            attempt=r.get('attempt'),       # ← 新：第1/2次
            ok=r.get('ok')                  # ← 新：TP/FN/FP/TN
        ))
    for f in abc.fails:
        fail_rows.append(dict(device=device_id, team=f['step'],
                              fail_start=t0_abc + f['fail_start'],
                              fail_end  =t0_abc + f['fail_end']))

    # 更新三组 ready
    team_ready['A'] = max(team_ready['A'], t0_abc + abc.finish_time_by_group['A'])
    team_ready['B'] = max(team_ready['B'], t0_abc + abc.finish_time_by_group['B'])
    team_ready['C'] = max(team_ready['C'], t0_abc + abc.finish_time_by_group['C'])



    # 关键：把本装置上三组的忙碌时长累加到“累计用时”（用于下一台的故障概率）
    for g in ['A','B','C']:
        team_used[g] += abc.busy_by_group[g]

    t_abc_end = t0_abc + abc.finish_min

    # 5) 若 ABC 任一步两次失败 → 早退出场
    if not abc.passed_all:
        t_out = fit_in_shift(t_abc_end, INOUT_MIN) + INOUT_MIN
        hall_slot_ready_min = t_out
        return (DeviceResult(device_id, true_state, False, t_in, t_abc_end, None, t_out,
                             sched_rows, fail_rows),
                hall_slot_ready_min, team_ready, team_used, need_cal)

    # 6) 进入 E：同样考虑是否更换→校准→不跨班
    re = apply_replacement_and_ready('E', team_ready['E'])
    t0_e = max(t_abc_end, re)
    t0_e = fit_in_shift(t0_e, TE)
    if need_cal['E']: need_cal['E'] = False  # 校准机会消费

    eout = run_E(true_state, used0_E=team_used['E'])

    # 汇总 E 日志
    for r in eout.logs:
        sched_rows.append(dict(
            device=device_id, team='E',
            start=t0_e + r['start'], end=t0_e + r['end'],
            result=r.get('result'), attempt=r.get('attempt'), ok=r.get('ok')
        ))
    for f in eout.fails:
        fail_rows.append(dict(device=device_id, team='E',
                              fail_start=t0_e + f['fail_start'],
                              fail_end  =t0_e + f['fail_end']))

    # 更新 E 组 ready & 累计用时
    team_ready['E'] = max(team_ready['E'], t0_e + eout.used_min)
    team_used['E']  += eout.used_min

    t_e_end = t0_e + eout.used_min

    # 7) 出场
    t_out = fit_in_shift(t_e_end, INOUT_MIN) + INOUT_MIN
    hall_slot_ready_min = t_out

    return (DeviceResult(device_id, true_state, eout.passed, t_in, t_abc_end, t_e_end, t_out,
                         sched_rows, fail_rows),
            hall_slot_ready_min, team_ready, team_used, need_cal)
# # ——单台完整走一遍（含ABC+E），看传出来的 schedule_rows——
# team_ready = {'A':0,'B':0,'C':0,'E':0}
# team_used  = {'A':0,'B':0,'C':0,'E':0}
# need_cal   = {'A':False,'B':False,'C':False,'E':False}
# dev_res, _, _, _, _ = simulate_one_device(
#     device_id=1, hall_slot_ready_min=0,
#     team_ready=team_ready, team_used=team_used, need_cal=need_cal
# )

# print("schedule_rows 前5条：")
# for row in dev_res.schedule_rows[:5]:
#     print(row)

#%%
# =========================
# 单元8：一次完整仿真（返回统计与“第一轮的两张表”）
# =========================

def run_one_simulation(sim_id: int = 1, return_tables: bool = False):
    """
    return_tables=True 时，额外返回“进度表、故障表”（只记录本轮）
    资源：
      - 在场名额2个：hall_ready[0], hall_ready[1]
      - 四个小组：team_ready['A'/'B'/'C'/'E']
    """
    hall_ready = [0, 0]
    team_ready = {'A':0,'B':0,'C':0,'E':0}

    # 新增：累计用时 & 待校准标志
    team_used  = {'A':0,'B':0,'C':0,'E':0}      # 自上次更换以来的累计加工时间（分钟）
    team_used_sum = {'A':0,'B':0,'C':0,'E':0}   # ★ 新增：本轮累计有效工时（分钟）
    need_cal   = {'A':False,'B':False,'C':False,'E':False}

    results: list[DeviceResult] = []

    for i in range(1, N_DEV+1):
        k = 0 if hall_ready[0] <= hall_ready[1] else 1
        dev_res, new_ready, team_ready, team_used, need_cal = simulate_one_device(
            i, hall_ready[k], team_ready, team_used, team_used_sum, need_cal
        )
        hall_ready[k] = new_ready
        results.append(dev_res)
    # ★ 兜底：把未更换留下的最后一段也算进累计
    for g in ['A','B','C','E']:
        team_used_sum[g] += team_used[g]

    # ——统计指标——
    makespan_min = max(hall_ready)                 # 本轮总工期（分钟）
    T_days12 = math.ceil(makespan_min / SHIFT_MIN)         # 以“12小时”为一天
    T_days24 = math.ceil(makespan_min / (24*60)   )          # 以“24小时”为一天
    T_hours  = makespan_min / 60

    # 通过数（缺这个）
    S = sum(1 for r in results if r.passed)
    # 计算PL/PW（定义：最终判定与真实状态的“错判概率”）
    #   PW（误判）= 真H判失败 的占比；PL（漏判）= 真坏(A/B/C/D)判通过 的占比
    nH = sum(1 for r in results if r.true_state=='H')
    nBad = N_DEV - nH
    PW = sum(1 for r in results if (r.true_state=='H' and not r.passed)) / max(1, nH)
    PL = sum(1 for r in results if (r.true_state!='H' and r.passed)) / max(1, nBad)

    # 各小组有效工作时长（分钟→占比）
    total_time = T_days12*720
    YXB = {g: team_used_sum[g] / total_time for g in ['A','B','C','E']}

    if not return_tables:
        return dict(sim_id=sim_id, T_days=T_days12, S=S, PL=PL, PW=PW, YXB=YXB)

    # ——第一轮的两张表（进度/故障）——
    # ——第一轮两张表（加入‘仿真轮次’和‘真实状态’）——
    sched_rows = []
    fail_rows  = []
    for r in results:
        for row in r.schedule_rows:
            sched_rows.append(dict(
                仿真轮次=sim_id, 装置编号=r.device_id, 真实状态=r.true_state,
                测试小组=row['team'], 开始时间=row['start'], 结束时间=row['end'],
                结果=row.get('result'), 尝试序号=row.get('attempt'), 正确性=row.get('ok')
            ))
        for f in r.failure_rows:
            fail_rows.append(dict(
                仿真轮次=sim_id, 故障的装置编号=r.device_id, 真实状态=r.true_state,
                故障小组=f['team'], 故障开始时间=f['fail_start'], 故障结束时间=f['fail_end']
            ))

    cols_sched = ["仿真轮次","装置编号","真实状态","测试小组","开始时间","结束时间","结果","尝试序号","正确性"]
    cols_fail  = ["仿真轮次","故障的装置编号","真实状态","故障小组","故障开始时间","故障结束时间"]

    df_sched = (pd.DataFrame(sched_rows, columns=cols_sched)
                .sort_values(["开始时间","装置编号"], ignore_index=True))
    df_sched[["结果","尝试序号","正确性"]] = df_sched[["结果","尝试序号","正确性"]].fillna("—")
    
    # fails 可能为空，先建空表再排序，避免 KeyError
    df_fail = pd.DataFrame(fail_rows, columns=cols_fail)
    if len(df_fail):
        df_fail = df_fail.sort_values(["故障开始时间","故障的装置编号"], ignore_index=True)
    if not return_tables:
        return dict(sim_id=sim_id, T_min=makespan_min,
                    T_days12=T_days12, T_days24=T_days24, T_hours=T_hours,
                    S=S, PL=PL, PW=PW, YXB=YXB)
    # 若 return_tables=True，同样把这三个指标一并放进返回 dict
    return dict(sim_id=sim_id, T_min=makespan_min,
                T_days12=T_days12, T_days24=T_days24, T_hours=T_hours,
                S=S, PL=PL, PW=PW, YXB=YXB,
                df_sched=df_sched, df_fail=df_fail)


#%%
# =========================
# 单元9：Monte-Carlo 主循环
# =========================

# 第1轮要回表
N_SIM = 100  # 你要10轮就设10；更多也可

sheets_sched = {}
sheets_fail  = {}
MC = []
A_values, B_values, C_values, E_values = [], [], [], []

for k in range(1, N_SIM+1):
    ret = run_one_simulation(sim_id=k, return_tables=True)  # 10轮都保存表
    MC.append(dict(sim_id=k, T_min=ret["T_min"],
                   T_days12=ret["T_days12"], T_days24=ret["T_days24"], T_hours=ret["T_hours"],
                   S=ret["S"], PL=ret["PL"], PW=ret["PW"],YXB=ret['YXB']))
        # 将每个小组的 YXB 数据保存到列表
    A_values.append(ret['YXB']['A'])
    B_values.append(ret['YXB']['B'])
    C_values.append(ret['YXB']['C'])
    E_values.append(ret['YXB']['E'])

    sheets_sched[k] = ret["df_sched"]
    sheets_fail[k]  = ret["df_fail"]

df_mc = pd.DataFrame(MC)
# 计算每个小组的平均 YXB
avg_YXB_A = sum(A_values) / len(A_values)
avg_YXB_B = sum(B_values) / len(B_values)
avg_YXB_C = sum(C_values) / len(C_values)
avg_YXB_E = sum(E_values) / len(E_values)

print("=== Monte-Carlo 汇总（平均） ===")
print(f"T（12小时/天）: {df_mc['T_days12'].mean():.3f} 天")
print(f"T（24小时/天）: {df_mc['T_days24'].mean():.3f} 天")
print(f"T（小时）     : {df_mc['T_hours'].mean():.2f} 小时")
print(f"S（平均通过数）: {df_mc['S'].mean():.2f} 台 / {N_DEV}")
print(f"PL（总漏判率）: {df_mc['PL'].mean():.4f}  ({100*df_mc['PL'].mean():.2f}%)")
print(f"PW（总误判率）: {df_mc['PW'].mean():.4f}  ({100*df_mc['PW'].mean():.2f}%)")
# 打印结果
print(f"平均 YXB（A）：{avg_YXB_A:.3f}")
print(f"平均 YXB（B）：{avg_YXB_B:.3f}")
print(f"平均 YXB（C）：{avg_YXB_C:.3f}")
print(f"平均 YXB（E）：{avg_YXB_E:.3f}")
# ——绘图：分布——
fig, axes = plt.subplots(1,3, figsize=(14,4))
sns.histplot(df_mc['T_days12'], kde=True, ax=axes[0]); axes[0].set_title('T 完工天数分布')
sns.histplot(df_mc['S'],      kde=True, ax=axes[1]); axes[1].set_title('S 通过数分布')
sns.histplot(df_mc['PL'],     kde=True, ax=axes[2]); axes[2].set_title('PL 漏判率分布')
plt.tight_layout()
plt.show()

#%%
os.makedirs("导出结果", exist_ok=True)

K = min(N_SIM, 10)
with pd.ExcelWriter("导出结果/进度表_前10轮.xlsx", engine="xlsxwriter") as w:
    for k in range(1, K+1):
        sheets_sched[k].to_excel(w, sheet_name=f"Sim{k}", index=False)

with pd.ExcelWriter("导出结果/故障表_前10轮.xlsx", engine="xlsxwriter") as w:
    for k in range(1, K+1):
        sheets_fail[k].to_excel(w, sheet_name=f"Sim{k}", index=False)



```

## Assistant
*2025-09-01T02:02:47.264768+00:00*
我已经仔细阅读了你的蒙特卡洛仿真代码。这是一个工业质量检测系统的仿真模型，包含ABC并行工序和E工序。让我为你提供绘制算法流程图的指导：
基于你的代码分析，我提供了详细的流程图绘制指导。你的仿真系统结构非常清晰，主要包含三个层次：

#### 核心流程特点：

1. **三层嵌套结构**：蒙特卡洛循环 → 单次仿真 → 单台装置处理
2. **并行与串行结合**：ABC三工序并行处理，然后串行进入E工序  
3. **资源约束管理**：在场名额、小组就绪时间、不跨班等约束
4. **故障与质检机制**：每个工序都有故障概率和误判率，最多两次质检机会

#### 建议的绘制工具：

**简单工具**：
- **Draw.io/Lucidchart**：在线流程图工具，模板丰富
- **Visio**：专业流程图软件
- **PowerPoint**：简单易用，适合展示

**程序化工具**：
- **Mermaid**：用代码生成流程图
- **Graphviz**：适合复杂流程
- **Python matplotlib**：完全自定义

你希望我帮你用哪种方式来实现具体的流程图？比如：
1. 用Mermaid语法生成可直接使用的流程图代码
2. 提供更详细的手工绘制步骤
3. 用Python代码生成流程图

请告诉我你的偏好，我可以提供更具体的帮助！

## Human
*2025-09-01T02:03:19.117547+00:00*
这是已编写的算法步骤，按照这个步骤给我指导

## 附件:
[1b91960768e0c1050417ea943e438a2f.png](https://claude.9e.lv/api/35697fcd-1591-46df-a6f0-e39a43c63c0d/files/4058ef03-0929-425f-98c5-67cf8ee14419/preview)

## Assistant
*2025-09-01T02:04:48.954893+00:00*
根据你提供的算法步骤，我来为你提供更精确的流程图绘制指导：
基于你提供的8步算法，我重新整理了流程图绘制指导。你的算法结构非常清晰：

#### 核心特点分析：

1. **Step 1-3**: 预处理阶段（参数初始化、概率模型、权重计算）
2. **Step 4-6**: 核心仿真逻辑（单次测试、设备管理、并行系统）  
3. **Step 7**: 资源调度（装置名额、测试队伍管理）
4. **Step 8**: 蒙特卡洛循环控制

#### 关键算法亮点：

- **Step 3的权重计算**：误判漏判各50%的巧妙设计
- **Step 6的并行机制**：三线程推进到最早结束时间轴
- **Step 5的设备管理**：强制更换(240h)和预防更换(120h)
- **不跨班限制**：每个工序都要考虑班次边界

#### 接下来你需要什么帮助？

1. **生成具体流程图**：我可以用Mermaid语法为你生成可直接使用的流程图代码
2. **详化某个步骤**：比如Step 6的并行测试机制，或Step 3的FP/FN计算
3. **制作分层图集**：按我建议的4层结构，分别制作不同详细程度的流程图
4. **解释算法细节**：如果对某个步骤的实现逻辑需要更深入理解

请告诉我你的具体需求，我可以提供更有针对性的帮助！
