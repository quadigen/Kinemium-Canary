local Instance = require("@Instance")
local Workspace = Instance.new("Workspace")
local Enum = require("@EnumMap")
local CFrame = require("@CFrame")
local argon = require("@argon")
local zembed = require("@zembed")

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
			local entries = {}

			if zembed.IsEmbedded() then
				local seen = {}
				for _, filePath in pairs(zembed.GetAssetFilesUnder(path)) do
					local materialName = filePath:gsub([[\]], "/"):match("^src/assets/materials/compressed/([^/]+)/albedo%.png$")
					if materialName and not seen[materialName] then
						seen[materialName] = true
						table.insert(entries, {
							kind = "directory",
							name = materialName,
						})
					end
				end
			else
				entries = zune.fs.entries(path)
			end

			for _, dir in pairs(entries) do
				if dir.kind ~= "directory" then
					continue
				end

				local albedo_tex = zembed.AssetPath(path .. `/{dir.name}/albedo.png`) -- assume pngs

				local ptr = argon:CreateMeshTexture(renderer.Window, albedo_tex)

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
				local materialTileScale = math.max(1, math.max(object.Size.X, object.Size.Y, object.Size.Z) / 4)

				renderer.MeshPool.DrawMesh({
					texture = material,
					MaterialKind = getMaterialKind(object.Material),
					MaterialTileScale = materialTileScale,
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
				materialTileScale = nil
			end
		end
	end)
end

return Workspace
