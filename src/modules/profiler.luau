local Profiler = {}
Profiler.__index = Profiler

Profiler.maxFrames = 120 -- frames to keep in history

Profiler._frames = {} -- circular buffer of past frames
Profiler._currentZones = {} -- zones being recorded this frame
Profiler._counters = {} -- counters by name
Profiler._workers = {} -- key = worker name, value = currentZones table

function Profiler:_newFrame()
	local frame = {
		zones = {}, -- {name, duration}
		counters = {}, -- snapshot of counters for this frame
	}
	table.insert(self._frames, frame)
	if #self._frames > self.maxFrames then
		table.remove(self._frames, 1)
	end
end

function Profiler:Begin(name)
	table.insert(self._currentZones, {
		name = name,
		start = os.clock(),
	})
end

function Profiler:End()
	local zone = table.remove(self._currentZones)
	if zone then
		zone.duration = os.clock() - zone.start
		-- record it into the current frame
		local frame = self._frames[#self._frames]
		if frame then
			table.insert(frame.zones, zone)
		end
	end
end

function Profiler:SetCounter(name, value)
	self._counters[name] = value
end

function Profiler:NextFrame()
	self:_newFrame()
	local frame = self._frames[#self._frames]
	-- snapshot counters into the frame
	for k, v in pairs(self._counters) do
		frame.counters[k] = v
	end
	-- reset current zones
	self._currentZones = {}
end

function Profiler:BeginWorker(workerName, zoneName)
	if not self._workers[workerName] then
		self._workers[workerName] = {}
	end
	table.insert(self._workers[workerName], {
		name = zoneName,
		start = os.clock(),
	})
end

function Profiler:EndWorker(workerName)
	local zones = self._workers[workerName]
	if zones then
		local zone = table.remove(zones)
		if zone then
			zone.duration = os.clock() - zone.start
			-- store in current frame under worker
			local frame = self._frames[#self._frames]
			frame.workerZones = frame.workerZones or {}
			frame.workerZones[workerName] = frame.workerZones[workerName] or {}
			table.insert(frame.workerZones[workerName], zone)
		end
	end
end

function Profiler:GetLatestFrame()
	return self._frames[#self._frames]
end

function Profiler:GetFrames()
	return self._frames
end

function Profiler:GetCounters()
	return self._counters
end

return Profiler
