-- description: "A rendering technique that simulates reflections using screen-space ray marching."
local propTable = {
	MaxRaySteps = 64,
	BinarySteps = 5,
	StepSize = 0.125,
	Thickness = 1.0,
	Bias = 0.01,
	MaxDistance = 100.0,
	EdgeFade = 0.1,
	Enabled = true,
	Name = "SSREffect",
	BaseClass = "LightingPreprocess",
}

return {
	class = "SSREffect",

	callback = function(instance, renderer)
		local Argon = require("@Argon")

		instance:SetProperties(propTable)

		local function applyFilament()
			if not renderer or not renderer.Window then
				return
			end
			local active = instance.Enabled and instance.Parent ~= nil and instance.Parent:IsA("Lighting")
			Argon:SetScreenSpaceReflections(renderer.Window, active, {
				Thickness = math.max(instance.Thickness, 0),
				Bias = instance.Bias,
				MaxDistance = math.max(instance.MaxDistance, 0),
				Stride = math.max(instance.StepSize, 0.001),
			})
		end

		instance.Changed:Connect(function(property, value)
			applyFilament()
		end)
		instance.AncestryChanged:Connect(applyFilament)
		applyFilament()

		return instance
	end,
	inherit = function(tble)
		for prop, val in pairs(propTable) do
			tble[prop] = val
		end
	end,
}
