local InterpolationBuffer = {}
InterpolationBuffer.__index = InterpolationBuffer

local function lerpState(a, b, alpha)
	local result = {}
	for key, value in pairs(a) do
		result[key] = value
	end
	for key, value in pairs(b) do
		local from = a[key]
		if type(from) == "number" and type(value) == "number" then
			result[key] = from + (value - from) * alpha
		elseif type(from) == "table" and from.Lerp and type(value) == "table" then
			result[key] = from:Lerp(value, alpha)
		elseif alpha >= 0.5 then
			result[key] = value
		end
	end
	return result
end

function InterpolationBuffer.new(options)
	options = options or {}
	return setmetatable({
		samples = {},
		maxSamples = options.maxSamples or 32,
		maxExtrapolationTicks = options.maxExtrapolationTicks or 3,
	}, InterpolationBuffer)
end

function InterpolationBuffer:Push(tick, state, reset)
	if reset then
		table.clear(self.samples)
	end
	local samples = self.samples
	for index, sample in ipairs(samples) do
		if sample.tick == tick then
			sample.state = state
			return
		end
		if tick < sample.tick then
			table.insert(samples, index, { tick = tick, state = state })
			return
		end
	end
	table.insert(samples, { tick = tick, state = state })
	while #samples > self.maxSamples do
		table.remove(samples, 1)
	end
end

function InterpolationBuffer:Sample(renderTick)
	local samples = self.samples
	if #samples == 0 then
		return nil
	end
	if renderTick <= samples[1].tick then
		return samples[1].state
	end
	for index = 2, #samples do
		local right = samples[index]
		if renderTick <= right.tick then
			local left = samples[index - 1]
			local span = math.max(1, right.tick - left.tick)
			return lerpState(left.state, right.state, math.clamp((renderTick - left.tick) / span, 0, 1))
		end
	end
	local last = samples[#samples]
	if renderTick - last.tick <= self.maxExtrapolationTicks then
		return last.state
	end
	return last.state
end

function InterpolationBuffer:Size()
	return #self.samples
end
function InterpolationBuffer:Clear()
	table.clear(self.samples)
end

return InterpolationBuffer
