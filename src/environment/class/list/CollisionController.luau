-- description: "Defines the collision shape and slope policy used by a character motor."
local Vector3 = require("@Vector3")

return {
	class = "CollisionController",
	callback = function(instance)
		instance:SetProperties({
			Name = "CollisionController",
			Enabled = true,
			Size = Vector3.new(2, 6, 2),
			Mass = 80,
			MaxSlopeAngle = 45,
			CollisionGroup = "Default",
			Padding = 0.02,
		})
		return instance
	end,
}
