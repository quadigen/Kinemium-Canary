-- description: "A physics body in a World2D, independent from 3D BasePart behavior."
local Vector2 = require("@Vector2")

local propTable = {
	Name = "Body2D",
	BaseClass = "Body2D",
	Position = Vector2.new(0, 0),
	Size = Vector2.new(32, 32),
	Rotation = 0,
	LinearVelocity = Vector2.new(0, 0),
	AngularVelocity = 0,
	Anchored = false,
	Enabled = true,
	Visible = false,
	Density = 1,
	Friction = 0.3,
	Restitution = 0,
	IsSensor = false,
	CollisionLayer = "Default",
	CollisionMask = "Default",
	AbsolutePosition = Vector2.new(0, 0),
	AbsoluteSize = Vector2.new(32, 32),
}

local function syncAbsolute(instance)
	local size = instance.Size or Vector2.new(0, 0)
	local position = instance.Position or Vector2.new(0, 0)
	instance.AbsoluteSize = Vector2.new(size.X, size.Y)
	instance.AbsolutePosition = Vector2.new(position.X - size.X * 0.5, position.Y - size.Y * 0.5)
end

return {
	class = "Body2D",
	callback = function(instance)
		instance:SetProperties(propTable)
		syncAbsolute(instance)
		instance.Changed:Connect(function(property)
			if property == "Position" or property == "Size" then
				syncAbsolute(instance)
			end
		end)
		return instance
	end,
	inherit = function(target)
		for key, value in pairs(propTable) do
			target[key] = value
		end
	end,
}
