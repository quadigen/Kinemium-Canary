-- description: "Renders a 3D Mesh in 3D Space."
local Vector3 = require("@Vector3")
local Part = require("@Part")
local Enum = require("@EnumMap")
local argon = require("@Argon")
local CFrame = require("@CFrame")

local propTable = {
	MeshObject = nil,
	MeshId = "",
	TextureID = "",
	TextureId = "",
	_showhitbox = false,
	CollisionFidelity = Enum.CollisionFidelity.Default,
	RenderFidelity = Enum.RenderFidelity.Automatic,
	CollisionScale = 1,
	_meshUsesPartSize = true,
	Anchored = true,
	Name = "MeshPart",
	BaseClass = "BasePart",
	MeshScale = 1,
	SkinningEnabled = true,
	CurrentAnimation = "",
	AnimationTime = 0,
	AnimationSpeed = 1,
	LoopAnimation = true,
	Transparency = 0,
	Size = Vector3.new(1, 1, 1),
}

Part.inherit(propTable)

return {
	class = "MeshPart",

	callback = function(instance, renderer, game)
		instance:SetProperties(propTable)
		Part.setupTouchSignals(instance, renderer)
		instance:SetMetadata("IsMovable", true)

		local KinemiumPhysicsService = game and game:GetService("UnifiedPhysicsService") or nil

		instance.ApplyImpulse = function(self, v)
			if KinemiumPhysicsService then
				return KinemiumPhysicsService.ApplyImpulse(instance, v)
			end
			return false
		end

		renderer.EventBus:Fire("UpdatePart", instance)

		local syncingTransform = false

		local ownedMeshObject = nil
		local ownedBones = {}
		local importedBones = {}
		local importedAnimations = {}
		local loadingMeshId = false
		local ownedTexture = nil
		local loadingTexture = false

		local function syncMeshObject(meshObject)
			instance._mesh = meshObject and (meshObject._mesh or meshObject._meshgenHandle) or nil
			instance._cpuMeshData = meshObject and meshObject._cpuMeshData or nil
			instance._materialHandle = meshObject and meshObject._materialHandle or nil
		end

		local function releaseOwnedMeshObject()
			if not ownedMeshObject then
				return
			end
			local previous = ownedMeshObject
			ownedMeshObject = nil
			if instance.MeshObject == previous then
				rawget(instance, "_props").MeshObject = nil
			end
			previous:Destroy()
		end

		local function releaseOwnedBones()
			for _, bone in ipairs(ownedBones) do
				if bone and bone.Parent ~= nil then
					bone:Destroy()
				end
			end
			table.clear(ownedBones)
			table.clear(importedBones)
			table.clear(importedAnimations)
		end

		local function matrixToCFrame(matrix)
			if type(matrix) ~= "table" or #matrix < 16 then
				return CFrame.new()
			end
			return CFrame.new(
				matrix[4],
				matrix[8],
				matrix[12],
				matrix[1],
				matrix[2],
				matrix[3],
				matrix[5],
				matrix[6],
				matrix[7],
				matrix[9],
				matrix[10],
				matrix[11]
			)
		end

		local function rebuildImportedBones(mesh)
			releaseOwnedBones()
			if not mesh or not argon.GetMeshSkeleton then
				return
			end
			local skeleton = argon:GetMeshSkeleton(mesh)
			if type(skeleton) ~= "table" or #skeleton == 0 then
				return
			end
			local Registry = require("@InstanceRegistry")
			for index, definition in ipairs(skeleton) do
				local bone = Registry.new("Bone", renderer, game)
				bone.Name = definition.name ~= "" and definition.name or ("Bone" .. tostring(index))
				bone.BoneId = definition.index
				bone.CFrame = matrixToCFrame(definition.bindTransform)
				bone.Transform = CFrame.new()
				bone._meshPartBone = true
				ownedBones[index] = bone
				importedBones[index] = {
					bone = bone,
					parentIndex = definition.parentIndex,
				}
			end
			for index, definition in ipairs(importedBones) do
				local parent = definition.parentIndex > 0 and ownedBones[definition.parentIndex] or instance
				ownedBones[index].Parent = parent or instance
			end
			if argon.GetMeshAnimations then
				importedAnimations = argon:GetMeshAnimations(mesh)
			end
		end

		local function releaseOwnedTexture()
			if ownedTexture and renderer and renderer.Window then
				argon:Destroy3DTexture(renderer.Window, ownedTexture)
			end
			ownedTexture = nil
			rawget(instance, "_props")._meshTexture = nil
		end

		local function loadTexture(textureId)
			if loadingTexture then
				return
			end
			loadingTexture = true
			releaseOwnedTexture()

			local path = type(textureId) == "string" and textureId or ""
			if path ~= "" and not _G.IsHeadless and renderer and renderer.Window then
				local ok, texture = pcall(argon.CreateMeshTexture, argon, renderer.Window, path)
				if ok and texture then
					ownedTexture = texture
					rawget(instance, "_props")._meshTexture = texture
				else
					warn(`MeshPart could not load texture "{path}"`)
				end
			end

			loadingTexture = false
			renderer.EventBus:Fire("UpdatePart", instance)
		end

		local function loadMeshId(meshId)
			if loadingMeshId then
				return
			end
			loadingMeshId = true
			releaseOwnedBones()
			releaseOwnedMeshObject()

			local path = type(meshId) == "string" and meshId or ""
			local cpuMeshData = nil
			if path ~= "" and argon.LoadMeshDataFromPath then
				local ok, result = pcall(argon.LoadMeshDataFromPath, argon, path)
				if ok then
					cpuMeshData = result
				end
			end
			rawget(instance, "_props")._cpuMeshData = cpuMeshData
			if path ~= "" and not _G.IsHeadless and renderer and renderer.Window then
				local ok, mesh = pcall(argon.CreateMeshFromPath, argon, renderer.Window, path)
				if ok and mesh and mesh._handle then
					local Registry = require("@InstanceRegistry")
					local meshObject = Registry.new("EditableMesh", renderer, game)
					mesh._window = renderer.Window
					meshObject.Name = instance.Name .. "Mesh"
					meshObject._mesh = mesh
					meshObject._meshgenHandle = mesh
					meshObject._sourcePath = path
					meshObject._cpuMeshData = cpuMeshData
					meshObject._geometryDirty = false
					ownedMeshObject = meshObject
					rawget(instance, "_props").MeshObject = meshObject
					syncMeshObject(meshObject)
					rebuildImportedBones(mesh)
				else
					warn(`MeshPart could not load mesh "{path}"`)
					syncMeshObject(nil)
				end
			else
				syncMeshObject(nil)
			end

			loadingMeshId = false
			renderer.EventBus:Fire("UpdatePart", instance)
		end

		local function findAnimation(animation)
			if type(animation) == "number" then
				return importedAnimations[math.floor(animation)]
			end
			if type(animation) ~= "string" then
				return nil
			end
			local wanted = string.lower(animation:gsub("\\", "/"):match("([^/]+)$") or animation):gsub("%.[^%.]+$", "")
			for _, clip in ipairs(importedAnimations) do
				local name = string.lower(clip.name or "")
				if name == string.lower(animation) or name == wanted or name:gsub("%.[^%.]+$", "") == wanted then
					return clip
				end
			end
			return nil
		end

		function instance:GetBones()
			local result = table.create(#ownedBones)
			for index, bone in ipairs(ownedBones) do
				result[index] = bone
			end
			return result
		end

		function instance:GetBoneByName(name: string)
			for _, bone in ipairs(ownedBones) do
				if bone.Name == name then
					return bone
				end
			end
			return nil
		end

		function instance:GetAnimationClips()
			local result = table.create(#importedAnimations)
			for index, clip in ipairs(importedAnimations) do
				result[index] = {
					Name = clip.name,
					Length = clip.duration,
					Index = index,
				}
			end
			return result
		end

		function instance:PlayAnimation(animation, looped: boolean?, speed: number?)
			local clip = findAnimation(animation)
			if not clip then
				return false
			end
			instance.CurrentAnimation = clip.name
			instance.AnimationTime = 0
			instance.LoopAnimation = looped ~= false
			instance.AnimationSpeed = type(speed) == "number" and speed or 1
			return true
		end

		function instance:StopAnimation()
			instance.CurrentAnimation = ""
			instance.AnimationTime = 0
		end

		function instance:ResetBoneTransforms()
			for _, bone in ipairs(ownedBones) do
				bone.Transform = CFrame.new()
			end
			instance:StopAnimation()
		end

		local function updateManualBonePose(mesh)
			if #importedBones == 0 or not argon.SetMeshBoneTransforms then
				return
			end
			local transforms = table.create(#importedBones)
			local states = table.create(#importedBones, 0)
			local function evaluate(index)
				if states[index] == 2 then
					return transforms[index]
				end
				if states[index] == 1 then
					return CFrame.new()
				end
				states[index] = 1
				local definition = importedBones[index]
				local bone = definition.bone
				local transformed = bone.CFrame * bone.Transform
				bone.TransformedCFrame = transformed
				local parentTransform = if definition.parentIndex > 0
					then evaluate(definition.parentIndex)
					else CFrame.new()
				local world = parentTransform * transformed
				transforms[index] = world
				bone.TransformedWorldCFrame = instance.CFrame * world
				states[index] = 2
				return world
			end
			for index = 1, #importedBones do
				evaluate(index)
			end
			argon:SetMeshBoneTransforms(renderer.Window, mesh, transforms)
		end

		local destroyed = false
		if renderer and renderer.Hook and renderer.Hook.new then
			renderer.Hook.new("Renderstep", function(dt)
				if destroyed or instance.SkinningEnabled == false then
					return
				end
				local mesh = instance._mesh
				if not mesh or not mesh._handle or #importedBones == 0 then
					return
				end
				local currentAnimation = instance.CurrentAnimation
				if currentAnimation ~= "" and argon.ApplyMeshAnimation then
					local newTime = (instance.AnimationTime or 0) + (dt or 0) * (instance.AnimationSpeed or 1)
					instance.AnimationTime = newTime
					if
						not argon:ApplyMeshAnimation(
							renderer.Window,
							mesh,
							currentAnimation,
							newTime,
							instance.LoopAnimation
						)
					then
						instance.CurrentAnimation = ""
					end
				else
					updateManualBonePose(mesh)
				end
			end)
		end

		local function syncFromCFrame(cf)
			if not cf or not cf.Position then
				return
			end
			local rx, ry, rz = cf:ToOrientation()
			local props = rawget(instance, "_props")
			if not props then
				return
			end
			props.Position = cf.Position
			props.Orientation = Vector3.new(rx, ry, rz)
			props.Rotation = props.Orientation
		end

		local function syncFromPosition(position)
			if not position then
				return
			end
			local props = rawget(instance, "_props")
			if not props or not props.CFrame then
				return
			end
			props.CFrame = props.CFrame:WithPosition(position)
		end

		if instance.MeshId ~= "" then
			loadMeshId(instance.MeshId)
		else
			syncMeshObject(instance.MeshObject)
		end
		if instance.TextureID ~= "" then
			loadTexture(instance.TextureID)
		elseif instance.TextureId ~= "" then
			loadTexture(instance.TextureId)
		end

		instance.Changed:Connect(function(property, value)
			if syncingTransform then
				return
			end
			if property == "CFrame" then
				syncingTransform = true
				syncFromCFrame(value)
				syncingTransform = false
			elseif property == "Position" then
				syncingTransform = true
				syncFromPosition(value)
				syncingTransform = false
			elseif property == "MeshObject" then
				if value ~= ownedMeshObject then
					releaseOwnedMeshObject()
				end
				syncMeshObject(value)
				renderer.EventBus:Fire("UpdatePart", instance)
			elseif property == "MeshId" then
				loadMeshId(value)
			elseif property == "TextureID" or property == "TextureId" then
				local props = rawget(instance, "_props")
				if property == "TextureID" then
					props.TextureId = value
				else
					props.TextureID = value
				end
				loadTexture(value)
			elseif
				property == "_mesh"
				or property == "_cpuMeshData"
				or property == "_meshUsesPartSize"
				or property == "Material"
			then
				renderer.EventBus:Fire("UpdatePart", instance)
			elseif property == "Parent" then
				renderer.EventBus:Fire("UpdatePart", instance)
			end
		end)

		instance.Destroying:Connect(function()
			destroyed = true
			releaseOwnedTexture()
			releaseOwnedBones()
			releaseOwnedMeshObject()
		end)

		return instance
	end,
	inherit = function()
		return propTable
	end,
}
