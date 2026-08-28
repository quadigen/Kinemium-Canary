-- description: "A rendering effect that simulates indirect diffuse lighting using screen-space sampling."
local propTable = {
	SampleCount = 16,
	SliceCount = 6,
	Radius = 1.0,
	Thickness = 1.0,
	Intensity = 1.0,
	AOPower = 1.0,
	DenoiseSteps = 5,
	Enabled = true,
	Name = "SSILEffect",
	BaseClass = "LightingPreprocess",
}

return {
	class = "SSILEffect",

	callback = function(instance)
		instance:SetProperties(propTable)

		instance.Changed:Connect(function(property, value) end)

		return instance
	end,
	inherit = function(tble)
		for prop, val in pairs(propTable) do
			tble[prop] = val
		end
	end,
}
