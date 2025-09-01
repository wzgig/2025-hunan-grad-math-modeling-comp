% Classes/Event.m
classdef Event
    properties
        time            
        type            
        deviceId        
        workstation     
        triggerScheduling  
    end
    
    methods
        function obj = Event(time, type, deviceId)
            obj.time = time;
            obj.type = type;
            obj.deviceId = deviceId;
            obj.workstation = '';
            obj.triggerScheduling = false;
        end
    end
end