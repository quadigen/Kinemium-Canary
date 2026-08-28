-- description: "Creates a Depth of Field effect in the Environment."
local propTable = {
	Mode = 1, -- R3D_DOF_ENABLED
	FocusPoint = 10.0,
	FocusScale = 1.0,
	MaxBlurSize = 20.0,
	MaxApertureDiameter = 0.02,
	Enabled = true,
	Name = "DOFEffect",
	BaseClass = "LightingPreprocess",
}

return {
	class = "DOFEffect",

	callback = function(instance, renderer)
		local Argon = require("@Argon")

		instance:SetProperties(propTable)

		local function applyFilament()
			if not renderer or not renderer.Window then
				return
			end
			local active = instance.Enabled and instance.Parent ~= nil and instance.Parent:IsA("Lighting")
			local blur = math.clamp(math.round(instance.MaxBlurSize), 0, 32)
			Argon:SetDepthOfField(renderer.Window, active, {
				FocusDistance = math.max(instance.FocusPoint, 0.001),
				CocScale = math.max(instance.FocusScale, 0),
				MaxApertureDiameter = instance.MaxApertureDiameter,
				MaxForegroundCOC = blur,
				MaxBackgroundCOC = blur,
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
