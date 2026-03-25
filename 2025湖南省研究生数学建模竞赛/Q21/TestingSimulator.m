classdef TestingSimulator < handle
    %% TestingSimulator - 测试任务仿真器主类
    
    properties (Access = private)
        params              % 参数
        currentTime         % 当前时间（分钟）
        currentDay          % 当前天数
        eventQueue          % 事件队列
        devices             % 装置数组
        workstations        % 工位状态
        platforms           % 测试台占用状态
        completedDevices    % 已完成装置数
        nextDeviceToEnter   % 下一个待进入的装置ID
        statistics          % 统计信息
    end
    
    % 在TestingSimulator类中添加一个创建事件的辅助方法
    methods (Access = private)
        function event = createEvent(obj, type, time, deviceID, workstation, platform)
            % 创建标准化的事件结构体
            event = struct();
            event.type = type;
            event.time = time;
            event.deviceID = deviceID;
            
            % 确保所有字段都存在
            if nargin < 5 || isempty(workstation)
                event.workstation = '';
            else
                event.workstation = workstation;
            end
            
            if nargin < 6 || isempty(platform)
                event.platform = 0;
            else
                event.platform = platform;
            end
        end
    end

    methods
        function obj = TestingSimulator(params)
            % 构造函数
            obj.params = params;
            obj.initialize();
        end
        
        function result = run(obj)
            % 运行仿真主循环
            maxDays = 365;  % 设置最大天数防止死循环
            
            while obj.completedDevices < obj.params.numDevices && obj.currentDay <= maxDays
                % 处理班次
                if obj.currentTime >= obj.params.shiftMinutes
                    obj.handleShiftEnd();
                    obj.currentDay = obj.currentDay + 1;
                    obj.currentTime = 0;
                    obj.handleShiftStart();
                    continue;
                end
                
                % 获取下一个事件
                event = obj.getNextEvent();
                
                if isempty(event)
                    % 没有事件，尝试调度
                    obj.scheduleDevices();
                    
                    % 如果还是没有事件，跳到班次结束
                    if isempty(obj.eventQueue)
                        obj.currentTime = obj.params.shiftMinutes;
                    end
                    continue;
                end
                
                % 事件时间检查
                if event.time > obj.params.shiftMinutes
                    % 事件跨班，推迟处理
                    obj.currentTime = obj.params.shiftMinutes;
                    obj.addEvent(event);
                    continue;
                end
                
                % 更新时间并处理事件
                obj.currentTime = event.time;
                obj.processEvent(event);
                
                % 调度新任务
                obj.scheduleDevices();
            end
            
            if obj.currentDay > maxDays
                warning('仿真达到最大天数限制！');
            end
            
            result = obj.collectStatistics();
        end
        
        function initialize(obj)
            % 初始化仿真环境
            obj.currentTime = 0;
            obj.currentDay = 1;
            obj.eventQueue = struct('type', {}, 'time', {}, 'deviceID', {}, 'workstation', {});
            obj.completedDevices = 0;
            obj.nextDeviceToEnter = 3;
            
            % 初始化统计 - 必须在调用scheduleDevices之前！
            obj.statistics = struct();
            obj.statistics.totalTestTime = zeros(1, 4);
            obj.statistics.totalSetupTime = zeros(1, 4);
            obj.statistics.schedule = {};
            
            % 初始化装置数组
            obj.devices = Device.empty(0, obj.params.numDevices);
            for i = 1:obj.params.numDevices
                obj.devices(i) = Device(i, obj.params);
            end
            
            % 初始化工位
            obj.workstations = struct();
            for ws = {'A', 'B', 'C', 'E'}
                w = ws{1};
                obj.workstations.(w) = Workstation(w, obj.params);
            end
            
            % 初始化测试台
            obj.platforms = zeros(1, obj.params.numPlatforms);
            
            % 前2个装置直接就位
            if obj.params.numDevices >= 1
                obj.platforms(1) = 1;
                obj.devices(1).location = 1;
                obj.devices(1).status = 'ready';
            end
            if obj.params.numDevices >= 2
                obj.platforms(2) = 2;
                obj.devices(2).location = 2;
                obj.devices(2).status = 'ready';
            end
            
            % 现在可以安全地调用scheduleDevices
            obj.scheduleDevices();
        end
        
        function processEvent(obj, event)
            % 处理事件
            switch event.type
                case 'TEST_COMPLETE'
                    obj.handleTestComplete(event);
                case 'EQUIPMENT_FAILURE'
                    obj.handleEquipmentFailure(event);
                case 'SETUP_COMPLETE'
                    obj.handleSetupComplete(event);
                case 'TRANSPORT_IN'
                    obj.handleTransportIn(event);
                case 'TRANSPORT_OUT'
                    obj.handleTransportOut(event);
            end
        end
        
        function handleTestComplete(obj, event)
            % 处理测试完成事件
            deviceID = event.deviceID;
            workstation = event.workstation;
            device = obj.devices(deviceID);
            ws = obj.workstations.(workstation);
            
            % 更新工位使用时间
            testTime = obj.params.testTime.(workstation);
            ws.totalUsage = ws.totalUsage + testTime;
            ws.isBusy = false;
            ws.currentDevice = 0;
            
            % 生成测试判定结果
            if strcmp(workstation, 'D')
                workstation = 'A';  % D没有单独的差错率，暂用A
            end
            
            trueState = 0;
            if strcmp(workstation, 'E')
                % E测试综合判定
                trueState = device.trueProblems.A || device.trueProblems.B || ...
                           device.trueProblems.C || device.trueProblems.D;
            else
                trueState = device.trueProblems.(workstation);
            end
            
            if trueState == 1
                missRate = obj.params.missRate.(workstation);
                hasDetected = rand() > missRate;
            else
                falseRate = obj.params.falseAlarmRate.(workstation);
                hasDetected = rand() < falseRate;
            end
            
            if hasDetected
                % 检出问题
                device.problemAttempts.(workstation) = ...
                    device.problemAttempts.(workstation) + 1;
                
                if device.problemAttempts.(workstation) >= 2
                    % 退出
                    device.status = 'failed';
                    obj.completedDevices = obj.completedDevices + 1;
                    
                    % 运出
                    obj.addEvent(struct(...
                        'type', 'TRANSPORT_OUT', ...
                        'time', obj.currentTime + obj.params.transportTime, ...
                        'deviceID', deviceID, ...
                        'workstation', ''));
                else
                    % 标记需要重测
                    device.testStatus.(workstation) = 'retry';
                end
            else
                % 测试通过
                device.testStatus.(workstation) = 'pass';
                
                % 检查是否完成
                if strcmp(workstation, 'E')
                    device.status = 'completed';
                    obj.completedDevices = obj.completedDevices + 1;
                    
                    % 运出
                    obj.addEvent(obj.createEvent('TRANSPORT_OUT', ...
                        obj.currentTime + obj.params.transportTime, ...
                        deviceID, '', 0));
                end
            end
            
            % 记录统计
            obj.statistics.totalTestTime(workstationIndex(workstation)) = ...
                obj.statistics.totalTestTime(workstationIndex(workstation)) + testTime;
        end
        
        function handleEquipmentFailure(obj, event)
            % 处理设备故障
            workstation = event.workstation;
            deviceID = event.deviceID;
            
            % 中断当前测试
            obj.workstations.(workstation).isBusy = false;
            obj.workstations.(workstation).isFailed = true;
            
            % 增加故障重测次数
            obj.devices(deviceID).failureAttempts.(workstation) = ...
                obj.devices(deviceID).failureAttempts.(workstation) + 1;
            
            % 安排设备更换
            setupTime = obj.params.setupTime.(workstation);
            obj.addEvent(struct(...
                'type', 'SETUP_COMPLETE', ...
                'time', obj.currentTime + setupTime, ...
                'workstation', workstation, ...
                'deviceID', deviceID));
            
            % 记录统计
            obj.statistics.totalSetupTime(workstationIndex(workstation)) = ...
                obj.statistics.totalSetupTime(workstationIndex(workstation)) + setupTime;
        end
        
        function handleSetupComplete(obj, event)
            % 设备维修/更换完成
            workstation = event.workstation;
            obj.workstations.(workstation).isFailed = false;
            obj.workstations.(workstation).totalUsage = 0;
        end
        
        function handleTransportOut(obj, event)
            % 处理装置运出
            deviceID = event.deviceID;
            device = obj.devices(deviceID);
            
            % 释放测试台
            platform = device.location;
            if platform > 0
                obj.platforms(platform) = 0;
            end
            device.location = -1;
            
            % 尝试运入新装置
            if obj.nextDeviceToEnter <= obj.params.numDevices
                newDeviceID = obj.nextDeviceToEnter;
                obj.nextDeviceToEnter = obj.nextDeviceToEnter + 1;
                
                % 安排运入
                obj.addEvent(obj.createEvent('TRANSPORT_IN', ...
                    obj.currentTime + obj.params.transportTime, ...
                    newDeviceID, '', platform));
                
                obj.devices(newDeviceID).status = 'transporting';
            end
        end
        
        function handleTransportIn(obj, event)
            % 处理装置运入
            deviceID = event.deviceID;
            platform = event.platform;
            
            obj.platforms(platform) = deviceID;
            obj.devices(deviceID).location = platform;
            obj.devices(deviceID).status = 'ready';
        end
        
        function handleShiftEnd(obj)
            % 处理班次结束
            for ws = {'A', 'B', 'C', 'E'}
                w = ws{1};
                if obj.workstations.(w).isBusy
                    deviceID = obj.workstations.(w).currentDevice;
                    obj.workstations.(w).isBusy = false;
                    obj.devices(deviceID).currentTest = '';
                    % 需要重新测试（从头开始）
                    % 测试状态不变，下次从头开始
                end
            end
            
            % 清空当天剩余事件
            newQueue = struct('type', {}, 'time', {}, 'deviceID', {}, 'workstation', {});
            for i = 1:length(obj.eventQueue)
                if obj.eventQueue(i).time > obj.params.shiftMinutes
                    % 将事件推迟到下一天
                    obj.eventQueue(i).time = obj.eventQueue(i).time - obj.params.shiftMinutes;
                    newQueue(end+1) = obj.eventQueue(i);
                end
            end
            obj.eventQueue = newQueue;
        end
        
        function handleShiftStart(obj)
            % 处理班次开始 - 预防性维护
            for ws = {'A', 'B', 'C', 'E'}
                w = ws{1};
                usage = obj.workstations.(w).totalUsage;
                
                if usage >= 14400  % 240小时，必须更换
                    obj.workstations.(w).totalUsage = 0;
                    obj.workstations.(w).isFailed = true;
                    
                    obj.addEvent(struct(...
                        'type', 'SETUP_COMPLETE', ...
                        'time', obj.currentTime + obj.params.setupTime.(w), ...
                        'workstation', w, ...
                        'deviceID', -1));
                elseif usage >= 7200  % 120-240小时，评估是否更换
                    % 简化处理：暂不实施预防性更换
                end
            end
        end
        
        function scheduleDevices(obj)
            % 调度算法
            readyDevices = [];
            for i = 1:min(obj.params.numDevices, obj.nextDeviceToEnter-1)
                if obj.devices(i).location > 0 && ...
                   strcmp(obj.devices(i).status, 'ready')
                    readyDevices(end+1) = i;
                end
            end
            
            if isempty(readyDevices)
                return;
            end
            
            remainingTime = obj.params.shiftMinutes - obj.currentTime;
            
            % 为每个工位尝试分配
            for ws = {'A', 'B', 'C', 'E'}
                w = ws{1};
                
                if obj.workstations.(w).isBusy || obj.workstations.(w).isFailed
                    continue;
                end
                
                testTime = obj.params.testTime.(w);
                if testTime > remainingTime
                    continue;
                end
                
                % 找可测试的装置
                for deviceID = readyDevices
                    if obj.canTest(deviceID, w)
                        % 开始测试
                        obj.startTest(deviceID, w);
                        
                        % 生成完成事件
                        obj.addEvent(obj.createEvent('TEST_COMPLETE', ...
                            obj.currentTime + testTime, ...
                            deviceID, w, 0));
                        
                        % 生成可能的故障事件
                        failureTime = obj.generateFailureTime(w, testTime);
                        if failureTime > 0 && failureTime < testTime
                            obj.addEvent(struct(...
                                'type', 'EQUIPMENT_FAILURE', ...
                                'time', obj.currentTime + failureTime, ...
                                'deviceID', deviceID, ...
                                'workstation', w));
                        end
                        
                        readyDevices(readyDevices == deviceID) = [];
                        break;
                    end
                end
            end
        end
        
        function canTest = canTest(obj, deviceID, workstation)
            % 判断是否可以测试
            device = obj.devices(deviceID);
            
            if strcmp(workstation, 'E')
                canTest = strcmp(device.testStatus.A, 'pass') && ...
                         strcmp(device.testStatus.B, 'pass') && ...
                         strcmp(device.testStatus.C, 'pass') && ...
                         ~strcmp(device.testStatus.E, 'pass') && ...
                         ~strcmp(device.testStatus.E, 'retry');
            else
                canTest = ~strcmp(device.testStatus.(workstation), 'pass') || ...
                         strcmp(device.testStatus.(workstation), 'retry');
            end
        end
        
        function startTest(obj, deviceID, workstation)
            % 开始测试
            obj.workstations.(workstation).isBusy = true;
            obj.workstations.(workstation).currentDevice = deviceID;
            obj.devices(deviceID).currentTest = workstation;
            obj.devices(deviceID).testStatus.(workstation) = 'testing';
            
            % 记录调度
            obj.statistics.schedule{end+1} = struct(...
                'deviceID', deviceID, ...
                'workstation', workstation, ...
                'startTime', obj.currentTime + (obj.currentDay-1)*720, ...
                'day', obj.currentDay);
        end
        
        function failureTime = generateFailureTime(obj, workstation, testTime)
            % 生成故障时间
            usage = obj.workstations.(workstation).totalUsage;
            
            if usage >= 14400
                failureTime = 1;  % 立即故障
                return;
            elseif usage < 7200
                rate = obj.params.failureRate.stage1.(workstation) / 7200;
            else
                rate = (obj.params.failureRate.stage2.(workstation) - ...
                       obj.params.failureRate.stage1.(workstation)) / 7200;
            end
            
            % 指数分布
            prob = 1 - exp(-rate * testTime);
            if rand() < prob
                failureTime = -log(1-rand()*prob) / rate;
            else
                failureTime = -1;
            end
        end
        
        function addEvent(obj, event)
            % 添加事件到队列
            if isempty(obj.eventQueue)
                obj.eventQueue = event;
            else
                times = [obj.eventQueue.time];
                idx = find(times > event.time, 1);
                if isempty(idx)
                    obj.eventQueue(end+1) = event;
                else
                    obj.eventQueue = [obj.eventQueue(1:idx-1), event, obj.eventQueue(idx:end)];
                end
            end
        end
        
        function event = getNextEvent(obj)
            % 获取下一个事件
            if isempty(obj.eventQueue)
                event = [];
            else
                event = obj.eventQueue(1);
                obj.eventQueue(1) = [];
            end
        end
        
        function result = collectStatistics(obj)
            % 收集统计结果
            result = struct();
            result.completionDays = obj.currentDay;
            
            passedCount = 0;
            missCount = 0;
            falseCount = 0;
            
            for i = 1:obj.params.numDevices
                device = obj.devices(i);
                if strcmp(device.status, 'completed')
                    passedCount = passedCount + 1;
                    
                    hasRealProblem = device.trueProblems.A || device.trueProblems.B || ...
                                    device.trueProblems.C || device.trueProblems.D;
                    if hasRealProblem
                        missCount = missCount + 1;
                    end
                elseif strcmp(device.status, 'failed')
                    hasRealProblem = device.trueProblems.A || device.trueProblems.B || ...
                                    device.trueProblems.C || device.trueProblems.D;
                    if ~hasRealProblem
                        falseCount = falseCount + 1;
                    end
                end
            end
            
            result.passedDevices = passedCount;
            result.missRate = missCount / max(passedCount, 1);
            result.falseAlarmRate = falseCount / max(100 - passedCount, 1);
            
            totalMinutes = obj.currentDay * obj.params.shiftMinutes;
            result.efficiency = obj.statistics.totalTestTime / max(totalMinutes, 1);
            result.schedule = obj.statistics.schedule;
        end
    end
end

function idx = workstationIndex(ws)
    switch ws
        case 'A', idx = 1;
        case 'B', idx = 2;
        case 'C', idx = 3;
        case 'E', idx = 4;
        otherwise, idx = 1;
    end
end
