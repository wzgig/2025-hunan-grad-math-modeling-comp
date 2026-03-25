classdef Device < handle
%% Device - 装置类
    
    properties
        id                  % 装置编号
        location            % 位置（0=场外，1/2=测试台）
        status              % 状态（pending/ready/testing/completed/failed）
        currentTest         % 当前测试工位
        
        % 真实问题状态
        trueProblems        % 结构体 {A,B,C,D}
        
        % 测试状态
        testStatus          % 结构体 {A,B,C,E}
        
        % 重测次数
        problemAttempts     % 因问题重测次数
        failureAttempts     % 因故障重测次数
    end
    
    methods
        function obj = Device(id, params)
            % 构造函数
            obj.id = id;
            obj.location = 0;
            obj.status = 'pending';
            obj.currentTest = '';
            
            % 生成真实问题状态
            obj.trueProblems = struct();
            obj.trueProblems.A = rand() < params.problemProb.A;
            obj.trueProblems.B = rand() < params.problemProb.B;
            obj.trueProblems.C = rand() < params.problemProb.C;
            obj.trueProblems.D = rand() < params.problemProb.D;
            
            % 初始化测试状态
            obj.testStatus = struct();
            obj.testStatus.A = 'untested';
            obj.testStatus.B = 'untested';
            obj.testStatus.C = 'untested';
            obj.testStatus.E = 'untested';
            
            % 初始化重测次数
            obj.problemAttempts = struct('A', 0, 'B', 0, 'C', 0, 'E', 0);
            obj.failureAttempts = struct('A', 0, 'B', 0, 'C', 0, 'E', 0);
        end
        
        function canStart = canStartE(obj)
            % 判断是否可以开始E测试
            canStart = strcmp(obj.testStatus.A, 'pass') && ...
                      strcmp(obj.testStatus.B, 'pass') && ...
                      strcmp(obj.testStatus.C, 'pass') && ...
                      ~strcmp(obj.testStatus.E, 'pass');
        end
    end
end