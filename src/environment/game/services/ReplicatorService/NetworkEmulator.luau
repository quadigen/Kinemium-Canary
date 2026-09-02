local NetworkEmulator = {}
NetworkEmulator.__index = NetworkEmulator

function NetworkEmulator.new(options)
	options = options or {}
	return setmetatable({
		latency = math.max(0, options.latency or 0),
		jitter = math.max(0, options.jitter or 0),
		loss = math.clamp(options.loss or 0, 0, 1),
		reorder = math.clamp(options.reorder or 0, 0, 1),
		queue = {},
		random = options.random or math.random,
	}, NetworkEmulator)
end

function NetworkEmulator:Send(value, reliable, now)
	if not reliable and self.random() < self.loss then
		return false
	end
	now = now or os.clock()
	local jitter = (self.random() * 2 - 1) * self.jitter
	local due = now + math.max(0, self.latency + jitter)
	if not reliable and self.random() < self.reorder then
		due += self.jitter * self.random()
	end
	table.insert(self.queue, { due = due, value = value })
	return true
end

function NetworkEmulator:Drain(now)
	now = now or os.clock()
	local ready = {}
	for index = #self.queue, 1, -1 do
		if self.queue[index].due <= now then
			table.insert(ready, table.remove(self.queue, index).value)
		end
	end
	return ready
end

return NetworkEmulator
