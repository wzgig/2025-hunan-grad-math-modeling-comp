% Functions/initializeParameters.m
function params = initializeParameters()

%% 基础参数
params.numDevices = 100;        
params.shiftHours = 12;         
params.numPlatforms = 2;         

%% 问题概率
params.problemProb = struct();
params.problemProb.A = 0.025;   
params.problemProb.B = 0.030;   
params.problemProb.C = 0.020;   
params.problemProb.D = 0.001;   

%% 测手差错率（修正后的计算）
params.errorRate = struct();
params.errorRate.A = 0.03;      
params.errorRate.B = 0.04;      
params.errorRate.C = 0.02;      
params.errorRate.E = 0.02;      

% 正确的误判率和漏判率计算
params.falseAlarmRate = struct();
params.missRate = struct();

% A组
params.missRate.A = 0.5 * params.errorRate.A / params.problemProb.A;
params.falseAlarmRate.A = 0.5 * params.errorRate.A / (1 - params.problemProb.A);

% B组
params.missRate.B = 0.5 * params.errorRate.B / params.problemProb.B;
params.falseAlarmRate.B = 0.5 * params.errorRate.B / (1 - params.problemProb.B);

% C组
params.missRate.C = 0.5 * params.errorRate.C / params.problemProb.C;
params.falseAlarmRate.C = 0.5 * params.errorRate.C / (1 - params.problemProb.C);

% E组的处理需要特殊计算
pAny = 1 - (1-params.problemProb.A*params.missRate.A) * ...
          (1-params.problemProb.B*params.missRate.B) * ...
          (1-params.problemProb.C*params.missRate.C) * ...
          (1-params.problemProb.D);
params.missRate.E = 0.5 * params.errorRate.E / pAny;
params.falseAlarmRate.E = 0.5 * params.errorRate.E / (1 - pAny);

%% 测试时长（分钟）
params.testTime = struct();
params.testTime.A = 150;        
params.testTime.B = 120;        
params.testTime.C = 150;        
params.testTime.E = 180;        

%% 设备调试时间（分钟）
params.setupTime = struct();
params.setupTime.A = 30;
params.setupTime.B = 20;
params.setupTime.C = 20;
params.setupTime.E = 40;

%% 运输时间（分钟）
params.transportTime = struct();
params.transportTime.in = 30;   
params.transportTime.out = 30;  

%% 设备故障率
params.failureRate = struct();
params.failureRate.stage1 = struct('A', 0.03, 'B', 0.04, 'C', 0.02, 'E', 0.03);
params.failureRate.stage2 = struct('A', 0.05, 'B', 0.07, 'C', 0.06, 'E', 0.05);

%% 调度权重
params.scheduleWeights = [3, 2, 1];  

%% 仿真控制参数
params.maxSimTime = 365 * 24 * 60;  
params.verbose = false;              

end