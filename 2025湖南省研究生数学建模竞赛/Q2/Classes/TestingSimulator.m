% Classes/TestingSimulator.m
classdef TestingSimulator < handle
    
    properties (Access = private)
        params          
        currentTime     
        eventQueue      
        devices         
        workstations    
        testPlatforms   
        statistics      
        randomStreams   
        currentShift    
        shiftEndTime    
    end
    
    methods (Access = public)
        function obj = TestingSimulator(params)
            obj.params = params;
            % 先初始化随机流，再初始化其他组件
            obj.randomStreams = struct();
            obj.randomStreams.quality = RandStream('mt19937ar', 'Seed', 1);
            obj.randomStreams.failure = RandStream('mt19937ar', 'Seed', 1001);
            obj.randomStreams.testing = RandStream('mt19937ar', 'Seed', 2001);
            obj.initialize();
        end
        
        function setRandomSeed(obj, seed)
            % 重新设置随机种子
            obj.randomStreams.quality = RandStream('mt19937ar', 'Seed', seed);
            obj.randomStreams.failure = RandStream('mt19937ar', 'Seed', seed+1000);
            obj.randomStreams.testing = RandStream('mt19937ar', 'Seed', seed+2000);
            
            % 重新生成装置的真实问题状态
            for i = 1:obj.params.numDevices
                obj.devices(i).regenerateProblems(obj.params, obj.randomStreams.quality);
            end
        end
        
        function results = run(obj)
            while ~obj.isSimulationComplete()
                event = obj.getNextEvent();
                if isempty(event)
                    break;
                end
                
                obj.currentTime = event.time;
                obj.processEvent(event);
                
                if event.triggerScheduling
                    obj.scheduleDevices();
                end
            end
            
            results = obj.collectStatistics();
        end
    end
    
    methods (Access = private)
        function initialize(obj)
            obj.currentTime = 0;
            obj.currentShift = 1;
            obj.shiftEndTime = obj.params.shiftHours * 60;
            obj.eventQueue = EventQueue();
            
            % 初始化装置
            obj.devices = Device.empty(0, obj.params.numDevices);
            for i = 1:obj.params.numDevices
                obj.devices(i) = Device(i, obj.params, obj.randomStreams.quality);
            end
            
            % 初始化工位
            obj.workstations = struct();
            for ws = {'A', 'B', 'C', 'E'}
                obj.workstations.(ws{1}) = Workstation(ws{1}, obj.params);
            end
            
            % 初始化测试台
            obj.testPlatforms = zeros(1, 2);  
            
            % 初始化统计
            obj.statistics = Statistics();
            
            % 生成初始事件
            obj.generateArrivalEvents();
            
            % 添加第一个班次结束事件
            shiftEnd = Event(obj.shiftEndTime, EventType.SHIFT_END, 0);
            obj.eventQueue.addEvent(shiftEnd);
        end

        % 在 TestingSimulator 类的 methods (Access = private) 部分添加：
        function event = getNextEvent(obj)
            event = obj.eventQueue.getNext();
        end
        
        function complete = isSimulationComplete(obj)
            % 判断仿真是否完成
            complete = true;
            for i = 1:obj.params.numDevices
                if obj.devices(i).departureTime < 0
                    complete = false;
                    break;
                end
            end
            
            % 或者超过最大仿真时间
            if obj.currentTime > obj.params.maxSimTime
                complete = true;
            end
        end
        
        function generateArrivalEvents(obj)
            % 生成装置到达事件
            % 前两个装置立即到达
            for i = 1:min(2, obj.params.numDevices)
                arrivalEvent = Event(0, EventType.ARRIVAL, i);
                obj.eventQueue.addEvent(arrivalEvent);
                obj.devices(i).arrivalTime = 0;
            end
            
            % 其余装置按需到达
            nextArrivalTime = 0;
            for i = 3:obj.params.numDevices
                % 当有测试台空闲时安排下一个装置到达
                nextArrivalTime = nextArrivalTime + obj.params.transportTime.in;
                arrivalEvent = Event(nextArrivalTime, EventType.ARRIVAL, i);
                obj.eventQueue.addEvent(arrivalEvent);
                obj.devices(i).arrivalTime = nextArrivalTime;
            end
        end
        
        function processArrival(obj, event)
            deviceId = event.deviceId;
            device = obj.devices(deviceId);
            
            % 找到空闲的测试台
            for k = 1:obj.params.numPlatforms
                if obj.testPlatforms(k) == 0
                    obj.testPlatforms(k) = deviceId;
                    device.currentPlatform = k;
                    break;
                end
            end
            
            % 触发调度
            event.triggerScheduling = true;
        end
        
        function processTestStart(obj, event)
            deviceId = event.deviceId;
            wsName = event.workstation;
            
            device = obj.devices(deviceId);
            ws = obj.workstations.(wsName);
            
            % 开始测试
            ws.startTest(deviceId, obj.currentTime);
            device.testStatus.(wsName) = TestResult.TESTING;
            
            % 计算完成时间
            testDuration = obj.params.testTime.(wsName);
            completeTime = obj.currentTime + testDuration;
            
            % 生成故障事件（如果会发生）
            failureTime = obj.generateFailureTime(ws.equipment);
            if failureTime < testDuration
                % 会发生故障
                failureEvent = Event(obj.currentTime + failureTime, EventType.EQUIPMENT_FAILURE, deviceId);
                failureEvent.workstation = wsName;
                obj.eventQueue.addEvent(failureEvent);
            else
                % 正常完成
                completeEvent = Event(completeTime, EventType.TEST_COMPLETE, deviceId);
                completeEvent.workstation = wsName;
                completeEvent.triggerScheduling = true;
                obj.eventQueue.addEvent(completeEvent);
            end
        end
        
        function failureTime = generateFailureTime(obj, equipment)
            % 生成故障时间
            prob = obj.calculateFailureProbability(equipment.usageTime + 1000, equipment.name) - ...
                   obj.calculateFailureProbability(equipment.usageTime, equipment.name);
            
            if rand(obj.randomStreams.failure) < prob
                % 在测试期间随机时刻故障
                failureTime = rand(obj.randomStreams.failure) * 1000;
            else
                failureTime = inf;  % 不会故障
            end
        end
        
        function processEquipmentFailure(obj, event)
            deviceId = event.deviceId;
            wsName = event.workstation;
            
            device = obj.devices(deviceId);
            ws = obj.workstations.(wsName);
            
            % 设备故障，中断测试
            ws.equipment.isFailed = true;
            ws.interruptTest(obj.currentTime);
            
            % 重置装置测试状态
            device.testStatus.(wsName) = TestResult.NOT_TESTED;
            
            % 安排设备维修
            repairTime = obj.currentTime + ws.equipment.setupTime;
            repairEvent = Event(repairTime, EventType.EQUIPMENT_REPAIR, 0);
            repairEvent.workstation = wsName;
            obj.eventQueue.addEvent(repairEvent);
            
            % 记录中断
            obj.statistics.recordInterruption(wsName, obj.currentTime);
        end
        
        function processEquipmentRepair(obj, event)
            wsName = event.workstation;
            ws = obj.workstations.(wsName);
            
            % 设备修复
            ws.equipment.reset();
            ws.equipment.isFailed = false;
            
            % 触发调度
            event.triggerScheduling = true;
        end
        
        function processDeparture(obj, event)
            deviceId = event.deviceId;
            device = obj.devices(deviceId);
            
            % 释放测试台
            if device.currentPlatform > 0
                obj.testPlatforms(device.currentPlatform) = 0;
                device.currentPlatform = 0;
            end
            
            % 记录完成时间
            if obj.statistics.completionTime < obj.currentTime
                obj.statistics.completionTime = obj.currentTime;
            end
            
            % 安排下一个装置进入（如果有）
            for i = 1:obj.params.numDevices
                if obj.devices(i).currentPlatform == 0 && obj.devices(i).arrivalTime > 0 && ...
                   obj.devices(i).departureTime < 0
                    % 找到等待的装置
                    arrivalEvent = Event(obj.currentTime + obj.params.transportTime.in, EventType.ARRIVAL, i);
                    obj.eventQueue.addEvent(arrivalEvent);
                    break;
                end
            end
        end
        
        function checkShiftEnd(obj)
            % 检查是否到班次结束时间（此方法在主循环中调用）
            % 班次结束事件已经在事件队列中处理
        end
        
        function waitingDevices = getWaitingDevices(obj)
            % 获取等待测试的装置
            waitingDevices = [];
            for i = 1:obj.params.numDevices
                if obj.devices(i).currentPlatform > 0 && obj.devices(i).departureTime < 0
                    % 装置在测试台上且未完成
                    waitingDevices(end+1) = i;
                end
            end
        end
        
        function canTest = canTestWorkstation(obj, deviceId, wsName)
            % 检查装置是否可以在指定工位测试
            device = obj.devices(deviceId);
            
            if strcmp(wsName, 'E')
                % E测试需要ABC都通过
                canTest = device.canStartE() && device.testStatus.E == TestResult.NOT_TESTED;
            else
                % ABC测试
                canTest = device.testStatus.(wsName) == TestResult.NOT_TESTED || ...
                         device.testStatus.(wsName) == TestResult.RETESTING;
            end
        end
        
        function assignDeviceToWorkstation(obj, deviceId, wsName)
            % 分配装置到工位
            ws = obj.workstations.(wsName);
            device = obj.devices(deviceId);
            
            % 创建测试开始事件
            startEvent = Event(obj.currentTime, EventType.TEST_START, deviceId);
            startEvent.workstation = wsName;
            obj.eventQueue.addEvent(startEvent);
        end
        
        function replaceEquipment(obj, wsName)
            % 更换设备
            ws = obj.workstations.(wsName);
            ws.equipment.reset();
            obj.statistics.recordMaintenance(wsName, obj.currentTime);
        end
        
        function results = collectStatistics(obj)
            % 收集统计结果
            results = struct();
            results.completionTime = obj.statistics.completionTime;
            results.numPassed = obj.statistics.numPassed;
            results.numFailed = obj.statistics.numFailed;
            results.missRate = obj.statistics.getMissRate();
            results.falseAlarmRate = obj.statistics.getFalseAlarmRate();
            
            % 计算工位效率
            totalTime = obj.statistics.completionTime;
            results.workstationEfficiency = struct();
            for ws = {'A', 'B', 'C', 'E'}
                wsName = ws{1};
                results.workstationEfficiency.(wsName) = ...
                    obj.workstations.(wsName).getEfficiency(totalTime);
            end
            
            % 设备故障统计
            results.equipmentFailures = obj.statistics.interruptions;
            
            % 调度记录
            results.schedule = obj.statistics.schedule;
        end      
        function processEvent(obj, event)
            switch event.type
                case EventType.ARRIVAL
                    obj.processArrival(event);
                case EventType.TEST_START
                    obj.processTestStart(event);
                case EventType.TEST_COMPLETE
                    obj.processTestComplete(event);
                case EventType.EQUIPMENT_FAILURE
                    obj.processEquipmentFailure(event);
                case EventType.EQUIPMENT_REPAIR
                    obj.processEquipmentRepair(event);
                case EventType.SHIFT_END
                    obj.processShiftEnd(event);
                case EventType.DEPARTURE
                    obj.processDeparture(event);
            end
        end
        
        function processTestComplete(obj, event)
            deviceId = event.deviceId;
            wsName = event.workstation;
            device = obj.devices(deviceId);
            ws = obj.workstations.(wsName);
            
            % 执行测试判定（考虑测手差错）
            testResult = obj.performTest(device, wsName);
            
            % 更新工位状态
            ws.completeTest(obj.currentTime);
            
            % 更新装置状态
            if testResult == TestResult.PASS
                device.testStatus.(wsName) = TestResult.PASS;
                obj.statistics.recordTestComplete(device, wsName, TestResult.PASS, obj.currentTime);
                
                % 检查是否可以开始E测试
                if strcmp(wsName, 'E')
                    % E测试通过，装置完成
                    device.departureTime = obj.currentTime + obj.params.transportTime.out;
                    departEvent = Event(device.departureTime, EventType.DEPARTURE, deviceId);
                    obj.eventQueue.addEvent(departEvent);
                    obj.statistics.numPassed = obj.statistics.numPassed + 1;
                elseif device.canStartE()
                    % ABC都通过，可以开始E测试
                    event.triggerScheduling = true;
                end
            else
                % 测试失败，需要重测
                device.testAttempts.(wsName) = device.testAttempts.(wsName) + 1;
                obj.statistics.recordTestComplete(device, wsName, TestResult.FAIL, obj.currentTime);
                
                if device.testAttempts.(wsName) >= 2
                    % 连续两次失败，装置退出
                    device.testStatus.(wsName) = TestResult.REJECTED;
                    device.departureTime = obj.currentTime + obj.params.transportTime.out;
                    departEvent = Event(device.departureTime, EventType.DEPARTURE, deviceId);
                    obj.eventQueue.addEvent(departEvent);
                    obj.statistics.numFailed = obj.statistics.numFailed + 1;
                else
                    % 安排重测
                    device.testStatus.(wsName) = TestResult.RETESTING;
                    event.triggerScheduling = true;
                end
            end
        end
        
        function result = performTest(obj, device, wsName)
            % 执行测试判定逻辑（核心修正）
            hasProblem = false;
            
            if strcmp(wsName, 'E')
                % E测试：检查是否有残留问题
                hasProblem = device.hasResidualProblem();
            else
                % ABC测试：检查对应子系统
                hasProblem = device.trueProblems.(wsName);
            end
            
            % 考虑测手差错
            if hasProblem
                % 有问题：可能漏判
                missRate = obj.params.missRate.(wsName);
                if rand(obj.randomStreams.testing) < missRate
                    result = TestResult.PASS;  % 漏判
                else
                    result = TestResult.FAIL;  % 正确检出
                end
            else
                % 无问题：可能误判
                falseAlarmRate = obj.params.falseAlarmRate.(wsName);
                if rand(obj.randomStreams.testing) < falseAlarmRate
                    result = TestResult.FAIL;  % 误判
                else
                    result = TestResult.PASS;  % 正确判定
                end
            end
        end
        
        function scheduleDevices(obj)
            % 调度算法
            waitingDevices = obj.getWaitingDevices();
            if isempty(waitingDevices)
                return;
            end
            
            priorities = obj.calculatePriorities(waitingDevices);
            [~, sortIdx] = sort(priorities, 'descend');
            sortedDevices = waitingDevices(sortIdx);
            
            for ws = {'A', 'B', 'C', 'E'}
                wsName = ws{1};
                if obj.workstations.(wsName).isAvailable()
                    remainingTime = obj.shiftEndTime - obj.currentTime;
                    testTime = obj.params.testTime.(wsName);
                    
                    % 班次窗口约束检查
                    if remainingTime >= testTime
                        for devId = sortedDevices
                            if obj.canTestWorkstation(devId, wsName)
                                obj.assignDeviceToWorkstation(devId, wsName);
                                break;
                            end
                        end
                    end
                end
            end
        end
        
        function priority = calculatePriorities(obj, devices)
            priority = zeros(size(devices));
            
            for i = 1:length(devices)
                dev = obj.devices(devices(i));
                
                % 进度因子
                progress = sum([dev.testStatus.A, dev.testStatus.B, ...
                               dev.testStatus.C] == TestResult.PASS) / 3;
                
                % 等待时间因子
                waitTime = (obj.currentTime - dev.arrivalTime) / (12*60);
                
                % 剩余工时因子
                remainingTests = 4 - sum([dev.testStatus.A, dev.testStatus.B, ...
                                         dev.testStatus.C, dev.testStatus.E] == TestResult.PASS);
                sptFactor = 1 / max(remainingTests, 0.1);
                
                % 加权组合
                priority(i) = obj.params.scheduleWeights(1) * progress + ...
                             obj.params.scheduleWeights(2) * waitTime + ...
                             obj.params.scheduleWeights(3) * sptFactor;
                
                % E测试优先级提升
                if dev.canStartE()
                    priority(i) = priority(i) + 5;
                end
            end
        end
        
        function processShiftEnd(obj, event)
            % 处理班次结束
            % 中断所有进行中的测试
            for ws = {'A', 'B', 'C', 'E'}
                wsName = ws{1};
                if obj.workstations.(wsName).isOccupied
                    deviceId = obj.workstations.(wsName).currentDevice;
                    device = obj.devices(deviceId);
                    
                    % 记录中断损失
                    obj.statistics.recordInterruption(wsName, obj.currentTime);
                    
                    % 重置测试状态
                    device.testStatus.(wsName) = TestResult.NOT_TESTED;
                    obj.workstations.(wsName).interruptTest(obj.currentTime);
                end
            end
            
            % 检查设备维护需求
            obj.performMaintenance();
            
            % 设置下一班次
            obj.currentShift = obj.currentShift + 1;
            obj.shiftEndTime = obj.currentShift * obj.params.shiftHours * 60;
            
            % 添加下一个班次结束事件
            nextShiftEnd = Event(obj.shiftEndTime, EventType.SHIFT_END, 0);
            obj.eventQueue.addEvent(nextShiftEnd);
        end
        
        function performMaintenance(obj)
            % 执行预防性维护决策
            for ws = {'A', 'B', 'C', 'E'}
                wsName = ws{1};
                equipment = obj.workstations.(wsName).equipment;
                
                if equipment.usageTime >= 14400  % 240小时强制更换
                    obj.replaceEquipment(wsName);
                elseif equipment.usageTime >= 7200  % 120小时以上评估
                    if obj.shouldPerformPreventiveMaintenance(equipment)
                        obj.replaceEquipment(wsName);
                    end
                end
            end
        end
        
        function should = shouldPerformPreventiveMaintenance(obj, equipment)
            % 预防性维护决策
            remainingShiftTime = obj.params.shiftHours * 60;
            
            % 计算故障概率
            currentUsage = equipment.usageTime;
            futureUsage = currentUsage + remainingShiftTime;
            
            % 故障概率增量
            failureProb = obj.calculateFailureProbability(futureUsage, equipment.name) - ...
                         obj.calculateFailureProbability(currentUsage, equipment.name);
            
            % 期望成本比较
            expectedFailureCost = failureProb * (equipment.setupTime + 0.5 * equipment.testTime);
            replacementCost = equipment.setupTime;
            
            should = (expectedFailureCost > replacementCost);
        end
        
        function prob = calculateFailureProbability(obj, usageTime, wsName)
            % 计算累积故障概率
            stage1Rate = obj.params.failureRate.stage1.(wsName);
            stage2Rate = obj.params.failureRate.stage2.(wsName);
            
            if usageTime <= 7200
                prob = stage1Rate * (usageTime / 7200);
            elseif usageTime <= 14400
                prob = stage1Rate + (stage2Rate - stage1Rate) * ((usageTime - 7200) / 7200);
            else
                prob = 1;
            end
        end
    end
end