local Instance = require("@Instance")
local Workspace = Instance.new("Workspace")
local Enum = require("@EnumMap")
local CFrame = require("@CFrame")
local argon = require("@argon")

export type KinemiumCFrame = typeof(CFrame.new())
Workspace._Intents = Enum.PluginIntents.Graphic

local materialTextures = {}

Workspace.InitRenderer = function(renderer, signal, game)
	Workspace:SetProperties({
		Test = 1,
		MaterialMode = Enum.WorkspaceMaterialMode.Compressed,
	})

	local meshes = {
		cube = argon:CreateMesh(renderer.Window, "cube"),
		sphere = argon:CreateMesh(renderer.Window, "sphere"),
		pyramid = argon:CreateMesh(renderer.Window, "pyramid"),
	}

	local material_index = {}

	for _, material in pairs(Enum.Material:GetEnumItems()) do
		material_index[material.Value] = material
	end

	local function fillMaterialTex(WorkspaceMaterialMode)
		if WorkspaceMaterialMode == Enum.WorkspaceMaterialMode.Compressed then
			local path = "./src/assets/materials/compressed"
			local entries = zune.fs.entries(path)
			for _, dir in pairs(entries) do
				if dir.kind ~= "directory" then
					continue
				end

				local albedo_tex = path .. `/{dir.name}/albedo.png` -- assume pngs

				local ptr = argon:CreateMeshTexture(renderer.Window, albedo_tex)
				print("loading " .. dir.name)
				print(ptr)

				materialTextures[material_index[dir.name]] = ptr
			end
		end
	end

	fillMaterialTex(Enum.WorkspaceMaterialMode.Compressed)

	local function getMaterialKind(materialEnum)
		if not materialEnum then
			return 0
		end
		if materialEnum == Enum.Material.Glass then
			return 1
		end
		if materialEnum == Enum.Material.Neon then
			return 2
		end
		if materialEnum == Enum.Material.Water then
			return 3
		end
		return 0
	end

	renderer.Hook.new("Renderstep", function()
		for _, object in pairs(Workspace:GetDescendants()) do
			if object:IsA("BasePart") then
				local matrix = object.CFrame:ToEngineMatrix(object.Size)
				local mesh = meshes.cube
				local material = materialTextures[object.Material]

				renderer.MeshPool.DrawMesh({
					texture = material,
					MaterialKind = getMaterialKind(object.Material),
					mesh = mesh,
					matrix = matrix,
					color = object.Color,
					transparency = object.Transparency,
					metallic = object.Metallic,
					roughness = object.Roughness,
					CastShadow = object.CastShadow,
					RecieveShadow = true,
					Culling = true,
				})
				matrix = nil
				mesh = nil
				material = nil
			end
		end
	end)
end

return Workspace
