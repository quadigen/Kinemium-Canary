-- description: "A camera dedicated to 2D world rendering."
local Vector2 = require("@Vector2")

local propTable = {
	Name = "Camera2D",
	Position = Vector2.new(0, 0),
	Zoom = 1,
	Rotation = 0,
	ViewportSize = Vector2.new(0, 0),
}

local function rotate(point, degrees)
	local angle = math.rad(degrees)
	local c, s = math.cos(angle), math.sin(angle)
	return Vector2.new(point.X * c - point.Y * s, point.X * s + point.Y * c)
end

return {
	class = "Camera2D",
	callback = function(instance)
		instance:SetProperties(propTable)

		function instance:WorldToViewportPoint(point)
			local center = self.ViewportSize * 0.5
			return center + rotate(point - self.Position, -self.Rotation) * math.max(self.Zoom, 0.0001)
		end

		function instance:ViewportToWorldPoint(point)
			local center = self.ViewportSize * 0.5
			return self.Position + rotate((point - center) / math.max(self.Zoom, 0.0001), self.Rotation)
		end

		return instance
	end,
}
