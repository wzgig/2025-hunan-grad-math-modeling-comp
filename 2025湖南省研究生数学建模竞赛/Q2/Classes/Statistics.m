% Classes/Statistics.m
classdef Statistics < handle
    
    properties
        completionTime      
        numPassed          
        numFailed          
        missedProblems     
        falseAlarms        
        workstationUsage   
        schedule           
        interruptions      
    end
    
    methods
        function obj = Statistics()
            obj.completionTime = 0;
            obj.numPassed = 0;
            obj.numFailed = 0;
            obj.missedProblems = 0;
            obj.falseAlarms = 0;
            obj.workstationUsage = struct('A',0,'B',0,'C',0,'E',0);
            obj.schedule = {};
            obj.interruptions = struct('A',0,'B',0,'C',0,'E',0);
        end
        
        function recordTestComplete(obj, device, workstation, result, time)
            if result == TestResult.PASS
                if device.trueProblems.(workstation)
                    obj.missedProblems = obj.missedProblems + 1;
                end
            else
                if ~device.trueProblems.(workstation)
                    obj.falseAlarms = obj.falseAlarms + 1;
                end
            end
        end
        
        function recordInterruption(obj, workstation, time)
            obj.interruptions.(workstation) = obj.interruptions.(workstation) + 1;
        end
        
        function missRate = getMissRate(obj)
            if obj.numPassed > 0
                missRate = obj.missedProblems / obj.numPassed;
            else
                missRate = 0;
            end
        end
        
        function falseAlarmRate = getFalseAlarmRate(obj)
            totalTests = obj.numPassed + obj.numFailed;
            if totalTests > 0
                falseAlarmRate = obj.falseAlarms / totalTests;
            else
                falseAlarmRate = 0;
            end
        end

        % 在 Statistics 类中添加：
        function recordMaintenance(obj, workstation, time)
            % 记录维护事件
            if ~isfield(obj.workstationUsage, 'maintenance')
                obj.workstationUsage.maintenance = struct('A',0,'B',0,'C',0,'E',0);
            end
            obj.workstationUsage.maintenance.(workstation) = ...
                obj.workstationUsage.maintenance.(workstation) + 1;
        end
    end
end