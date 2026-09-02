-- description: "A constraint that maintains a specific aspect ratio for a UI element."
local Enum = require("@EnumMap")

local propTable = {
	Name = "UIAspectRatioConstraint",
	BaseClass = "Kinemium.uimodifier",

	AspectRatio = 1,
	AspectType = Enum.AspectType.ScaleWithParentSize,
	DominantAxis = Enum.DominantAxis.Width,
}

return {
	class = "UIAspectRatioConstraint",
	callback = function(instance)
		instance:SetProperties(propTable)

		return instance
	end,
	inherit = function(tble)
		for prop, val in pairs(propTable) do
			tble[prop] = val
		end
	end,
}
