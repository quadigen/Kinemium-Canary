-- description: "Creates a fog effect in Lighting."
local Color3 = require("@Color3")
local Enum = require("@EnumMap")

local propTable = {
	Mode = Enum.KinemiumFogMode.Linear, -- Linear, Exponential, Exponential2
	Color = Color3.new(0.7, 0.7, 0.7),
	Start = 1.0,
	End = 100.0,
	Density = 0.1,
	SkyAffect = 0.5,
	Enabled = true,
	Name = "FogEffect",
	BaseClass = "LightingPreprocess",
}

return {
	class = "FogEffect",

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
