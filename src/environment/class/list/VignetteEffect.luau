-- description: "Darkens or tints the edges of the rendered image."
local Color3 = require("@Color3")

local propTable = {
	Name = "VignetteEffect",
	BaseClass = "Kinemium.posteffect",
	Enabled = true,
	Intensity = 0.35,
	Roundness = 0.65,
	Feather = 0.55,
	Color = Color3.new(0, 0, 0),
}

return {
	class = "VignetteEffect",
	callback = function(instance, renderer)
		local Argon = require("@Argon")
		instance:SetProperties(propTable)

		local function apply()
			if not renderer or not renderer.Window then
				return
			end
			local active = instance.Enabled and instance.Parent ~= nil and instance.Parent:IsA("Lighting")
			local r, g, b = instance.Color:ToRGB()
			Argon:SetVignette(renderer.Window, active, {
				MidPoint = 1 - math.clamp(instance.Intensity, 0, 1),
				Roundness = math.clamp(instance.Roundness, 0, 1),
				Feather = math.clamp(instance.Feather, 0, 1),
				Color = { R = r, G = g, B = b, A = 1 },
			})
		end

		instance.Changed:Connect(apply)
		instance.AncestryChanged:Connect(apply)
		apply()
		return instance
	end,
	inherit = function(tble)
		for prop, val in pairs(propTable) do
			tble[prop] = val
		end
	end,
}
