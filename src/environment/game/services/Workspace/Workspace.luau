local Instance = require("@Instance")
local Workspace = Instance.new("Workspace")
local Enum = require("@EnumMap")
local CFrame = require("@CFrame")
local argon = require("@argon")
local zembed = require("@zembed")
local Vector3 = require("@Vector3")

export type KinemiumCFrame = typeof(CFrame.new())
Workspace._Intents = Enum.PluginIntents.Graphic

local materialTextures = {}

Workspace.InitRenderer = function(renderer, signal, game)
	Workspace:SetProperties({
		Test = 1,
		MaterialMode = Enum.WorkspaceMaterialMode.Compressed,
		PhysicsEngine = Enum.PhysicsEngine.Default,
		Gravity = -9.81,
		GlobalWind = Vector3.new(0, 0, 0),
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
					local materialName =
						filePath:gsub([[\]], "/"):match("^src/assets/materials/compressed/([^/]+)/albedo%.png$")
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

	local renderParts = {}
	local renderPartIndices = {}
	local sceneVersion = 1
	local packedVersion = 0
	local renderProperties = {
		CFrame = true,
		Position = true,
		Size = true,
		Color = true,
		Transparency = true,
		Metallic = true,
		Roughness = true,
		CastShadow = true,
		Material = true,
	}

	local function isBasePart(object)
		local props = rawget(object, "_props")
		return props
			and (
				props.ClassName == "BasePart"
				or props.BaseClass == "BasePart"
				or rawget(object, "BaseClass") == "BasePart"
			)
	end

	local function addPart(object)
		if not isBasePart(object) or renderPartIndices[object] then
			return
		end
		table.insert(renderParts, object)
		renderPartIndices[object] = #renderParts
		sceneVersion += 1
	end

	local function removePart(object)
		local index = renderPartIndices[object]
		if not index then
			return
		end
		local last = renderParts[#renderParts]
		renderParts[index] = last
		renderParts[#renderParts] = nil
		renderPartIndices[object] = nil
		if last and last ~= object then
			renderPartIndices[last] = index
		end
		sceneVersion += 1
	end

	local function addTree(object)
		addPart(object)
		for _, descendant in pairs(object:GetDescendants()) do
			addPart(descendant)
		end
	end

	local function removeTree(object)
		removePart(object)
		for _, descendant in pairs(object:GetDescendants()) do
			removePart(descendant)
		end
	end

	for _, descendant in pairs(Workspace:GetDescendants()) do
		addPart(descendant)
	end
	local descendantAdded = Workspace.DescendantAdded:Connect(addTree)
	local descendantRemoving = Workspace.DescendantRemoving:Connect(removeTree)
	local descendantChanged = Workspace.DescendantChanged:Connect(function(object, property)
		if renderPartIndices[object] and renderProperties[property] then
			sceneVersion += 1
		end
	end)

	local partDrawList = {}
	renderer.Hook.new("Renderstep", function()
		local partCount = #renderParts
		if packedVersion ~= sceneVersion then
			for i = 1, partCount do
				local object = renderParts[i]
				local props = rawget(object, "_props")
				local drawCall = partDrawList[i]
				if not drawCall then
					drawCall = {}
					partDrawList[i] = drawCall
				end

				local size = props.Size
				local material = props.Material
				drawCall.texture = materialTextures[material]
				drawCall.MaterialKind = getMaterialKind(material)
				drawCall.MaterialTileScale = math.max(1, math.max(size.X, size.Y, size.Z) / 4)
				drawCall.mesh = meshes.cube
				drawCall.matrix = nil
				drawCall.cframe = props.CFrame
				drawCall.scale = size
				drawCall.color = props.Color
				drawCall.transparency = props.Transparency
				drawCall.metallic = props.Metallic
				drawCall.roughness = props.Roughness
				drawCall.CastShadow = props.CastShadow
				drawCall.RecieveShadow = true
				drawCall.Culling = true
			end

			for i = #partDrawList, partCount + 1, -1 do
				partDrawList[i] = nil
			end
			packedVersion = sceneVersion
		end
		renderer.MeshPool.DrawMeshList(partDrawList, partCount, 1, sceneVersion)
	end)

	renderer.Hook.new("Shutdown", function()
		descendantAdded:Disconnect()
		descendantRemoving:Disconnect()
		descendantChanged:Disconnect()
	end)
end

return Workspace
