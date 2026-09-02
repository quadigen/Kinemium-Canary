-- description: "A circular collision shape for a Body2D."
local Vector2 = require("@Vector2")

return {
	class = "CircleCollider2D",
	callback = function(instance)
		instance:SetProperties({
			Name = "CircleCollider2D",
			BaseClass = "Collider2D",
			Radius = 16,
			Offset = Vector2.new(0, 0),
			Enabled = true,
			IsSensor = false,
			Density = 1,
			Friction = 0.3,
			Restitution = 0,
		})
		return instance
	end,
}
