-- description: "Creates bloom for the environment, Parented under Lighting."
local Enum = require("@EnumMap")

local propTable = {
	Mode = Enum.KinemiumBloomMode.Mix,
	Levels = 0.5,
	Intensity = 0.05,
	Threshold = 0.6,
	SoftThreshold = 0.5,
	FilterRadius = 1.0,
	Resolution = 384,
	LensFlare = false,
	Enabled = true,
	Name = "BloomEffect",
	BaseClass = "LightingPreprocess",
}

return {
	class = "BloomEffect",
	callback = function(instance, renderer)
		local Argon = require("@Argon")

		instance:SetProperties(propTable)

		local function applyFilament()
			if not renderer or not renderer.Window then
				return
			end
			local active = instance.Enabled and instance.Parent ~= nil and instance.Parent:IsA("Lighting")
			local levels = if instance.Levels <= 1
				then math.round(1 + instance.Levels * 10)
				else math.round(instance.Levels)
			Argon:SetBloom(renderer.Window, active, {
				Strength = math.clamp(instance.Intensity, 0, 1),
				Levels = math.clamp(levels, 1, 11),
				Resolution = instance.Resolution,
				Threshold = instance.Threshold > 0,
				LensFlare = instance.LensFlare,
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
