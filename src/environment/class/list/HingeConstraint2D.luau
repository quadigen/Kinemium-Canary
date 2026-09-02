-- description: "A rotational joint between two Attachment2D instances."
return {
	class = "HingeConstraint2D",
	callback = function(instance)
		instance:SetProperties({
			Name = "HingeConstraint2D",
			BaseClass = "Constraint2D",
			Attachment0 = nil,
			Attachment1 = nil,
			LimitsEnabled = false,
			LowerAngle = -180,
			UpperAngle = 180,
			Enabled = true,
		})
		return instance
	end,
}
