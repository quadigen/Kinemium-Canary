-- description: "A distance-limited rope between two Attachment2D instances."
return {
	class = "RopeConstraint2D",
	callback = function(instance)
		instance:SetProperties({
			Name = "RopeConstraint2D",
			BaseClass = "Constraint2D",
			Attachment0 = nil,
			Attachment1 = nil,
			Length = 100,
			Stiffness = 0,
			Damping = 0.1,
			Enabled = true,
		})
		return instance
	end,
}
