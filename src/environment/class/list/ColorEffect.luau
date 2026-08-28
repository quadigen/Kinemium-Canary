-- description: "Creates a color effect for the Environment, Works if parented under Lighting."
local propTable = {
	Brightness = 0.0,
	Contrast = 1.0,
	Saturation = 1.0,
	Vibrance = 1.0,
	Temperature = 0.0,
	Tint = 0.0,
	Enabled = true,
	Name = "ColorEffect",
	BaseClass = "LightingPreprocess",
}

return {
	class = "ColorEffect",

	callback = function(instance, renderer)
		local Argon = require("@Argon")

		instance:SetProperties(propTable)

		local function applyFilament()
			if not renderer or not renderer.Window then
				return
			end
			local active = instance.Enabled and instance.Parent ~= nil and instance.Parent:IsA("Lighting")
			Argon:SetColorGrading(renderer.Window, {
				Enabled = active,
				Exposure = instance.Brightness,
				Contrast = math.max(instance.Contrast, 0.001),
				Saturation = math.max(instance.Saturation, 0),
				Vibrance = math.max(instance.Vibrance, 0),
				Temperature = math.clamp(instance.Temperature, -1, 1),
				Tint = math.clamp(instance.Tint, -1, 1),
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
