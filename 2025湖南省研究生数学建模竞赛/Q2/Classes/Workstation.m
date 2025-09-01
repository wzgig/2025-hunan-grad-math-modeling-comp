% Classes/Workstation.m
classdef Workstation < handle
    %WORKSTATION 工位类
    
    properties
        name            % 工位名称 {A,B,C,E}
        isOccupied      % 是否被占用
        currentDevice   % 当前测试的装置ID
        equipment       % 设备对象
        testStartTime   % 当前测试开始时间
        totalTestTime   % 累计测试时间
        totalIdleTime   % 累计空闲时间
    end
    
    methods
        function obj = Workstation(name, params)
            obj.name = name;
            obj.isOccupied = false;
            obj.currentDevice = 0;
            obj.equipment = Equipment(name, params);
            obj.testStartTime = 0;
            obj.totalTestTime = 0;
            obj.totalIdleTime = 0;
        end
        
        function available = isAvailable(obj)
            available = ~obj.isOccupied && ~obj.equipment.isFailed;
        end
        
        function startTest(obj, deviceId, currentTime)
            obj.isOccupied = true;
            obj.currentDevice = deviceId;
            obj.testStartTime = currentTime;
        end
        
        function completeTest(obj, currentTime)
            testDuration = currentTime - obj.testStartTime;
            obj.totalTestTime = obj.totalTestTime + testDuration;
            obj.equipment.addUsageTime(testDuration);
            obj.isOccupied = false;
            obj.currentDevice = 0;
        end
        
        function efficiency = getEfficiency(obj, totalTime)
            efficiency = obj.totalTestTime / totalTime;
        end

        % 在 Workstation 类中添加：
        function interruptTest(obj, currentTime)
            % 中断测试
            if obj.isOccupied
                % 记录中断时的测试时长
                interruptedDuration = currentTime - obj.testStartTime;
                % 不计入有效工作时间
                obj.isOccupied = false;
                obj.currentDevice = 0;
            end
        end
    end
end