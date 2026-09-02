-- description: "A rectangular collision shape for a Body2D."
local Vector2 = require("@Vector2")

return {
	class = "BoxCollider2D",
	callback = function(instance)
		instance:SetProperties({
			Name = "BoxCollider2D",
			BaseClass = "Collider2D",
			Size = Vector2.new(32, 32),
			Offset = Vector2.new(0, 0),
			Rotation = 0,
			Enabled = true,
			IsSensor = false,
			Density = 1,
			Friction = 0.3,
			Restitution = 0,
		})
		return instance
	end,
}
