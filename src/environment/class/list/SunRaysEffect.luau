-- description: "A post-processing effect that simulates sunlight rays or god rays."
local propTable = {
	Name = "SunRaysEffect",
	BaseClass = "Kinemium.posteffect",

	Enabled = true,
	Intensity = 0.25,
	Spread = 0.1,
}

return {
	class = "SunRaysEffect",
	callback = function(instance, renderer, datamodel)
		instance:SetProperties(propTable)

		local Argon = require("@Argon")
		local function apply()
			if not renderer or not renderer.Window then
				return
			end

			local lighting = datamodel and datamodel:FindFirstChild("Lighting")
			local isActive = instance.Parent == lighting and instance.Enabled
			local intensity = math.clamp(instance.Intensity, 0, 1)
			local spread = math.clamp(instance.Spread, 0.01, 1)
			Argon:SetSunRays(renderer.Window, isActive, {
				Density = 0.006 + intensity * 0.04,
				MaximumOpacity = 0.2 + intensity * 0.75,
				InScatteringSize = 4 / spread,
			})
		end

		instance.Changed:Connect(function(property)
			if property == "Enabled" or property == "Intensity" or property == "Spread" or property == "Parent" then
				apply()
			end
		end)
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
