-- description: "A convex polygon collision shape for a Body2D."
local Vector2 = require("@Vector2")

return {
	class = "PolygonCollider2D",
	callback = function(instance)
		instance:SetProperties({
			Name = "PolygonCollider2D",
			BaseClass = "Collider2D",
			Points = {},
			Offset = Vector2.new(0, 0),
			Rotation = 0,
			Enabled = true,
			IsSensor = false,
			Density = 1,
			Friction = 0.3,
			Restitution = 0,
		})
		instance.Points = {}
		return instance
	end,
}
