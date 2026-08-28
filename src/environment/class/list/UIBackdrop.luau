-- description: "A modifier class that blurs the scene behind a GUI element."
local Color3 = require("@Color3")

local propTable = {
	Blur = 12,
	Transparency = 0,
	TintColor = Color3.new(1, 1, 1),
	TintTransparency = 1,
	Enabled = true,
	Name = "UIBackdrop",
	BaseClass = "Kinemium.uimodifier",
}

return {
	class = "UIBackdrop",
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
