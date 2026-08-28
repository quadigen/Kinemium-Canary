-- description: "Creates an outline around a 3d object."
local Color3 = require("@Color3")

local propTable = {
	Adornee = nil,
	Color3 = Color3.new(0.0666667, 0.611765, 0.941176),
	LineThickness = 3,
	SurfaceColor3 = Color3.new(0.0666667, 0.611765, 0.941176),
	SurfaceTransparency = 1,
	Transparency = 0,
	Visible = true,
	Name = "SelectionBox",
}
local argon = require("@Argon")

return {
	class = "SelectionBox",

	callback = function(instance, renderer, game)
		instance:SetProperties(propTable)

		local cube

		local MeshesPreset = game:GetService("Workspace").MeshesPreset
		if MeshesPreset then
			cube = MeshesPreset.cube
		end

		renderer.Pool.new("3d", function()
			local adornee = instance.Adornee
			if adornee and cube then
				local mat4 = adornee.CFrame and adornee.CFrame:ToEngineMatrix(adornee.Size)
				argon:DrawMeshOutline(
					renderer.Window,
					cube,
					{ R = instance.Color3.R, G = instance.Color3.G, B = instance.Color3.B, A = 0 },
					instance.LineThickness,
					mat4
				)
			end
		end)

		return instance
	end,
	inherit = function(tble)
		for prop, val in pairs(propTable) do
			tble[prop] = val
		end
	end,
}
