-- Coalesces native-constraint rebuilds and always crosses a scheduler boundary.
-- Some runtimes execute long chains of task.defer callbacks in one C call path;
-- constraints retrying before their replicated bodies exist could consequently
-- overflow the C stack and also spin hard enough to starve physics.
local ConstraintRetry = {}
local states = setmetatable({}, { __mode = "k" })

local function stateFor(owner)
	local state = states[owner]
	if not state then
		state = { generation = 0, pending = false, connections = {} }
		states[owner] = state
	end
	return state
end

function ConstraintRetry.Cancel(owner)
	local state = stateFor(owner)
	state.generation += 1
	state.pending = false
	for _, connection in ipairs(state.connections) do
		connection:Disconnect()
	end
	table.clear(state.connections)
end

function ConstraintRetry.Track(owner, connection)
	if connection then
		table.insert(stateFor(owner).connections, connection)
	end
	return connection
end

function ConstraintRetry.Schedule(owner, callback, delaySeconds)
	local state = stateFor(owner)
	if state.pending then
		return false
	end

	state.pending = true
	local generation = state.generation
	-- Zune may execute task.delay(0) in the current C callback chain. A burst of
	-- replicated property/ownership changes can then recursively rebuild hundreds
	-- of constraints and overflow the C stack. Always cross at least one scheduler
	-- slice, even when callers request an immediate rebuild.
	local delay = math.max(delaySeconds or 0.05, 0.001)
	task.delay(delay, function()
		if state.generation ~= generation then
			return
		end
		state.pending = false
		callback()
	end)
	return true
end

return ConstraintRetry
