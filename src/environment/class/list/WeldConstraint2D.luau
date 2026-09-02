-- description: "A rigid 2D joint between two Body2D instances."
return {
	class = "WeldConstraint2D",
	callback = function(instance)
		instance:SetProperties({
			Name = "WeldConstraint2D",
			BaseClass = "Constraint2D",
			Body0 = nil,
			Body1 = nil,
			Enabled = true,
		})
		return instance
	end,
}
