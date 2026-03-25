% Classes/EventQueue.m
classdef EventQueue < handle
    
    properties (Access = private)
        eventList      % 事件数组（改名避免使用保留字）
        eventCount     % 事件数量
    end
    
    methods
        function obj = EventQueue()
            obj.eventList = Event.empty();
            obj.eventCount = 0;
        end
        
        function addEvent(obj, event)
            obj.eventList(end+1) = event;
            obj.eventCount = obj.eventCount + 1;
            
            % 维护最小堆
            idx = obj.eventCount;
            while idx > 1
                parentIdx = floor(idx/2);
                if obj.eventList(idx).time < obj.eventList(parentIdx).time
                    temp = obj.eventList(idx);
                    obj.eventList(idx) = obj.eventList(parentIdx);
                    obj.eventList(parentIdx) = temp;
                    idx = parentIdx;
                else
                    break;
                end
            end
        end
        
        function event = getNext(obj)
            if obj.isEmpty()
                event = [];
                return;
            end
            
            event = obj.eventList(1);
            obj.eventList(1) = obj.eventList(obj.eventCount);
            obj.eventList(obj.eventCount) = [];
            obj.eventCount = obj.eventCount - 1;
            
            if obj.eventCount > 0
                obj.heapifyDown(1);
            end
        end
        
        function empty = isEmpty(obj)
            empty = (obj.eventCount == 0);
        end
        
        function heapifyDown(obj, idx)
            while true
                leftChild = 2 * idx;
                rightChild = 2 * idx + 1;
                smallest = idx;
                
                if leftChild <= obj.eventCount && ...
                   obj.eventList(leftChild).time < obj.eventList(smallest).time
                    smallest = leftChild;
                end
                
                if rightChild <= obj.eventCount && ...
                   obj.eventList(rightChild).time < obj.eventList(smallest).time
                    smallest = rightChild;
                end
                
                if smallest ~= idx
                    temp = obj.eventList(idx);
                    obj.eventList(idx) = obj.eventList(smallest);
                    obj.eventList(smallest) = temp;
                    idx = smallest;
                else
                    break;
                end
            end
        end
    end
end