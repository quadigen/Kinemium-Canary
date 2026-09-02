local Instance = require("@Instance")
local Workspace = Instance.new("Workspace")
local Enum = require("@EnumMap")
local CFrame = require("@CFrame")
local argon = require("@Argon")
local zembed = require("@zembed")
local Vector3 = require("@Vector3")

export type KinemiumCFrame = typeof(CFrame.new())
Workspace._Intents = Enum.PluginIntents.Graphic

local materialTextures = {}
local displacedMaterials = {}

local materialHeightScales = {
	brick = 0.12,
	wood = 0.04,
}

Workspace.InitRenderer = function(renderer, signal, game)
	Workspace:SetProperties({
		Test = 1,
		MaterialMode = Enum.WorkspaceMaterialMode.Compressed,
		PhysicsEngine = Enum.PhysicsEngine.Default,
		Gravity = -9.81,
		GlobalWind = Vector3.new(0, 0, 0),
		CurrentCamera2D = nil,
	})

	function Workspace:Raycast(origin, direction, params)
		local physicsService = game:GetService("UnifiedPhysicsService")
		if not physicsService or not physicsService.Raycast then
			return nil
		end
		return physicsService.Raycast(origin, direction, params)
	end

	if IsHeadless == true then
		Workspace.MeshesPreset = {}
		return Workspace
	end

	local meshes = {
		cube = argon:CreateMesh(renderer.Window, "cube"),
		displacedCube = argon:CreateMesh(renderer.Window, "displacedCube"),
		sphere = argon:CreateMesh(renderer.Window, "sphere"),
	}
	Workspace.MeshesPreset = meshes

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

				local albedo_tex = path .. `/{dir.name}/albedo.png` -- assume pngs
				local normal_tex = path .. `/{dir.name}/normal.png`
				local orm_tex = path .. `/{dir.name}/orm.png`
				local height_tex = path .. `/{dir.name}/height.png`

				local ptr = argon:CreatePbrMeshTexture(
					renderer.Window,
					albedo_tex,
					normal_tex,
					orm_tex,
					height_tex,
					materialHeightScales[dir.name] or 0
				)

				materialTextures[material_index[dir.name]] = ptr
				if (materialHeightScales[dir.name] or 0) > 0 then
					displacedMaterials[material_index[dir.name]] = true
				end
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

	local function getMeshForShape(shape, material)
		if shape == Enum.PartType.Ball then
			return meshes.sphere
		end
		if displacedMaterials[material] then
			return meshes.displacedCube
		end
		return meshes.cube
	end

	local renderParts = {}
	local renderPartIndices = {}
	local metadataDirty = true
	local dynamicGroups = {}
	local dynamicPartState = {}
	local renderProperties = {
		Size = true,
		Color = true,
		Transparency = true,
		Metallic = true,
		Roughness = true,
		CastShadow = true,
		Material = true,
		Shape = true,
		MeshObject = true,
		_mesh = true,
		MeshScale = true,
	}
	local transformProperties = {
		CFrame = true,
		Position = true,
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
		metadataDirty = true
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
		metadataDirty = true
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
		if not renderPartIndices[object] then
			return
		end
		if transformProperties[property] then
			local state = dynamicPartState[object]
			if state and not state.dirty then
				state.dirty = true
				table.insert(state.group.dirtyUpdates, state)
			end
		elseif renderProperties[property] then
			metadataDirty = true
		end
	end)

	local function getRenderableMesh(object, props, material)
		if props.ClassName == "MeshPart" then
			local mesh = props._mesh
				or (props.MeshObject and (props.MeshObject._mesh or props.MeshObject._meshgenHandle))
			if mesh and mesh._handle then
				return mesh
			end
		end
		return getMeshForShape(props.Shape, material)
	end

	local function getRenderScale(props)
		local size = props.Size
		local meshScale = tonumber(props.MeshScale) or 1
		if props.ClassName == "MeshPart" and meshScale ~= 1 then
			return Vector3.new(size.X * meshScale, size.Y * meshScale, size.Z * meshScale)
		end
		return size
	end

	local function updateDrawCallTransform(drawCall, props)
		drawCall.matrix = nil
		drawCall.cframe = props.CFrame
		drawCall.scale = getRenderScale(props)
	end

	local function destroyDynamicGroups()
		for _, group in pairs(dynamicGroups) do
			if group.batch then
				renderer.MeshPool.DestroyInstanceBatch(group.batch)
			end
		end
		table.clear(dynamicGroups)
		table.clear(dynamicPartState)
	end

	local function fillDrawCall(drawCall, object, props)
		local size = props.Size
		local material = props.Material
		local isGlass = material == Enum.Material.Glass
		drawCall.texture = materialTextures[material]
		drawCall.MaterialKind = getMaterialKind(material)
		if isGlass then
			drawCall.roughness = math.clamp((props.Roughness or 0.5) * 0.2, 0.02, 0.18)
			drawCall.metallic = 1.52
			drawCall.MaterialTileScale = math.max(0.05, math.min(size.X, size.Y, size.Z) * 0.5)
			drawCall.transmission = 0.88 + math.clamp(props.Transparency or 0, 0, 1) * 0.12
		else
			drawCall.MaterialTileScale = math.max(1, math.max(size.X, size.Y, size.Z) / 4)
			drawCall.metallic = props.Metallic
			drawCall.roughness = props.Roughness
			drawCall.transmission = 0
		end
		drawCall.mesh = getRenderableMesh(object, props, material)
		updateDrawCallTransform(drawCall, props)
		drawCall.color = props.Color
		drawCall.transparency = props.Transparency
		-- Filament's depth-only shadow pass treats transmissive solids as opaque.
		-- Avoid the solid black shadow until transparent shadows are supported.
		drawCall.CastShadow = props.CastShadow and not isGlass
		drawCall.RecieveShadow = true
		drawCall.Culling = true
	end

	local function getRenderKey(object, props)
		local color = props.Color
		local material = props.Material
		local isGlass = material == Enum.Material.Glass
		local size = props.Size
		local texture = materialTextures[material]
		local mesh = getRenderableMesh(object, props, material)
		local materialParam3 = if isGlass
			then math.max(0.05, math.min(size.X, size.Y, size.Z) * 0.5)
			else math.max(1, math.max(size.X, size.Y, size.Z) / 4)
		return table.concat({
			tostring(mesh),
			tostring(texture),
			tostring(getMaterialKind(material)),
			tostring(color.R),
			tostring(color.G),
			tostring(color.B),
			tostring(props.Transparency),
			tostring(props.Metallic),
			tostring(props.Roughness),
			tostring(props.CastShadow),
			tostring(materialParam3),
		}, "|")
	end

	local function rebuildDynamicGroups()
		destroyDynamicGroups()

		for _, object in pairs(renderParts) do
			local props = rawget(object, "_props")
			if not props or (tonumber(props.Transparency) or 0) >= 1 then
				continue
			end

			local key = getRenderKey(object, props)
			local group = dynamicGroups[key]
			if not group then
				group = {
					drawCalls = {},
					parts = {},
					dirtyUpdates = {},
				}
				dynamicGroups[key] = group
			end

			local drawCall = {}
			fillDrawCall(drawCall, object, props)
			table.insert(group.drawCalls, drawCall)
			table.insert(group.parts, object)
			dynamicPartState[object] = {
				group = group,
				object = object,
				index = #group.parts - 1,
				dirty = false,
			}
		end

		for _, group in pairs(dynamicGroups) do
			group.batch = renderer.MeshPool.CreateInstanceBatch(group.drawCalls, #group.drawCalls)
		end

		metadataDirty = false
	end

	local function flushTransformUpdates()
		for _, group in pairs(dynamicGroups) do
			local updates = group.dirtyUpdates
			if group.batch and #updates > 0 then
				for i = 1, #updates do
					local state = updates[i]
					local props = rawget(state.object, "_props")
					if props then
						state.matrix = nil
						state.cframe = props.CFrame
						state.scale = props.Size
					end
				end
				renderer.MeshPool.UpdateInstanceTransforms(group.batch, updates, #updates)
				for i = 1, #updates do
					local state = updates[i]
					state.dirty = false
					state.cframe = nil
					state.scale = nil
				end
				table.clear(updates)
			end
		end
	end

	renderer.Hook.new("Renderstep", function()
		if metadataDirty then
			rebuildDynamicGroups()
		else
			flushTransformUpdates()
		end
	end)

	renderer.Hook.new("Shutdown", function()
		destroyDynamicGroups()
		descendantAdded:Disconnect()
		descendantRemoving:Disconnect()
		descendantChanged:Disconnect()
	end)
end

return Workspace
