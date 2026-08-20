local Color3 = require("@Color3")

local pi = math.pi
local exp = math.exp
local sin = math.sin
local cos = math.cos
local sqrt = math.sqrt

local EPS = 1e-5
local DONE_EPS = 1e-3

------------------------------------------------
-- scalar spring
------------------------------------------------
local function newScalar(d, f, p)
	return {
		d = d,
		f = f * 2 * pi,
		p = p,
		g = p,
		v = 0,
	}
end

local function stepScalar(s, dt)
	local d, f = s.d, s.f
	local p, g, v = s.p, s.g, s.v
	local o = p - g

	if d == 1 then
		local q = exp(-f * dt)
		local w = dt * q
		p = o * (q + w * f) + v * w + g
		v = v * (q - w * f) - o * (w * f * f)
	elseif d < 1 then
		local c = sqrt(1 - d * d)
		local q = exp(-d * f * dt)
		local i = cos(f * c * dt)
		local j = sin(f * c * dt)
		local z = (c > EPS) and (j / c) or dt * f
		local y = (f * c > EPS) and (j / (f * c)) or dt
		p = (o * (i + z * d) + v * y) * q + g
		v = (v * (i - z * d) - o * (z * f)) * q
	else
		local c = sqrt(d * d - 1)
		local r1 = -f * (d + c)
		local r2 = -f * (d - c)
		local co2 = (v - o * r1) / (2 * f * c)
		local co1 = o - co2
		p = co1 * exp(r1 * dt) + co2 * exp(r2 * dt) + g
		v = co1 * r1 * exp(r1 * dt) + co2 * r2 * exp(r2 * dt)
	end

	s.p = p
	s.v = v
	return p, math.abs(o) < DONE_EPS and math.abs(v) < DONE_EPS
end

------------------------------------------------
-- Spring class
------------------------------------------------
local Spring = {}
Spring.__index = Spring

function Spring.new(damping, frequency)
	return setmetatable({
		d = damping,
		f = frequency,
		objects = {}, -- [object] = { springs }
	}, Spring)
end

------------------------------------------------
-- spring:target(object, goals)
------------------------------------------------
function Spring:target(obj, goals)
	local entry = self.objects[obj]
	if not entry then
		entry = {}
		self.objects[obj] = entry
	end

	for key, goal in pairs(goals) do
		local value = obj[key]
		local s = entry[key]

		-- number
		if type(value) == "number" then
			if not s then
				s = newScalar(self.d, self.f, value)
				entry[key] = s
			end
			s.g = goal

		-- Color3
		elseif type(value) == "table" and value.R then
			if not s then
				s = {
					__color = true,
					r = newScalar(self.d, self.f, value.R),
					g = newScalar(self.d, self.f, value.G),
					b = newScalar(self.d, self.f, value.B),
				}
				entry[key] = s
			end
			s.r.g = goal.R
			s.g.g = goal.G
			s.b.g = goal.B
		else
			error("Unsupported spring target: " .. tostring(key))
		end
	end
end

------------------------------------------------
-- spring:step(dt)
------------------------------------------------
function Spring:step(dt)
	for obj, entry in pairs(self.objects) do
		for key, s in pairs(entry) do
			if s.__color then
				local r = stepScalar(s.r, dt)
				local g = stepScalar(s.g, dt)
				local b = stepScalar(s.b, dt)
				obj[key] = Color3.new(r, g, b)
			else
				obj[key] = stepScalar(s, dt)
			end
		end
	end
end

function Spring:Get(key)
	return self.values[key]
end

return Spring
