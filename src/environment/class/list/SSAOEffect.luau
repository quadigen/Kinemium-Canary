-- description: "A screen-space ambient occlusion effect that simulates soft shadows and depth"
local propTable = {
	SampleCount = 16,
	Intensity = 5,
	Power = 5,
	Radius = 1,
	Bias = 0.02,
	Type = "gtao",
	Enabled = true,
	Name = "SSAOEffect",
	BaseClass = "LightingPreprocess",
}

return {
	class = "SSAOEffect",

	callback = function(instance, renderer)
		local r3d = require("@r3d")
		local Argon = require("@Argon")

		instance:SetProperties(propTable)

		local envssao = r3d.structs.R3D_EnvSSAO:new({
			sampleCount = instance.SampleCount,
			intensity = instance.Intensity,
			power = instance.Power,
			radius = instance.Radius,
			bias = instance.Bias,
			enabled = instance.Enabled and 1 or 0,
		})
		instance:SetMetadata("EffectObject", envssao)

		local function applyFilament()
			if not renderer or not renderer.Window then
				return
			end
			local active = instance.Enabled and instance.Parent ~= nil and instance.Parent:IsA("Lighting")
			local quality = if instance.SampleCount <= 8 then "low" else if instance.SampleCount <= 16 then "medium" else "high"
			Argon:SetAmbientOcclusion(renderer.Window, active, {
				Type = instance.Type,
				Quality = quality,
				Radius = math.clamp(instance.Radius, 0.01, 10),
				Power = math.clamp(instance.Power, 0.01, 8),
				Intensity = math.clamp(instance.Intensity, 0, 4),
			})
		end

		instance.Changed:Connect(function(property, value)
			if property == "_r3deffect" then
				return
			end
			envssao = r3d.structs.R3D_EnvSSAO:new({
				sampleCount = instance.SampleCount,
				intensity = instance.Intensity,
				power = instance.Power,
				radius = instance.Radius,
				bias = instance.Bias,
				enabled = instance.Enabled and 1 or 0,
			})
			instance:SetMetadata("EffectObject", envssao)
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
