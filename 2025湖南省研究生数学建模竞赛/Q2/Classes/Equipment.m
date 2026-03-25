% Classes/Equipment.m
classdef Equipment < handle
    
    properties
        name            % 设备名称
        usageTime       % 累计使用时间
        isFailed        % 是否故障
        setupTime       % 调试时间
        testTime        % 测试时间
        lastMaintenance % 上次维护时间
    end
    
    methods
        function obj = Equipment(name, params)
            obj.name = name;
            obj.usageTime = 0;
            obj.isFailed = false;
            obj.setupTime = params.setupTime.(name);
            obj.testTime = params.testTime.(name);
            obj.lastMaintenance = 0;
        end
        
        function addUsageTime(obj, duration)
            obj.usageTime = obj.usageTime + duration;
        end
        
        function reset(obj)
            obj.usageTime = 0;
            obj.isFailed = false;
            obj.lastMaintenance = 0;
        end
    end
end