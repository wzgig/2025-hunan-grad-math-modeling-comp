function params = InitParams()
%% InitParams - 初始化系统参数
% 输出：params - 参数结构体

%% 基础参数
params.numDevices = 100;           % 装置数量
params.numPlatforms = 2;            % 测试台数量
params.shiftHours = 12;            % 每班工作时间（小时）
params.shiftMinutes = 720;         % 每班工作时间（分钟）

%% 子系统问题概率
params.problemProb = struct();
params.problemProb.A = 0.025;      % A子系统
params.problemProb.B = 0.030;      % B子系统
params.problemProb.C = 0.020;      % C子系统
params.problemProb.D = 0.001;      % D子系统（联接系统）

%% 测手差错率
params.errorRate = struct();
params.errorRate.A = 0.03;         % A组总差错率
params.errorRate.B = 0.04;         % B组
params.errorRate.C = 0.02;         % C组
params.errorRate.E = 0.02;         % E组（综合测试）

%% 计算误判率和漏判率
% 根据"各占50%"的约束
for ws = {'A', 'B', 'C'}
    w = ws{1};
    p = params.problemProb.(w);
    e = params.errorRate.(w);
    params.missRate.(w) = 0.5 * e / p;           % 漏判率
    params.falseAlarmRate.(w) = 0.5 * e / (1-p); % 误判率
end

% E的处理需要特殊计算（在仿真中动态计算）
params.missRate.E = 0.01;          % 暂定值
params.falseAlarmRate.E = 0.01;    % 暂定值

%% 测试时长（分钟）
params.testTime = struct();
params.testTime.A = 150;           % 2.5小时
params.testTime.B = 120;           % 2小时
params.testTime.C = 150;           % 2.5小时
params.testTime.E = 180;           % 3小时

%% 设备调试时间（分钟）
params.setupTime = struct();
params.setupTime.A = 30;
params.setupTime.B = 20;
params.setupTime.C = 20;
params.setupTime.E = 40;

%% 运输时间（分钟）
params.transportTime = 30;         % 运入或运出各30分钟

%% 设备故障率
% 第一阶段（0-120小时）
params.failureRate.stage1 = struct();
params.failureRate.stage1.A = 0.03;
params.failureRate.stage1.B = 0.04;
params.failureRate.stage1.C = 0.02;
params.failureRate.stage1.E = 0.03;

% 第二阶段（120-240小时）
params.failureRate.stage2 = struct();
params.failureRate.stage2.A = 0.05;
params.failureRate.stage2.B = 0.07;
params.failureRate.stage2.C = 0.06;
params.failureRate.stage2.E = 0.05;

%% 调度权重（通过参数优化获得）
params.scheduleWeights = [3, 2, 1]; % [进度权重, 等待权重, SPT权重]

end