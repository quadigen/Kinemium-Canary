local SnapshotHistory = {}
SnapshotHistory.__index = SnapshotHistory

function SnapshotHistory.new(capacity)
	return setmetatable({ capacity = math.max(2, capacity or 64), order = {}, byTick = {} }, SnapshotHistory)
end

function SnapshotHistory:Push(tick, snapshot)
	if self.byTick[tick] == nil then
		table.insert(self.order, tick)
	end
	self.byTick[tick] = snapshot
	while #self.order > self.capacity do
		self.byTick[table.remove(self.order, 1)] = nil
	end
end

function SnapshotHistory:Get(tick)
	return self.byTick[tick]
end

function SnapshotHistory:Latest()
	local tick = self.order[#self.order]
	return tick, tick and self.byTick[tick] or nil
end

function SnapshotHistory:Clear()
	table.clear(self.order)
	table.clear(self.byTick)
end

return SnapshotHistory
