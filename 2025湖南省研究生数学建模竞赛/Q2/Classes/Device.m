% Classes/Device.m
classdef Device < handle
    
    properties
        id              
        trueProblems    
        testStatus      
        testAttempts    
        arrivalTime     
        departureTime   
        currentPlatform 
        testHistory     
    end
    
    methods
        function obj = Device(id, params, rng)
            obj.id = id;
            obj.arrivalTime = -1;
            obj.departureTime = -1;
            obj.currentPlatform = 0;
            obj.testHistory = [];
            
            % 生成真实问题状态
            obj.generateProblems(params, rng);
            
            % 初始化测试状态
            obj.initializeTestStatus();
            
            % 初始化尝试次数
            obj.testAttempts = struct('A', 0, 'B', 0, 'C', 0, 'E', 0);
        end
        
        function generateProblems(obj, params, rng)
            % 生成真实问题状态
            obj.trueProblems = struct();
            obj.trueProblems.A = (rand(rng) < params.problemProb.A);
            obj.trueProblems.B = (rand(rng) < params.problemProb.B);
            obj.trueProblems.C = (rand(rng) < params.problemProb.C);
            obj.trueProblems.D = (rand(rng) < params.problemProb.D);
        end
        
        function regenerateProblems(obj, params, rng)
            % 重新生成问题（用于设置新的随机种子）
            obj.generateProblems(params, rng);
        end
        
        function initializeTestStatus(obj)
            % 初始化测试状态
            obj.testStatus = struct();
            obj.testStatus.A = TestResult.NOT_TESTED;
            obj.testStatus.B = TestResult.NOT_TESTED;
            obj.testStatus.C = TestResult.NOT_TESTED;
            obj.testStatus.E = TestResult.NOT_TESTED;
        end
        
        function result = canStartE(obj)
            % 判断是否可以开始E测试
            result = (obj.testStatus.A == TestResult.PASS) && ...
                    (obj.testStatus.B == TestResult.PASS) && ...
                    (obj.testStatus.C == TestResult.PASS) && ...
                    (obj.testStatus.E == TestResult.NOT_TESTED);
        end
        
        function hasProblem = hasResidualProblem(obj)
            % 判断是否有残留问题（考虑漏判）
            hasProblem = false;
            
            % 检查各子系统是否有未检出的问题
            % 注意：这里需要检查的是通过了测试但实际有问题的情况
            if obj.trueProblems.A && obj.testStatus.A == TestResult.PASS
                hasProblem = true;  % A被漏判
            end
            if obj.trueProblems.B && obj.testStatus.B == TestResult.PASS
                hasProblem = true;  % B被漏判
            end
            if obj.trueProblems.C && obj.testStatus.C == TestResult.PASS
                hasProblem = true;  % C被漏判
            end
            if obj.trueProblems.D
                hasProblem = true;  % D系统问题
            end
        end
    end
end