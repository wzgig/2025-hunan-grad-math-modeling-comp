classdef Workstation < handle
%% Workstation - 工位类
    
    properties
        name            % 工位名称
        isBusy          % 是否忙碌
        isFailed        % 是否故障
        currentDevice   % 当前测试装置ID
        totalUsage      % 累计使用时间（分钟）
        lastMaintenance % 上次维护时间
    end
    
    methods
        function obj = Workstation(name, params)
            % 构造函数
            obj.name = name;
            obj.isBusy = false;
            obj.isFailed = false;
            obj.currentDevice = 0;
            obj.totalUsage = 0;
            obj.lastMaintenance = 0;
        end
        
        function reset(obj)
            % 重置设备（更换后）
            obj.totalUsage = 0;
            obj.isFailed = false;
            obj.lastMaintenance = 0;
        end
    end
end