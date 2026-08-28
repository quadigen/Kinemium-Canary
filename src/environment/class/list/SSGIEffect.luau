-- description: "A real-time rendering effect that simulates bounced light by casting and sampling rays in screen space for indirect illumination."
local propTable = {
	SampleCount = 2,
	MaxRaySteps = 32,
	StepSize = 0.125,
	Thickness = 1.0,
	MaxDistance = 4.0,
	FadeStart = 8.0,
	FadeEnd = 16.0,
	DenoiseSteps = 5,
	Enabled = true,
	Name = "SSGIEffect",
	BaseClass = "LightingPreprocess",
}

return {
	class = "SSGIEffect",

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
