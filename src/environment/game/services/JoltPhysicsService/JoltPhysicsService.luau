-- devcell
local Instance = require("@Instance")
local Vector3 = require("@Vector3")
local CFrame = require("@CFrame")
local ffi = zune.ffi
local jolt = require("@jolt")
local lib = jolt.lib
local Enum = require("@EnumMap")
local structs = jolt.structs
local bodyMaker = require("@_BodyMaker")
local RaycastResult = require("@RaycastResult")
local NetworkOwnership = require("@NetworkOwnership")

local KinemiumPhysicsService = Instance.new("KinemiumPhysicsService")
KinemiumPhysicsService.ExplorerHidden = true
KinemiumPhysicsService._Intents = Enum.PluginIntents.Physics

local bodiesMap = {} -- Part -> BodyID (uint32)
local movingBodiesMap = {} -- Part -> BodyID for locally authoritative dynamic bodies
local softBodiesMap = {} -- SoftBody -> BodyID (uint32)
local softBodyStates = {} -- SoftBody -> { vIds = {number} }
local bodyPointerMap = {} -- Part -> BodyPointer (ffi.pointer)
local inverseMap = {} -- BodyID -> Part
local bodyConnections = {} -- Part -> RBXScriptConnection
local bodyTransformDirty = {} -- Part -> boolean
local partsByNetworkId = {}
local physicsDatamodel = nil

local gravityBuffer = ffi.alloc(structs.JPH_Vec3:size(), structs.JPH_Vec3:alignment())
local tempBodyPosition = ffi.alloc(structs.JPH_RVec3:size(), structs.JPH_RVec3:alignment())
local tempBodyRotation = ffi.alloc(structs.JPH_Quat:size(), structs.JPH_Quat:alignment())
local tempBodyLinear = ffi.alloc(structs.JPH_Vec3:size(), structs.JPH_Vec3:alignment())
local tempBodyAngular = ffi.alloc(structs.JPH_Vec3:size(), structs.JPH_Vec3:alignment())
local tempCharacterVelocity = ffi.alloc(structs.JPH_Vec3:size(), structs.JPH_Vec3:alignment())
local tempCharacterGravity = ffi.alloc(structs.JPH_Vec3:size(), structs.JPH_Vec3:alignment())
local tempCharacterPosition = ffi.alloc(structs.JPH_RVec3:size(), structs.JPH_RVec3:alignment())
local tempCharacterOutputVelocity = ffi.alloc(structs.JPH_Vec3:size(), structs.JPH_Vec3:alignment())

local terrainBodies = {} -- chunkKey -> BodyID
local terrainBodyMaterials = {} -- BodyID -> dominant terrain material

local collisionGroups = {
	[0] = { name = "Default", collidesWith = {} },
}
local groupNameToId = { ["Default"] = 0 }

for i = 0, 31 do
	if not collisionGroups[i] then
		collisionGroups[i] = { name = "", collidesWith = {} }
	end
	for j = 0, 31 do
		collisionGroups[i].collidesWith[j] = true
	end
end

local NUM_OBJECT_LAYERS = 128

local function RegisterCollisionGroup(name)
	if type(name) ~= "string" then
		return 0
	end
	if groupNameToId[name] then
		return groupNameToId[name]
	end
	for i = 1, 31 do
		if collisionGroups[i].name == "" then
			collisionGroups[i].name = name
			groupNameToId[name] = i
			return i
		end
	end
	warn("Maximum number of collision groups (32) reached.")
	return 0
end

local function GetCollisionGroupId(name)
	return groupNameToId[name] or 0
end

local function getLayerForPart(part)
	local cgName = part.CollisionGroup or "Default"
	local cgId = GetCollisionGroupId(cgName)

	local motionState = 0
	if part.CanCollide then
		motionState = part.Anchored and 0 or 1
	else
		motionState = part.Anchored and 2 or 3
	end
	return (cgId * 4) + motionState
end

local function indexPart(part)
	local networkId = part and part.NetworkId
	if networkId ~= nil then
		partsByNetworkId[networkId] = part
	end
end

local function unindexPart(part)
	local networkId = part and part.NetworkId
	if networkId ~= nil and partsByNetworkId[networkId] == part then
		partsByNetworkId[networkId] = nil
	end
end

local function trackBodyMotion(part, bodyID, motionType)
	if motionType == 2 then
		movingBodiesMap[part] = bodyID
	else
		movingBodiesMap[part] = nil
	end
end

local function updatePhysicalProps(part)
	local bodyID = bodiesMap[part]
	local bodyPtr = bodyPointerMap[part]
	if not bodyID or not bodyPtr then
		return
	end

	local physicalProperties = part.CustomPhysicalProperties
	if physicalProperties.Friction then
		jolt.lib.JPH_Body_SetFriction(bodyPtr, physicalProperties.Friction)
	end
	if part.Mass then
		local motionProps = jolt.lib.JPH_Body_GetMotionProperties(bodyPtr)
		jolt.lib.JPH_MotionProperties_ScaleToMass(motionProps, part.Mass)
	end
end

local reusableJoltVec3 = { x = 0, y = 0, z = 0 }
local function ToJoltVec3(vec3)
	reusableJoltVec3.x = vec3.X
	reusableJoltVec3.y = vec3.Y
	reusableJoltVec3.z = vec3.Z
	return reusableJoltVec3
end

local function RVec3(x, y, z)
	local vec = structs.JPH_RVec3:new({})
	buffer.writef64(vec, 0, x)
	buffer.writef64(vec, 8, y)
	buffer.writef64(vec, 16, z)
	return vec
end

local function FromJoltVec3(jvec)
	return Vector3.new(jvec.x, jvec.y, jvec.z)
end

local function syncBodyTransformFromPart(part, bodyInterface, bodyID)
	if not part.CFrame or not part.CFrame.Position then
		return false
	end

	local pos_rvec = tempBodyPosition
	pos_rvec:writef64(0, part.CFrame.Position.X)
	pos_rvec:writef64(8, part.CFrame.Position.Y)
	pos_rvec:writef64(16, part.CFrame.Position.Z)

	local rot_quat = tempBodyRotation
	local x, y, z, w = part.CFrame:ToQuaternion()
	rot_quat:writef32(0, x)
	rot_quat:writef32(4, y)
	rot_quat:writef32(8, z)
	rot_quat:writef32(12, w)

	if lib.JPH_BodyInterface_SetPositionAndRotation then
		lib.JPH_BodyInterface_SetPositionAndRotation(bodyInterface, bodyID, pos_rvec, rot_quat, 1)
	else
		lib.JPH_BodyInterface_SetPosition(bodyInterface, bodyID, pos_rvec, 1)
		lib.JPH_BodyInterface_SetRotation(bodyInterface, bodyID, rot_quat, 1)
	end

	local linear = part.AssemblyLinearVelocity or Vector3.zero
	local angular = part.AssemblyAngularVelocity or Vector3.zero
	tempBodyLinear:writef32(0, linear.X)
	tempBodyLinear:writef32(4, linear.Y)
	tempBodyLinear:writef32(8, linear.Z)

	lib.JPH_BodyInterface_SetLinearVelocity(bodyInterface, bodyID, tempBodyLinear)
	if lib.JPH_BodyInterface_SetAngularVelocity then
		tempBodyAngular:writef32(0, angular.X)
		tempBodyAngular:writef32(4, angular.Y)
		tempBodyAngular:writef32(8, angular.Z)
		lib.JPH_BodyInterface_SetAngularVelocity(bodyInterface, bodyID, tempBodyAngular)
	end

	return true
end

local function _CFrameToJolt(cf)
	return {
		pos = ToJoltVec3(cf.Position),
		rot = { x = 0, y = 0, z = 0, w = 1 }, -- Identity quaternion
	}
end

local function _debugBody(bodyInterface, bodyID, partName)
	local isActive = lib.JPH_BodyInterface_IsActive(bodyInterface, bodyID)
	local isAdded = lib.JPH_BodyInterface_IsAdded(bodyInterface, bodyID)

	local position = ffi.alloc(structs.JPH_RVec3:size(), structs.JPH_RVec3:alignment())
	lib.JPH_BodyInterface_GetPosition(bodyInterface, bodyID, position)

	local posX = position:readf64(0)
	local posY = position:readf64(8)
	local posZ = position:readf64(16)

	log(
		string.format(
			"[Physics Debug] %s: Active=%s, Added=%s, Pos=(%.2f, %.2f, %.2f)",
			partName,
			tostring(isActive == 1),
			tostring(isAdded == 1),
			posX,
			posY,
			posZ
		)
	)
end

local function getMotionTypeForPart(part)
	if part.Anchored then
		if part.IsKinematic then
			return 1
		end
		return 0
	end
	if NetworkOwnership.ShouldSimulatePartForMachine(part, physicsDatamodel) then
		return 2
	else
		-- Remote dynamic bodies remain collision/query proxies, but snapshots
		-- drive their transforms and the local solver never integrates them.
		return 1
	end
end

local function shouldHavePhysicsBody(part)
	return not (
		part.Anchored == true
		and part.CanCollide == false
		and part.CanQuery == false
		and part.IsKinematic ~= true
	)
end

local function getMeshPartGeometry(part)
	local mesh = part.MeshObject
	if not mesh or (mesh.ClassName ~= "EditableMesh" and mesh.class ~= "EditableMesh") then
		return nil
	end

	local vertexIds = {}
	for id in pairs(mesh._vertices or {}) do
		table.insert(vertexIds, id)
	end
	if #vertexIds < 3 then
		return nil
	end

	table.sort(vertexIds)

	local points = {}
	local vertexIndex = {}
	local meshScale = part.MeshScale or 1
	local collisionScale = part.CollisionScale or 1
	local sx = part.Size.X * meshScale * collisionScale
	local sy = part.Size.Y * meshScale * collisionScale
	local sz = part.Size.Z * meshScale * collisionScale

	for index, vertexId in ipairs(vertexIds) do
		local position = mesh._vertices[vertexId]
		if position then
			points[index] = {
				position.X * sx,
				position.Y * sy,
				position.Z * sz,
			}
			vertexIndex[vertexId] = index - 1
		end
	end

	local triangles = {}
	for _, face in pairs(mesh._faces or {}) do
		local i0 = vertexIndex[face[1]]
		local i1 = vertexIndex[face[2]]
		local i2 = vertexIndex[face[3]]
		if i0 ~= nil and i1 ~= nil and i2 ~= nil then
			table.insert(triangles, { i0, i1, i2 })
		end
	end

	if #triangles == 0 then
		return nil
	end

	return points, triangles
end

local function buildDynamicMeshFallbackShape(part, halfSize, convexRadius)
	local size = part.Size or Vector3.new(1, 1, 1)
	local minSize = math.min(size.X, size.Y, size.Z)
	local maxSize = math.max(size.X, size.Y, size.Z)

	if minSize > 0 and (maxSize / minSize) <= 1.1 then
		return lib.JPH_SphereShape_Create(minSize * 0.5)
	end

	return lib.JPH_BoxShape_Create(halfSize, convexRadius)
end

local function buildShapeForPart(part, halfSize, motionType)
	local convexRadius = math.min(0.05, math.min(part.Size.X, part.Size.Y, part.Size.Z) * 0.1)

	if part:IsA("MeshPart") then
		local geometryPoints, geometryTriangles = getMeshPartGeometry(part)
		if geometryPoints and geometryTriangles and part.CollisionFidelity ~= Enum.CollisionFidelity.Box then
			if part.CollisionFidelity == Enum.CollisionFidelity.Hull then
				if #geometryPoints >= 4 then
					local hullShape = bodyMaker.convexHullShape(geometryPoints, convexRadius)
					if hullShape ~= ffi.null then
						return hullShape
					end
				end
				warn("[Physics] Convex hull creation failed for", part.Name, "- falling back to primitive shape")
				return buildDynamicMeshFallbackShape(part, halfSize, convexRadius)
			elseif motionType == 2 then
				return buildDynamicMeshFallbackShape(part, halfSize, convexRadius)
			else
				local meshShape = bodyMaker.meshShape(geometryPoints, geometryTriangles)
				if meshShape ~= ffi.null then
					return meshShape
				end
			end
		end
	end

	if part.Shape == Enum.PartType.Block then
		return lib.JPH_BoxShape_Create(halfSize, convexRadius)
	elseif part.Shape == Enum.PartType.Ball then
		local radius = part.Size.X * 0.5
		return lib.JPH_SphereShape_Create(radius)
	end

	return lib.JPH_BoxShape_Create(halfSize, 0.05)
end

local function updateBodyShape(part, bodyInterface, bodyID)
	local halfSize = ffi.alloc(structs.JPH_Vec3:size(), structs.JPH_Vec3:alignment())
	halfSize:writef32(0, part.Size.X / 2)
	halfSize:writef32(4, part.Size.Y / 2)
	halfSize:writef32(8, part.Size.Z / 2)

	local newShape = buildShapeForPart(part, halfSize, getMotionTypeForPart(part))
	if not newShape or newShape == ffi.null then
		warn("[Physics] Failed to build shape for", part.Name)
		return false
	end

	lib.JPH_BodyInterface_SetShape(bodyInterface, bodyID, newShape, 1, 1)
	return true
end

local function createBody(bodyInterface, part, motionType)
	local halfSize = ffi.alloc(structs.JPH_Vec3:size(), structs.JPH_Vec3:alignment())
	halfSize:writef32(0, part.Size.X / 2)
	halfSize:writef32(4, part.Size.Y / 2)
	halfSize:writef32(8, part.Size.Z / 2)

	local shape = buildShapeForPart(part, halfSize, motionType)
	if not shape or shape == ffi.null then
		warn("[Physics] Failed to build shape for", part.Name)
		return
	end

	if not part.CFrame then
		return
	end

	part.Position = part.CFrame.Position
	if not part.Position then
		return
	end

	local position = ffi.alloc(structs.JPH_RVec3:size(), structs.JPH_RVec3:alignment())
	position:writef64(0, part.Position.X)
	position:writef64(8, part.Position.Y)
	position:writef64(16, part.Position.Z)

	local rotation = ffi.alloc(structs.JPH_Quat:size(), structs.JPH_Quat:alignment())
	local rotX, rotY, rotZ, rotW = part.CFrame:ToQuaternion()
	rotation:writef32(0, rotX)
	rotation:writef32(4, rotY)
	rotation:writef32(8, rotZ)
	rotation:writef32(12, rotW)

	local layer = getLayerForPart(part)

	local bodySettings = lib.JPH_BodyCreationSettings_Create3(shape, position, rotation, motionType, layer)
	lib.JPH_BodyCreationSettings_SetAllowSleeping(bodySettings, 1)

	lib.JPH_BodyCreationSettings_SetAllowDynamicOrKinematic(bodySettings, 1)

	local bodyPtr = lib.JPH_BodyInterface_CreateBody(bodyInterface, bodySettings)
	if bodyPtr == ffi.null then
		warn("[Physics] Failed to create body pointer for", part.Name)
		lib.JPH_BodyCreationSettings_Destroy(bodySettings)
		return
	end

	local bodyID = lib.JPH_Body_GetID(bodyPtr)
	local activation = (motionType == 2) and 0 or 1 -- JPH_Activation_Activate = 0, JPH_Activation_DontActivate = 1

	lib.JPH_BodyInterface_AddBody(bodyInterface, bodyID, activation)

	lib.JPH_BodyCreationSettings_Destroy(bodySettings)

	bodiesMap[part] = bodyID
	bodyPointerMap[part] = bodyPtr
	inverseMap[bodyID] = part
	bodyTransformDirty[part] = nil
	trackBodyMotion(part, bodyID, motionType)

	--debugBody(bodyInterface, bodyID, part.Name)
	return bodyID
end

local function CalculateBodyPhysics(part, bodyInterface, bodyID, assumeActive)
	if part.Anchored then
		return
	end
	if not assumeActive and lib.JPH_BodyInterface_IsActive(bodyInterface, bodyID) == 0 then
		return
	end

	local position = tempBodyPosition
	local rotation = tempBodyRotation

	lib.JPH_BodyInterface_GetPositionAndRotation(bodyInterface, bodyID, position, rotation)

	local posX = position:readf64(0)
	local posY = position:readf64(8)
	local posZ = position:readf64(16)

	local velocity = tempBodyLinear
	local angular_vel = tempBodyAngular

	lib.JPH_BodyInterface_GetLinearVelocity(bodyInterface, bodyID, velocity)
	lib.JPH_BodyInterface_GetAngularVelocity(bodyInterface, bodyID, angular_vel)

	local velX = velocity:readf32(0)
	local velY = velocity:readf32(4)
	local velZ = velocity:readf32(8)

	local angvelX = angular_vel:readf32(0)
	local angvelY = angular_vel:readf32(4)
	local angvelZ = angular_vel:readf32(8)

	local qx = rotation:readf32(0)
	local qy = rotation:readf32(4)
	local qz = rotation:readf32(8)
	local qw = rotation:readf32(12)

	local qlen = qx * qx + qy * qy + qz * qz + qw * qw
	if qlen > 1e-12 and math.abs(qlen - 1) > 1e-6 then
		local invLen = 1 / math.sqrt(qlen)
		qx, qy, qz, qw = qx * invLen, qy * invLen, qz * invLen, qw * invLen
	end

	local xx, yy, zz = qx * qx, qy * qy, qz * qz
	local xy, xz, yz = qx * qy, qx * qz, qy * qz
	local wx, wy, wz = qw * qx, qw * qy, qw * qz

	local r00 = 1 - 2 * (yy + zz)
	local r01 = 2 * (xy - wz)
	local r02 = 2 * (xz + wy)

	local r10 = 2 * (xy + wz)
	local r11 = 1 - 2 * (xx + zz)
	local r12 = 2 * (yz - wx)

	local r20 = 2 * (xz - wy)
	local r21 = 2 * (yz + wx)
	local r22 = 1 - 2 * (xx + yy)

	-- Snap position to 0.001 precision without math.round overhead:
	-- floor(x * 1000 + 0.5) / 1000 avoids the function call.
	local f = math.floor
	local finalCF = CFrame.new(
		f(posX * 1000 + 0.5) * 0.001,
		f(posY * 1000 + 0.5) * 0.001,
		f(posZ * 1000 + 0.5) * 0.001,
		r00,
		r01,
		r02,
		r10,
		r11,
		r12,
		r20,
		r21,
		r22
	)

	local linearVelocity
	if velX * velX + velY * velY + velZ * velZ > 1e-8 then
		linearVelocity =
			Vector3.new(f(velX * 1000 + 0.5) * 0.001, f(velY * 1000 + 0.5) * 0.001, f(velZ * 1000 + 0.5) * 0.001)
	else
		linearVelocity = Vector3.zero
	end

	local angularVelocity
	if angvelX * angvelX + angvelY * angvelY + angvelZ * angvelZ > 1e-8 then
		angularVelocity = Vector3.new(
			f(angvelX * 1000 + 0.5) * 0.001,
			f(angvelY * 1000 + 0.5) * 0.001,
			f(angvelZ * 1000 + 0.5) * 0.001
		)
	else
		angularVelocity = Vector3.zero
	end

	return finalCF, linearVelocity, angularVelocity
end

local function setGravity(physicsSystem, v, wind)
	-- i HAVE to add the wind, its mandatory trust
	local gravity = gravityBuffer
	gravity:writef32(0, 0 + (wind and wind.X or 0)) -- X
	gravity:writef32(4, v + -(wind and wind.Y or 0)) -- Y
	gravity:writef32(8, 0 + (wind and wind.Z or 0)) -- Z
	lib.JPH_PhysicsSystem_SetGravity(physicsSystem, gravity)
end

local function writeVec3(ptr, vec)
	ptr:writef32(0, vec.X)
	ptr:writef32(4, vec.Y)
	ptr:writef32(8, vec.Z)
end

local function readVec3(ptr)
	return Vector3.new(ptr:readf32(0), ptr:readf32(4), ptr:readf32(8))
end

KinemiumPhysicsService.InitRenderer = function(renderer, renderer_signal, game)
	physicsDatamodel = game
	task.spawn(function()
		repeat
			task.wait()
		until game.PlaytestService

		local _PlaytestService = game.PlaytestService
		local activeContactsByBody = {}
		local pendingTouchEvents = {}
		local pendingTouchEventCount = 0

		local function queueTouchEvent(part, otherPart, ended)
			pendingTouchEventCount += 1
			local event = pendingTouchEvents[pendingTouchEventCount]
			if not event then
				event = {}
				pendingTouchEvents[pendingTouchEventCount] = event
			end
			event.part = part
			event.otherPart = otherPart
			event.ended = ended
		end

		local function dispatchTouchEvents()
			for i = 1, pendingTouchEventCount do
				local event = pendingTouchEvents[i]
				local part = event.part
				if part and not rawget(part, "Destroyed") then
					local touchSignal = rawget(part, event.ended and "TouchEnded" or "Touched")
					if touchSignal then
						touchSignal:Fire(event.otherPart)
					end
				end
				event.part = nil
				event.otherPart = nil
				event.ended = nil
			end
			pendingTouchEventCount = 0
		end

		local function detachContact(record, emitTouchEnded)
			if not record.active then
				return
			end
			record.active = false

			local contacts1 = activeContactsByBody[record.body1]
			if contacts1 then
				contacts1[record.body2] = nil
				if next(contacts1) == nil then
					activeContactsByBody[record.body1] = nil
				end
			end

			local contacts2 = activeContactsByBody[record.body2]
			if contacts2 then
				contacts2[record.body1] = nil
				if next(contacts2) == nil then
					activeContactsByBody[record.body2] = nil
				end
			end

			if emitTouchEnded then
				queueTouchEvent(record.part1, record.part2, true)
				queueTouchEvent(record.part2, record.part1, true)
			end
		end

		local function beginContact(body1, body2)
			if body1 == body2 then
				return
			end

			local part1 = inverseMap[body1]
			local part2 = inverseMap[body2]
			if not part1 or not part2 then
				return
			end

			local contacts1 = activeContactsByBody[body1]
			local existing = contacts1 and contacts1[body2]
			if existing then
				existing.count += 1
				return
			end

			contacts1 = contacts1 or {}
			activeContactsByBody[body1] = contacts1
			local contacts2 = activeContactsByBody[body2] or {}
			activeContactsByBody[body2] = contacts2

			local record = {
				body1 = body1,
				body2 = body2,
				part1 = part1,
				part2 = part2,
				count = 1,
				active = true,
			}
			contacts1[body2] = record
			contacts2[body1] = record
			queueTouchEvent(part1, part2, false)
			queueTouchEvent(part2, part1, false)
		end

		local function endContact(body1, body2)
			local contacts = activeContactsByBody[body1]
			local record = contacts and contacts[body2]
			if not record then
				return
			end

			record.count -= 1
			if record.count <= 0 then
				detachContact(record, true)
			end
		end

		local function clearContactsForBody(bodyID, emitTouchEnded)
			local contacts = activeContactsByBody[bodyID]
			if not contacts then
				return
			end
			for _, record in pairs(contacts) do
				detachContact(record, emitTouchEnded)
			end
			activeContactsByBody[bodyID] = nil
		end

		local onContactAdded = ffi.closure({
			returns = ffi.types.void,
			args = { ffi.types.u32, ffi.types.u32, ffi.types.pointer },
		}, function(body1, body2, _manifold)
			beginContact(body1, body2)
		end)
		local onContactRemoved = ffi.closure({
			returns = ffi.types.void,
			args = { ffi.types.u32, ffi.types.u32, ffi.types.u32, ffi.types.u32 },
		}, function(body1, body2, _subShapeID1, _subShapeID2)
			endContact(body1, body2)
		end)
		local contactListenerProcs = structs.JPH_ContactListener_Procs:new({
			OnContactAdded = onContactAdded,
			OnContactPersisted = ffi.null,
			OnContactRemoved = onContactRemoved,
		})

		log("[Physics] Initializing Jolt Physics...")

		local initSuccess = lib.JPH_Init()
		if initSuccess == 0 then
			error("[Physics] Failed to initialize Jolt")
		end
		log("[Physics] Jolt initialized")

		-- BroadPhase has 3 buckets: 0=NonMoving, 1=Moving, 2=Intangible (both ghost layers share one BP bucket)
		local NUM_BROADPHASE_LAYERS = 3
		local broadPhaseLayerInterface =
			lib.JPH_BroadPhaseLayerInterfaceTable_Create(NUM_OBJECT_LAYERS, NUM_BROADPHASE_LAYERS)
		if broadPhaseLayerInterface == ffi.null then
			error("[Physics] Failed to create BroadPhaseLayerInterface")
		end

		for cg = 0, 31 do
			local baseLayer = cg * 4
			lib.JPH_BroadPhaseLayerInterfaceTable_MapObjectToBroadPhaseLayer(broadPhaseLayerInterface, baseLayer + 0, 0)
			lib.JPH_BroadPhaseLayerInterfaceTable_MapObjectToBroadPhaseLayer(broadPhaseLayerInterface, baseLayer + 1, 1)
			lib.JPH_BroadPhaseLayerInterfaceTable_MapObjectToBroadPhaseLayer(broadPhaseLayerInterface, baseLayer + 2, 2)
			lib.JPH_BroadPhaseLayerInterfaceTable_MapObjectToBroadPhaseLayer(broadPhaseLayerInterface, baseLayer + 3, 2)
		end
		log("[Physics] BroadPhaseLayerInterface created (4 object layers, 3 BP buckets)")

		local objectLayerPairFilter = lib.JPH_ObjectLayerPairFilterTable_Create(NUM_OBJECT_LAYERS)
		if objectLayerPairFilter == ffi.null then
			error("[Physics] Failed to create ObjectLayerPairFilter")
		end

		local function SetupCollisionMatrix()
			for cgA = 0, 31 do
				for cgB = 0, 31 do
					local collides = collisionGroups[cgA].collidesWith[cgB]
					for stateA = 0, 3 do
						for stateB = 0, 3 do
							local layerA = cgA * 4 + stateA
							local layerB = cgB * 4 + stateB

							local isIntangibleA = (stateA == 2 or stateA == 3)
							local isIntangibleB = (stateB == 2 or stateB == 3)
							local isBothStatic = (stateA == 0 or stateA == 2) and (stateB == 0 or stateB == 2)

							if isIntangibleA or isIntangibleB or isBothStatic or not collides then
								lib.JPH_ObjectLayerPairFilterTable_DisableCollision(
									objectLayerPairFilter,
									layerA,
									layerB
								)
							else
								lib.JPH_ObjectLayerPairFilterTable_EnableCollision(
									objectLayerPairFilter,
									layerA,
									layerB
								)
							end
						end
					end
				end
			end
		end

		SetupCollisionMatrix()

		log("[Physics] ObjectLayerPairFilter created (intangible layers disabled)")

		local objectVsBroadPhaseFilter = lib.JPH_ObjectVsBroadPhaseLayerFilterTable_Create(
			broadPhaseLayerInterface,
			NUM_BROADPHASE_LAYERS,
			objectLayerPairFilter,
			NUM_OBJECT_LAYERS
		)
		if objectVsBroadPhaseFilter == ffi.null then
			error("[Physics] Failed to create ObjectVsBroadPhaseLayerFilter")
		end
		log("[Physics] ObjectVsBroadPhaseLayerFilter created")

		local physicsSystemSettings = structs.JPH_PhysicsSystemSettings:new({
			maxBodies = 102400,
			numBodyMutexes = 0,
			maxBodyPairs = 65536,
			maxContactConstraints = 10240,
			_padding = 0,
			broadPhaseLayerInterface = broadPhaseLayerInterface,
			objectLayerPairFilter = objectLayerPairFilter,
			objectVsBroadPhaseLayerFilter = objectVsBroadPhaseFilter,
		})

		local physicsSystem = lib.JPH_PhysicsSystem_Create(physicsSystemSettings)

		if physicsSystem == ffi.null then
			error("[Physics] Failed to create physics system")
		end

		log("[Physics] Physics system created and initialized")

		local contactListener = lib.JPH_ContactListener_Create()
		if contactListener == ffi.null then
			error("[Physics] Failed to create contact listener")
		end
		lib.JPH_PhysicsSystem_SetContactListener(physicsSystem, contactListener)
		local physicsUnloaded = false

		local function pollContactEvents()
			if physicsUnloaded or contactListener == ffi.null then
				return
			end
			-- FFI callbacks invoked repeatedly from one native call consume Zune's C
			-- callback depth until that call returns. Draining an unbounded collision
			-- burst therefore produces a wall of "C stack overflow" errors.
			lib.JPH_ContactListener_PollEvents(contactListener, contactListenerProcs, 32)
			dispatchTouchEvents()
		end

		setGravity(physicsSystem, -9.81)
		log("[Physics] Gravity set")

		local bodyInterface = lib.JPH_PhysicsSystem_GetBodyInterface(physicsSystem)
		if bodyInterface == ffi.null then
			error("[Physics] Failed to get body interface")
		end
		log("[Physics] Body interface obtained")

		local _physicsState = {
			system = physicsSystem,
			bodyInterface = bodyInterface,
			broadPhaseLayerInterface = broadPhaseLayerInterface,
			objectLayerPairFilter = objectLayerPairFilter,
			objectVsBroadPhaseFilter = objectVsBroadPhaseFilter,
			SetupCollisionMatrix = SetupCollisionMatrix,
		}

		local config = structs.JPH_JobSystemConfig:new({
			context = 0,
			queueJob = ffi.null, -- Use Jolt's default
			queueJobs = ffi.null, -- Use Jolt's default
			maxConcurrency = 8, -- Number of threads
			maxBarriers = 8, -- Max barriers
		})

		local jobSystem = lib.JPH_JobSystemThreadPool_Create(config)
		if jobSystem == ffi.null then
			error("[Physics] Failed to create job system")
		end

		log("[Physics] Job system created")

		local function RemoveBody(part)
			local bodyID = bodiesMap[part]
			if bodyID then
				clearContactsForBody(bodyID, true)
				lib.JPH_BodyInterface_RemoveAndDestroyBody(bodyInterface, bodyID)
				bodiesMap[part] = nil
				movingBodiesMap[part] = nil
				bodyPointerMap[part] = nil
				inverseMap[bodyID] = nil
				bodyTransformDirty[part] = nil
				unindexPart(part)
				if bodyConnections[part] then
					bodyConnections[part]:Disconnect()
					bodyConnections[part] = nil
				end
				log("[Physics] Destroyed body for part")
			end

			local softBodyID = softBodiesMap[part]
			if softBodyID then
				lib.JPH_BodyInterface_RemoveAndDestroyBody(bodyInterface, softBodyID)
				softBodiesMap[part] = nil
				softBodyStates[part] = nil
				bodyPointerMap[part] = nil
				log("[Physics] Destroyed soft body")
			end
		end

		local debugBodiesCreated = 0
		local function refreshBodyMotion(part, bodyID)
			local newMotion = getMotionTypeForPart(part)
			local wasLocallySimulated = movingBodiesMap[part] ~= nil
			local activationMode = if newMotion == 2 then 0 else 1

			lib.JPH_BodyInterface_SetMotionType(bodyInterface, bodyID, newMotion, activationMode)
			lib.JPH_BodyInterface_SetObjectLayer(bodyInterface, bodyID, getLayerForPart(part))
			trackBodyMotion(part, bodyID, newMotion)

			if newMotion == 2 then
				if not wasLocallySimulated then
					syncBodyTransformFromPart(part, bodyInterface, bodyID)
				end
				lib.JPH_BodyInterface_ActivateBody(bodyInterface, bodyID)
				bodyTransformDirty[part] = nil
			else
				-- Static and remote kinematic bodies consume Instance/network state.
				bodyTransformDirty[part] = true
			end
		end

		local function CreateBodyForPart(part)
			if not shouldHavePhysicsBody(part) then
				RemoveBody(part)
				return
			end

			if not part.CFrame then
				return
			end

			if not part.Parent or not part:IsDescendantOf(game.Workspace) then
				return
			end

			local motion = getMotionTypeForPart(part)

			local oldBody = bodiesMap[part]
			if oldBody then
				trackBodyMotion(part, oldBody, motion)
				indexPart(part)
			else
				debugBodiesCreated += 1
				createBody(bodyInterface, part, motion)
				indexPart(part)

				local connection = part.Changed:Connect(function(property)
					local bodyID = bodiesMap[part]
					local bodyPtr = bodyPointerMap[part]
					if not bodyID or not bodyPtr then
						return
					end

					if property == "CustomPhysicalProperties" or property == "Mass" then
						updatePhysicalProps(part)
					end

					if
						property == "Size"
						or property == "Shape"
						or property == "MeshObject"
						or property == "CollisionFidelity"
						or property == "CollisionScale"
						or property == "MeshScale"
					then
						updateBodyShape(part, bodyInterface, bodyID)
						if part.Anchored then
							bodyTransformDirty[part] = true
						end
					elseif
						property == "Anchored"
						or property == "IsKinematic"
						or property == "NetworkOwner"
						or property == "NetworkOwnerType"
					then
						refreshBodyMotion(part, bodyID)
						updateBodyShape(part, bodyInterface, bodyID)
					elseif property == "CanCollide" or property == "CollisionGroup" then
						local newLayer = getLayerForPart(part)
						lib.JPH_BodyInterface_SetObjectLayer(bodyInterface, bodyID, newLayer)
					elseif property == "Position" or property == "CFrame" then
						if getMotionTypeForPart(part) ~= 2 then
							bodyTransformDirty[part] = true
						end
					end
				end)

				bodyConnections[part] = connection
			end
		end

		local propTable = {
			Raycast = function(origin, direction, params)
				if not origin or not direction or direction:Magnitude() == 0 then
					return nil
				end

				local filterRoots = params and params.FilterDescendantsInstances or nil
				local filterType = params and params.FilterType or Enum.RaycastFilterType.Exclude
				local includeFilter = filterType == Enum.RaycastFilterType.Include
					or filterType == 1
					or (type(filterType) == "table" and filterType.Name == "Include")
				local queryGroupID = GetCollisionGroupId(params and params.CollisionGroup or "Default")
				local queryGroup = collisionGroups[queryGroupID]
				local allowedBodyIDs = {}

				local function isFiltered(part)
					for _, root in ipairs(filterRoots or {}) do
						if part == root or (part.IsDescendantOf and part:IsDescendantOf(root)) then
							return true
						end
					end
					return false
				end

				for part, bodyID in pairs(bodiesMap) do
					local matchesFilter = isFiltered(part)
					local partGroupID = GetCollisionGroupId(part.CollisionGroup or "Default")
					local allowed = part.Parent ~= nil
						and part.CanQuery ~= false
						and (not params or not params.RespectCanCollide or part.CanCollide == true)
						and (not params or not params.IgnoreWater or part.Material ~= Enum.Material.Water)
						and (not queryGroup or queryGroup.collidesWith[partGroupID] ~= false)
						and (if includeFilter then matchesFilter else not matchesFilter)
					if allowed then
						table.insert(allowedBodyIDs, bodyID)
					end
				end
				for _, bodyID in pairs(terrainBodies) do
					local terrain = inverseMap[bodyID]
					if terrain then
						local matchesFilter = isFiltered(terrain)
						local allowed = terrain.CanQuery ~= false
							and (not params or not params.IgnoreWater or terrainBodyMaterials[bodyID] ~= Enum.Material.Water)
							and (not queryGroup or queryGroup.collidesWith[0] ~= false)
							and (if includeFilter then matchesFilter else not matchesFilter)
						if allowed then
							table.insert(allowedBodyIDs, bodyID)
						end
					end
				end

				if #allowedBodyIDs == 0 then
					return nil
				end

				local originBuffer = ffi.alloc(structs.JPH_RVec3:size(), structs.JPH_RVec3:alignment())
				originBuffer:writef64(0, origin.X)
				originBuffer:writef64(8, origin.Y)
				originBuffer:writef64(16, origin.Z)
				local directionBuffer = ffi.alloc(structs.JPH_Vec3:size(), structs.JPH_Vec3:alignment())
				directionBuffer:writef32(0, direction.X)
				directionBuffer:writef32(4, direction.Y)
				directionBuffer:writef32(8, direction.Z)
				local bodyIDBuffer = ffi.alloc(#allowedBodyIDs * 4, 4)
				for index, bodyID in ipairs(allowedBodyIDs) do
					bodyIDBuffer:writeu32((index - 1) * 4, bodyID)
				end
				local hit = ffi.alloc(structs.JPH_RayCastResult:size(), structs.JPH_RayCastResult:alignment())
				if
					lib.JPH_PhysicsSystem_CastRay(
						physicsSystem,
						originBuffer,
						directionBuffer,
						bodyIDBuffer,
						#allowedBodyIDs,
						2,
						hit
					) == 0
				then
					return nil
				end

				local bodyID = hit:readu32(structs.JPH_RayCastResult:offset("bodyID"))
				local part = inverseMap[bodyID]
				if not part then
					return nil
				end
				local positionOffset = structs.JPH_RayCastResult:offset("position")
				local normalOffset = structs.JPH_RayCastResult:offset("normal")
				local position = Vector3.new(
					hit:readf64(positionOffset),
					hit:readf64(positionOffset + 8),
					hit:readf64(positionOffset + 16)
				)
				local normal =
					Vector3.new(hit:readf32(normalOffset), hit:readf32(normalOffset + 4), hit:readf32(normalOffset + 8))
				local material = terrainBodyMaterials[bodyID] or part.Material
				return RaycastResult.new(
					part,
					position,
					normal,
					material,
					direction:Magnitude() * hit:readf32(structs.JPH_RayCastResult:offset("fraction"))
				)
			end,

			GetBody = function(part)
				return bodiesMap[part]
			end,

			UpdatePart = function(part)
				local body = bodiesMap[part]
				local bodyPtr = bodyPointerMap[part]
				if not body or not bodyPtr then
					return
				end

				-- UpdatePart is the synchronous route used by Part's Anchored and
				-- ownership handlers. Keep the native motion type in sync here rather
				-- than relying on the ordering of a second Changed listener.
				refreshBodyMotion(part, body)
				updatePhysicalProps(part)
				updateBodyShape(part, bodyInterface, body)

				if part.Anchored then
					syncBodyTransformFromPart(part, bodyInterface, body)
					bodyTransformDirty[part] = nil
				end
				CalculateBodyPhysics(part, bodyInterface, body)
			end,

			AddBody = function(part)
				CreateBodyForPart(part)
			end,

			RegisterCollisionGroup = RegisterCollisionGroup,

			CollisionGroupSetCollidable = function(name1, name2, collidable)
				local id1 = GetCollisionGroupId(name1)
				local id2 = GetCollisionGroupId(name2)
				if collisionGroups[id1] and collisionGroups[id2] then
					collisionGroups[id1].collidesWith[id2] = collidable
					collisionGroups[id2].collidesWith[id1] = collidable
					if _physicsState and _physicsState.SetupCollisionMatrix then
						_physicsState.SetupCollisionMatrix()
					end
				end
			end,

			GetCollisionGroupInfo = function(name)
				local id = GetCollisionGroupId(name)
				return collisionGroups[id]
			end,

			Enabled = false,

			setGravity = function(value, wind)
				setGravity(physicsSystem, value, wind)
			end,

			ApplyImpulse = function(part, impulse)
				local bodyID = bodiesMap[part]
				if not bodyID then
					log("[Physics] ApplyImpulse: No body for part", part.Name)
					return false
				end
				if movingBodiesMap[part] == nil then
					-- Static and remotely-owned kinematic proxies cannot consume a local
					-- impulse. Their authoritative simulation machine must apply it.
					return false
				end

				lib.JPH_BodyInterface_ActivateBody(bodyInterface, bodyID)

				local velocity = tempBodyLinear
				lib.JPH_BodyInterface_GetLinearVelocity(bodyInterface, bodyID, velocity)
				local beforeX = velocity:readf32(0)
				local beforeY = velocity:readf32(4)
				local beforeZ = velocity:readf32(8)
				local jImpulse = ffi.alloc(structs.JPH_Vec3:size(), structs.JPH_Vec3:alignment())
				writeVec3(jImpulse, impulse)

				lib.JPH_BodyInterface_AddImpulse(bodyInterface, bodyID, jImpulse)
				lib.JPH_BodyInterface_GetLinearVelocity(bodyInterface, bodyID, velocity)
				local afterX = velocity:readf32(0)
				local afterY = velocity:readf32(4)
				local afterZ = velocity:readf32(8)

				-- Some kine_jolt builds expose AddImpulse but silently leave velocity
				-- unchanged. Preserve impulse semantics with delta-v = impulse / mass.
				local observedDeltaSq = (afterX - beforeX) ^ 2 + (afterY - beforeY) ^ 2 + (afterZ - beforeZ) ^ 2
				local mass = math.max(tonumber(part.Mass) or 1, 0.001)
				local expectedDeltaSq = (impulse.X ^ 2 + impulse.Y ^ 2 + impulse.Z ^ 2) / (mass * mass)
				if expectedDeltaSq > 1e-8 and observedDeltaSq < expectedDeltaSq * 1e-4 then
					velocity:writef32(0, beforeX + impulse.X / mass)
					velocity:writef32(4, beforeY + impulse.Y / mass)
					velocity:writef32(8, beforeZ + impulse.Z / mass)
					lib.JPH_BodyInterface_SetLinearVelocity(bodyInterface, bodyID, velocity)
				end
				lib.JPH_BodyInterface_ActivateBody(bodyInterface, bodyID)
				return true
			end,

			ApplyForce = function(part, force, applicationPoint)
				local bodyID = bodiesMap[part]
				if not bodyID then
					return
				end

				lib.JPH_BodyInterface_ActivateBody(bodyInterface, bodyID)

				lib.JPH_BodyInterface_ActivateBody(bodyInterface, bodyID)
				local f = structs.JPH_Vec3:new({ x = force.X, y = force.Y, z = force.Z })
				if applicationPoint then
					local p = structs.JPH_RVec3:new({})
					p:writef64(0, applicationPoint.X)
					p:writef64(8, applicationPoint.Y)
					p:writef64(16, applicationPoint.Z)
					lib.JPH_BodyInterface_AddForce2(bodyInterface, bodyID, f, p)
				else
					lib.JPH_BodyInterface_AddForce(bodyInterface, bodyID, f)
				end
			end,

			CreateRawBody = function(data)
				local halfSize = ffi.alloc(structs.JPH_Vec3:size(), structs.JPH_Vec3:alignment())
				local size = data.Size or Vector3.new(1, 1, 1)
				halfSize:writef32(0, size.X / 2)
				halfSize:writef32(4, size.Y / 2)
				halfSize:writef32(8, size.Z / 2)

				local shape
				if data.Shape == Enum.PartType.Ball then
					shape = lib.JPH_SphereShape_Create(size.X * 0.5)
				else
					shape = lib.JPH_BoxShape_Create(halfSize, 0.05)
				end

				local pos = data.Position or Vector3.zero
				local position = ffi.alloc(structs.JPH_RVec3:size(), structs.JPH_RVec3:alignment())
				position:writef64(0, pos.X)
				position:writef64(8, pos.Y)
				position:writef64(16, pos.Z)

				local rotation = ffi.alloc(structs.JPH_Quat:size(), structs.JPH_Quat:alignment())
				rotation:writef32(0, 0)
				rotation:writef32(4, 0)
				rotation:writef32(8, 0)
				rotation:writef32(12, 1)

				local cgName = data.CollisionGroup or "Default"
				local cgId = GetCollisionGroupId(cgName)

				local motionState = 0
				if data.CanCollide then
					motionState = data.Anchored and 0 or 1
				else
					motionState = data.Anchored and 2 or 3
				end
				local layer = (cgId * 4) + motionState
				local motionType = data.Anchored and 0 or 2

				local bodySettings = lib.JPH_BodyCreationSettings_Create3(shape, position, rotation, motionType, layer)
				lib.JPH_BodyCreationSettings_SetAllowSleeping(bodySettings, 1)
				lib.JPH_BodyCreationSettings_SetAllowDynamicOrKinematic(bodySettings, 1)

				if data.Friction then
					lib.JPH_BodyCreationSettings_SetFriction(bodySettings, data.Friction)
				end
				if data.Restitution then
					lib.JPH_BodyCreationSettings_SetRestitution(bodySettings, data.Restitution)
				end
				if data.LinearDamping then
					lib.JPH_BodyCreationSettings_SetLinearDamping(bodySettings, data.LinearDamping)
				end
				if data.AngularDamping then
					lib.JPH_BodyCreationSettings_SetAngularDamping(bodySettings, data.AngularDamping)
				end
				if data.GravityFactor ~= nil then
					lib.JPH_BodyCreationSettings_SetGravityFactor(bodySettings, data.GravityFactor)
				end

				local bodyPtr = lib.JPH_BodyInterface_CreateBody(bodyInterface, bodySettings)
				if bodyPtr == ffi.null then
					lib.JPH_BodyCreationSettings_Destroy(bodySettings)
					return nil
				end

				local bodyID = lib.JPH_Body_GetID(bodyPtr)
				lib.JPH_BodyInterface_AddBody(bodyInterface, bodyID, motionType == 2 and 0 or 1)
				lib.JPH_BodyCreationSettings_Destroy(bodySettings)

				if data.AssemblyLinearVelocity then
					local tempLinear = ffi.alloc(structs.JPH_Vec3:size(), structs.JPH_Vec3:alignment())
					tempLinear:writef32(0, data.AssemblyLinearVelocity.X)
					tempLinear:writef32(4, data.AssemblyLinearVelocity.Y)
					tempLinear:writef32(8, data.AssemblyLinearVelocity.Z)
					lib.JPH_BodyInterface_SetLinearVelocity(bodyInterface, bodyID, tempLinear)
				end

				return bodyID
			end,

			GetRawBodyCFrame = function(bodyID)
				if not bodyID then
					return CFrame.new()
				end
				local position = tempBodyPosition
				local rotation = tempBodyRotation

				lib.JPH_BodyInterface_GetPositionAndRotation(bodyInterface, bodyID, position, rotation)
				local posX = position:readf64(0)
				local posY = position:readf64(8)
				local posZ = position:readf64(16)

				local qx = rotation:readf32(0)
				local qy = rotation:readf32(4)
				local qz = rotation:readf32(8)
				local qw = rotation:readf32(12)

				local xx, yy, zz = qx * qx, qy * qy, qz * qz
				local xy, xz, yz = qx * qy, qx * qz, qy * qz
				local wx, wy, wz = qw * qx, qw * qy, qw * qz

				local r00 = 1 - 2 * (yy + zz)
				local r01 = 2 * (xy - wz)
				local r02 = 2 * (xz + wy)

				local r10 = 2 * (xy + wz)
				local r11 = 1 - 2 * (xx + zz)
				local r12 = 2 * (yz - wx)

				local r20 = 2 * (xz - wy)
				local r21 = 2 * (yz + wx)
				local r22 = 1 - 2 * (xx + yy)

				return CFrame.new(posX, posY, posZ, r00, r01, r02, r10, r11, r12, r20, r21, r22)
			end,

			GetRawBodyPosition = function(bodyID)
				if not bodyID then
					return Vector3.zero
				end
				local position = tempBodyPosition
				lib.JPH_BodyInterface_GetPosition(bodyInterface, bodyID, position)
				return Vector3.new(position:readf64(0), position:readf64(8), position:readf64(16))
			end,

			GetRawBodyVelocity = function(bodyID)
				if not bodyID then
					return Vector3.zero
				end
				local velocity = tempBodyLinear
				lib.JPH_BodyInterface_GetLinearVelocity(bodyInterface, bodyID, velocity)
				return Vector3.new(velocity:readf32(0), velocity:readf32(4), velocity:readf32(8))
			end,

			DeleteRawBody = function(bodyID)
				if not bodyID then
					return
				end
				lib.JPH_BodyInterface_RemoveAndDestroyBody(bodyInterface, bodyID)
			end,

			CreateHumanoidController = function(data)
				if not lib.JPH_CharacterVirtual_Create or not lib.JPH_CharacterVirtual_Update then
					return nil
				end

				local size = data.Size or Vector3.new(2, 2.5, 1.25)

				local halfSize = ffi.alloc(structs.JPH_Vec3:size(), structs.JPH_Vec3:alignment())
				halfSize:writef32(0, size.X * 0.5)
				halfSize:writef32(4, size.Y * 0.5)
				halfSize:writef32(8, size.Z * 0.5)

				local shape = lib.JPH_BoxShape_Create(halfSize, 0.05)
				if shape == ffi.null then
					return nil
				end

				local up = buffer.create(structs.JPH_Vec3:size())
				buffer.writef32(up, 0, 0)
				buffer.writef32(up, 4, 1)
				buffer.writef32(up, 8, 0)

				local base = structs.JPH_CharacterBaseSettings:new({
					maxSlopeAngle = math.rad(data.MaxSlopeAngle or 45),
					up = up,
					shape = shape,
				})

				local settings = structs.JPH_CharacterVirtualSettings:new({
					base = base,
					mass = data.Mass or 80,
					maxStrength = data.MaxStrength or 4000,
					characterPadding = data.Padding or 0.02,
					maxNumHits = data.MaxNumHits or 32,
					penetrationRecoverySpeed = data.PenetrationRecoverySpeed or 1,
				})

				lib.JPH_CharacterVirtualSettings_Init(settings)

				local pos = data.Position or Vector3.zero

				local position = ffi.alloc(structs.JPH_RVec3:size(), structs.JPH_RVec3:alignment())
				position:writef64(0, pos.X)
				position:writef64(8, pos.Y)
				position:writef64(16, pos.Z)

				local rotation = ffi.alloc(structs.JPH_Quat:size(), structs.JPH_Quat:alignment())
				rotation:writef32(0, 0)
				rotation:writef32(4, 0)
				rotation:writef32(8, 0)
				rotation:writef32(12, 1)

				local character = lib.JPH_CharacterVirtual_Create(settings, position, rotation, physicsSystem)
				if character == ffi.null then
					return nil
				end
				return { character = character, shape = shape }
			end,

			DestroyHumanoidController = function(controller)
				if not controller or not controller.character then
					return
				end
				lib.JPH_CharacterBase_Destroy(controller.character)
				controller.character = nil
			end,

			StepHumanoidController = function(controller, velocity, gravity, dt)
				if not controller or not controller.character then
					return nil
				end

				local jVelocity = tempCharacterVelocity
				writeVec3(jVelocity, velocity or Vector3.zero)
				lib.JPH_CharacterVirtual_SetLinearVelocity(controller.character, jVelocity)

				local jGravity = tempCharacterGravity
				writeVec3(jGravity, gravity or Vector3.new(0, -9.81, 0))
				lib.JPH_CharacterVirtual_Update(controller.character, dt, jGravity, ffi.null, ffi.null, ffi.null)

				local position = tempCharacterPosition
				local outVelocity = tempCharacterOutputVelocity
				lib.JPH_CharacterVirtual_GetPosition(controller.character, position)
				lib.JPH_CharacterVirtual_GetLinearVelocity(controller.character, outVelocity)

				local isSupported = false
				if lib.JPH_CharacterBase_IsSupported then
					isSupported = lib.JPH_CharacterBase_IsSupported(controller.character) ~= 0
				end
				local groundBodyId = nil
				if lib.JPH_CharacterBase_GetGroundBodyId then
					groundBodyId = lib.JPH_CharacterBase_GetGroundBodyId(controller.character)
				end

				return {
					position = Vector3.new(position:readf64(0), position:readf64(8), position:readf64(16)),
					velocity = readVec3(outVelocity),
					isGrounded = isSupported,
					groundInstance = groundBodyId and inverseMap[groundBodyId] or nil,
				}
			end,

			ApplyForceToRawBody = function(bodyID, force)
				if not bodyID then
					return
				end
				lib.JPH_BodyInterface_ActivateBody(bodyInterface, bodyID)
				local f = structs.JPH_Vec3:new({ x = force.X, y = force.Y, z = force.Z })
				lib.JPH_BodyInterface_AddForce(bodyInterface, bodyID, f)
			end,

			ApplyImpulseToRawBody = function(bodyID, impulse)
				if not bodyID then
					return
				end
				lib.JPH_BodyInterface_ActivateBody(bodyInterface, bodyID)
				local f = structs.JPH_Vec3:new({ x = impulse.X, y = impulse.Y, z = impulse.Z })
				lib.JPH_BodyInterface_AddImpulse(bodyInterface, bodyID, f)
			end,

			ApplyTorque = function(part, torque)
				local bodyID = bodiesMap[part]
				if not bodyID then
					return
				end
				lib.JPH_BodyInterface_ActivateBody(bodyInterface, bodyID)
				local jTorque = structs.JPH_Vec3:new({ x = torque.X, y = torque.Y, z = torque.Z })
				lib.JPH_BodyInterface_AddTorque(bodyInterface, bodyID, jTorque)
			end,

			GetBodyRotation = function(part)
				local bodyID = bodiesMap[part]
				if not bodyID then
					return 0, 0, 0, 1
				end
				local rot = ffi.alloc(structs.JPH_Quat:size(), structs.JPH_Quat:alignment())
				lib.JPH_BodyInterface_GetRotation(bodyInterface, bodyID, rot)
				return rot:readf32(0), rot:readf32(4), rot:readf32(8), rot:readf32(12)
			end,

			GetAngularVelocity = function(part)
				local bodyID = bodiesMap[part]
				if not bodyID then
					return Vector3.new(0, 0, 0)
				end
				local av = ffi.alloc(structs.JPH_Vec3:size(), structs.JPH_Vec3:alignment())
				lib.JPH_BodyInterface_GetAngularVelocity(bodyInterface, bodyID, av)
				return Vector3.new(av:readf32(0), av:readf32(4), av:readf32(8))
			end,

			UpdateTerrainChunk = function(chunkKey, vertices, indices, material)
				if terrainBodies[chunkKey] then
					local oldBodyID = terrainBodies[chunkKey]
					lib.JPH_BodyInterface_RemoveAndDestroyBody(bodyInterface, oldBodyID)
					inverseMap[oldBodyID] = nil
					terrainBodyMaterials[oldBodyID] = nil
					terrainBodies[chunkKey] = nil
				end

				if not vertices or #vertices == 0 or not indices or #indices == 0 then
					return
				end

				-- Convert vertices to _BodyMaker's required format
				local points = bodyMaker.pointsFromMeshgenVerts(vertices)

				-- Convert indices to the triangles table _BodyMaker expects
				local triangles = {}
				-- indices are zero-based from Terrain:_rebuildChunk's meshgen
				for i = 1, #indices - 2, 3 do
					table.insert(triangles, { indices[i], indices[i + 1], indices[i + 2] })
				end

				-- _BodyMaker.buildMeshBody handles MeshShape and BodyCreation
				local bodyID = bodyMaker.buildMeshBody(bodyInterface, points, triangles, nil, {
					motionType = 0, -- Static
					layer = 0, -- Static, Solid (Layer 0)
				})

				if bodyID then
					terrainBodies[chunkKey] = bodyID
					inverseMap[bodyID] = game.Workspace:FindFirstChild("Terrain")
					terrainBodyMaterials[bodyID] = material
				end
			end,

			CreateWeld = function(partA, partB)
				local bodyA = bodyPointerMap[partA]
				local bodyB = bodyPointerMap[partB]
				if not bodyA or not bodyB then
					warn(
						"[Physics] CreateWeld: missing body for",
						partA and partA.Name or "?",
						"or",
						partB and partB.Name or "?"
					)
					return
				end

				local FCS = structs.JPH_FixedConstraintSettings
				local settings = ffi.alloc(FCS:size(), FCS:alignment())
				lib.JPH_FixedConstraintSettings_Init(settings)

				-- Use autoDetectPoint so Jolt computes correct local-space anchors
				-- from both bodies' current world transforms automatically.
				settings:writei32(FCS:offset("space"), 1) -- WorldSpace (1)
				settings:writeu8(FCS:offset("autoDetectPoint"), 1) -- let Jolt derive anchor points

				local constraint = lib.JPH_FixedConstraint_Create(settings, bodyA, bodyB)
				if constraint == ffi.null then
					warn("[Physics] CreateWeld: JPH_FixedConstraint_Create returned null")
					return
				end
				lib.JPH_PhysicsSystem_AddConstraint(physicsSystem, constraint)
				return constraint
			end,

			CreateHinge = function(partA, partB, point1, axis1, normal1, point2, axis2, normal2, maxTorque)
				local bodyA = bodyPointerMap[partA]
				local bodyB = bodyPointerMap[partB]
				if not bodyA or not bodyB then
					return
				end

				local HCS = structs.JPH_HingeConstraintSettings
				local settings = ffi.alloc(HCS:size(), HCS:alignment())
				lib.JPH_HingeConstraintSettings_Init(settings)

				settings:writei32(HCS:offset("space"), 1) -- JPH_ConstraintSpace_WorldSpace (1)

				local function setVec3(offset, v)
					settings:writef32(offset, v.X)
					settings:writef32(offset + 4, v.Y)
					settings:writef32(offset + 8, v.Z)
				end

				local function setRVec3(offset, v)
					settings:writef64(offset, v.X)
					settings:writef64(offset + 8, v.Y)
					settings:writef64(offset + 16, v.Z)
				end

				setRVec3(HCS:offset("point1"), point1)
				setVec3(HCS:offset("hingeAxis1"), axis1)
				setVec3(HCS:offset("normalAxis1"), normal1)

				setRVec3(HCS:offset("point2"), point2)
				setVec3(HCS:offset("hingeAxis2"), axis2)
				setVec3(HCS:offset("normalAxis2"), normal2)

				settings:writef32(HCS:offset("limitsMin"), 3.14159)
				settings:writef32(HCS:offset("limitsMax"), -3.14159)

				local torque = maxTorque or 10000
				local MS = structs.JPH_MotorSettings
				local motorOffset = HCS:offset("motorSettings")
				local SS = structs.JPH_SpringSettings
				settings:writeu32(motorOffset + MS:offset("springSettings") + SS:offset("mode"), 0)
				settings:writef32(motorOffset + MS:offset("springSettings") + SS:offset("frequencyOrStiffness"), 10.0)
				settings:writef32(motorOffset + MS:offset("springSettings") + SS:offset("damping"), 0.5)
				settings:writef32(motorOffset + MS:offset("minForceLimit"), -torque)
				settings:writef32(motorOffset + MS:offset("maxForceLimit"), torque)
				settings:writef32(motorOffset + MS:offset("minTorqueLimit"), -torque)
				settings:writef32(motorOffset + MS:offset("maxTorqueLimit"), torque)

				local constraint = lib.JPH_HingeConstraint_Create(settings, bodyA, bodyB)
				if constraint ~= ffi.null then
					lib.JPH_PhysicsSystem_AddConstraint(physicsSystem, constraint)
				end
				return constraint
			end,

			CreateBallSocket = function(partA, partB, point1, point2)
				local bodyA = bodyPointerMap[partA]
				local bodyB = bodyPointerMap[partB]
				if not bodyA or not bodyB then
					return
				end

				-- The bundled C API does not expose JPH_PointConstraint. A SixDOF
				-- constraint with locked translation and free rotation is equivalent.
				local SCS = structs.JPH_SixDOFConstraintSettings
				local settings = ffi.alloc(SCS:size(), SCS:alignment())
				lib.JPH_SixDOFConstraintSettings_Init(settings)
				settings:writei32(SCS:offset("space"), 1) -- WorldSpace

				local function setRVec3(offset, v)
					settings:writef64(offset, v.X)
					settings:writef64(offset + 8, v.Y)
					settings:writef64(offset + 16, v.Z)
				end
				local function setVec3(offset, x, y, z)
					settings:writef32(offset, x)
					settings:writef32(offset + 4, y)
					settings:writef32(offset + 8, z)
				end

				setRVec3(SCS:offset("position1"), point1)
				setRVec3(SCS:offset("position2"), point2)
				setVec3(SCS:offset("axisX1"), 1, 0, 0)
				setVec3(SCS:offset("axisY1"), 0, 1, 0)
				setVec3(SCS:offset("axisX2"), 1, 0, 0)
				setVec3(SCS:offset("axisY2"), 0, 1, 0)
				for axis = 0, 2 do
					lib.JPH_SixDOFConstraintSettings_MakeFixedAxis(settings, axis)
				end
				for axis = 3, 5 do
					lib.JPH_SixDOFConstraintSettings_MakeFreeAxis(settings, axis)
				end

				local constraint = lib.JPH_SixDOFConstraint_Create(settings, bodyA, bodyB)
				if constraint ~= ffi.null then
					lib.JPH_PhysicsSystem_AddConstraint(physicsSystem, constraint)
				end
				return constraint
			end,

			CreateUniversal = function(
				partA,
				partB,
				point1,
				axisX1,
				axisY1,
				point2,
				axisX2,
				axisY2,
				limitMinX,
				limitMaxX,
				limitMinY,
				limitMaxY
			)
				local bodyA = bodyPointerMap[partA]
				local bodyB = bodyPointerMap[partB]
				if not bodyA or not bodyB then
					return
				end

				local SCS = structs.JPH_SixDOFConstraintSettings
				local settings = ffi.alloc(SCS:size(), SCS:alignment())
				lib.JPH_SixDOFConstraintSettings_Init(settings)
				settings:writei32(SCS:offset("space"), 1) -- WorldSpace

				local function setVec3(offset, v)
					settings:writef32(offset, v.X)
					settings:writef32(offset + 4, v.Y)
					settings:writef32(offset + 8, v.Z)
				end
				local function setRVec3(offset, v)
					settings:writef64(offset, v.X)
					settings:writef64(offset + 8, v.Y)
					settings:writef64(offset + 16, v.Z)
				end

				setRVec3(SCS:offset("position1"), point1)
				setVec3(SCS:offset("axisX1"), axisX1)
				setVec3(SCS:offset("axisY1"), axisY1)

				setRVec3(SCS:offset("position2"), point2)
				setVec3(SCS:offset("axisX2"), axisX2)
				setVec3(SCS:offset("axisY2"), axisY2)

				lib.JPH_SixDOFConstraintSettings_MakeFixedAxis(settings, 0) -- TransX
				lib.JPH_SixDOFConstraintSettings_MakeFixedAxis(settings, 1) -- TransY
				lib.JPH_SixDOFConstraintSettings_MakeFixedAxis(settings, 2) -- TransZ

				lib.JPH_SixDOFConstraintSettings_SetLimitedAxis(settings, 3, limitMinX or -3.1415, limitMaxX or 3.1415) -- RotX
				lib.JPH_SixDOFConstraintSettings_SetLimitedAxis(settings, 4, limitMinY or -3.1415, limitMaxY or 3.1415) -- RotY
				lib.JPH_SixDOFConstraintSettings_MakeFixedAxis(settings, 5) -- RotZ (Twist locked)

				local constraint = lib.JPH_SixDOFConstraint_Create(settings, bodyA, bodyB)
				if constraint ~= ffi.null then
					lib.JPH_PhysicsSystem_AddConstraint(physicsSystem, constraint)
				end
				return constraint
			end,

			CreateRod = function(partA, partB, point1, point2, length)
				local bodyA = bodyPointerMap[partA]
				local bodyB = bodyPointerMap[partB]
				if not bodyA or not bodyB then
					return
				end

				local DCS = structs.JPH_DistanceConstraintSettings
				local settings = ffi.alloc(DCS:size(), DCS:alignment())
				lib.JPH_DistanceConstraintSettings_Init(settings)

				-- WorldSpace = 1
				settings:writei32(DCS:offset("space"), 1)

				-- point1 (RVec3 = 3x double)
				settings:writef64(DCS:offset("point1") + 0, point1.X)
				settings:writef64(DCS:offset("point1") + 8, point1.Y)
				settings:writef64(DCS:offset("point1") + 16, point1.Z)

				-- point2 (RVec3 = 3x double)
				settings:writef64(DCS:offset("point2") + 0, point2.X)
				settings:writef64(DCS:offset("point2") + 8, point2.Y)
				settings:writef64(DCS:offset("point2") + 16, point2.Z)

				-- Fixed rod: min == max == length
				settings:writef32(DCS:offset("minDistance"), length)
				settings:writef32(DCS:offset("maxDistance"), length)

				local constraint = lib.JPH_DistanceConstraint_Create(settings, bodyA, bodyB)
				if constraint ~= ffi.null then
					lib.JPH_PhysicsSystem_AddConstraint(physicsSystem, constraint)
				end
				return constraint
			end,

			CreateRope = function(partA, partB, point1, point2, maxLength, stiffness, damping)
				local bodyA = bodyPointerMap[partA]
				local bodyB = bodyPointerMap[partB]
				if not bodyA or not bodyB then
					return
				end

				local DCS = structs.JPH_DistanceConstraintSettings
				local settings = ffi.alloc(DCS:size(), DCS:alignment())
				lib.JPH_DistanceConstraintSettings_Init(settings)

				-- WorldSpace = 1
				settings:writei32(DCS:offset("space"), 1)

				-- point1
				settings:writef64(DCS:offset("point1") + 0, point1.X)
				settings:writef64(DCS:offset("point1") + 8, point1.Y)
				settings:writef64(DCS:offset("point1") + 16, point1.Z)

				-- point2
				settings:writef64(DCS:offset("point2") + 0, point2.X)
				settings:writef64(DCS:offset("point2") + 8, point2.Y)
				settings:writef64(DCS:offset("point2") + 16, point2.Z)

				-- Rope: min = 0 (slack allowed), max = maxLength (can't stretch)
				settings:writef32(DCS:offset("minDistance"), 0)
				settings:writef32(DCS:offset("maxDistance"), maxLength)

				-- Optional spring softness for the limit
				if stiffness and stiffness > 0 then
					local SS = structs.JPH_SpringSettings
					local springOff = DCS:offset("limitsSpringSettings")
					-- SpringMode: 0 = FrequencyAndDamping, 1 = StiffnessAndDamping
					settings:writei32(springOff + SS:offset("mode"), 1)
					settings:writef32(springOff + SS:offset("frequencyOrStiffness"), stiffness)
					settings:writef32(springOff + SS:offset("damping"), damping or 0.1)
				end

				local constraint = lib.JPH_DistanceConstraint_Create(settings, bodyA, bodyB)
				if constraint ~= ffi.null then
					lib.JPH_PhysicsSystem_AddConstraint(physicsSystem, constraint)
				end
				return constraint
			end,

			CreatePlane = function(partA, partB, point1, axisX1, axisY1, point2, axisX2, axisY2)
				local bodyA = bodyPointerMap[partA]
				local bodyB = bodyPointerMap[partB]
				if not bodyA or not bodyB then
					return
				end

				local SCS = structs.JPH_SixDOFConstraintSettings
				local settings = ffi.alloc(SCS:size(), SCS:alignment())
				lib.JPH_SixDOFConstraintSettings_Init(settings)
				settings:writei32(SCS:offset("space"), 1)

				local function setVec3(offset, v)
					settings:writef32(offset, v.X)
					settings:writef32(offset + 4, v.Y)
					settings:writef32(offset + 8, v.Z)
				end
				local function setRVec3(offset, v)
					settings:writef64(offset, v.X)
					settings:writef64(offset + 8, v.Y)
					settings:writef64(offset + 16, v.Z)
				end

				setRVec3(SCS:offset("position1"), point1)
				setVec3(SCS:offset("axisX1"), axisX1)
				setVec3(SCS:offset("axisY1"), axisY1)
				setRVec3(SCS:offset("position2"), point2)
				setVec3(SCS:offset("axisX2"), axisX2)
				setVec3(SCS:offset("axisY2"), axisY2)

				lib.JPH_SixDOFConstraintSettings_MakeFreeAxis(settings, 0) -- TransX
				lib.JPH_SixDOFConstraintSettings_MakeFreeAxis(settings, 1) -- TransY
				lib.JPH_SixDOFConstraintSettings_MakeFixedAxis(settings, 2) -- TransZ Fixed to 0 (Plane normal)

				lib.JPH_SixDOFConstraintSettings_MakeFreeAxis(settings, 3) -- RotX
				lib.JPH_SixDOFConstraintSettings_MakeFreeAxis(settings, 4) -- RotY
				lib.JPH_SixDOFConstraintSettings_MakeFreeAxis(settings, 5) -- RotZ

				local constraint = lib.JPH_SixDOFConstraint_Create(settings, bodyA, bodyB)
				if constraint ~= ffi.null then
					lib.JPH_PhysicsSystem_AddConstraint(physicsSystem, constraint)
				end
				return constraint
			end,

			CreateTorsionSpring = function(
				partA,
				partB,
				point1,
				axisX1,
				axisY1,
				point2,
				axisX2,
				axisY2,
				stiffness,
				damping,
				maxAngle
			)
				local bodyA = bodyPointerMap[partA]
				local bodyB = bodyPointerMap[partB]
				if not bodyA or not bodyB then
					return
				end

				-- Jolt only supports limit springs on the three translational SixDOF
				-- axes. A position-driven hinge is its native torsional spring: it
				-- locks translation, permits twist around Axis, and drives that twist
				-- back to zero with the requested stiffness and damping.
				local HCS = structs.JPH_HingeConstraintSettings
				local settings = ffi.alloc(HCS:size(), HCS:alignment())
				lib.JPH_HingeConstraintSettings_Init(settings)
				settings:writei32(HCS:offset("space"), 1)

				local function setVec3(offset, v)
					settings:writef32(offset, v.X)
					settings:writef32(offset + 4, v.Y)
					settings:writef32(offset + 8, v.Z)
				end
				local function setRVec3(offset, v)
					settings:writef64(offset, v.X)
					settings:writef64(offset + 8, v.Y)
					settings:writef64(offset + 16, v.Z)
				end

				setRVec3(HCS:offset("point1"), point1)
				setVec3(HCS:offset("hingeAxis1"), axisX1)
				setVec3(HCS:offset("normalAxis1"), axisY1)
				setRVec3(HCS:offset("point2"), point2)
				setVec3(HCS:offset("hingeAxis2"), axisX2)
				setVec3(HCS:offset("normalAxis2"), axisY2)

				local angle = maxAngle or math.pi
				settings:writef32(HCS:offset("limitsMin"), -angle)
				settings:writef32(HCS:offset("limitsMax"), angle)

				local MS = structs.JPH_MotorSettings
				local SS = structs.JPH_SpringSettings
				local motorOffset = HCS:offset("motorSettings")
				settings:writeu32(motorOffset + MS:offset("springSettings") + SS:offset("mode"), 1)
				settings:writef32(
					motorOffset + MS:offset("springSettings") + SS:offset("frequencyOrStiffness"),
					stiffness or 10.0
				)
				settings:writef32(motorOffset + MS:offset("springSettings") + SS:offset("damping"), damping or 0.5)
				settings:writef32(motorOffset + MS:offset("minTorqueLimit"), -100000)
				settings:writef32(motorOffset + MS:offset("maxTorqueLimit"), 100000)

				local constraint = lib.JPH_HingeConstraint_Create(settings, bodyA, bodyB)
				if constraint ~= ffi.null then
					lib.JPH_PhysicsSystem_AddConstraint(physicsSystem, constraint)
					lib.JPH_HingeConstraint_SetMotorState(constraint, 2)
					lib.JPH_HingeConstraint_SetTargetAngle(constraint, 0)
				end
				return constraint
			end,

			CreateCylindrical = function(
				partA,
				partB,
				point1,
				axisX1,
				axisY1,
				point2,
				axisX2,
				axisY2,
				limitMinTrans,
				limitMaxTrans,
				limitMinRot,
				limitMaxRot
			)
				local bodyA = bodyPointerMap[partA]
				local bodyB = bodyPointerMap[partB]
				if not bodyA or not bodyB then
					return
				end

				local SCS = structs.JPH_SixDOFConstraintSettings
				local settings = ffi.alloc(SCS:size(), SCS:alignment())
				lib.JPH_SixDOFConstraintSettings_Init(settings)
				settings:writei32(SCS:offset("space"), 1)

				local function setVec3(offset, v)
					settings:writef32(offset, v.X)
					settings:writef32(offset + 4, v.Y)
					settings:writef32(offset + 8, v.Z)
				end
				local function setRVec3(offset, v)
					settings:writef64(offset, v.X)
					settings:writef64(offset + 8, v.Y)
					settings:writef64(offset + 16, v.Z)
				end

				setRVec3(SCS:offset("position1"), point1)
				setVec3(SCS:offset("axisX1"), axisX1)
				setVec3(SCS:offset("axisY1"), axisY1)
				setRVec3(SCS:offset("position2"), point2)
				setVec3(SCS:offset("axisX2"), axisX2)
				setVec3(SCS:offset("axisY2"), axisY2)

				if limitMinTrans ~= nil and limitMaxTrans ~= nil then
					lib.JPH_SixDOFConstraintSettings_SetLimitedAxis(settings, 0, limitMinTrans, limitMaxTrans)
				else
					lib.JPH_SixDOFConstraintSettings_MakeFreeAxis(settings, 0) -- TransX Free
				end

				lib.JPH_SixDOFConstraintSettings_MakeFixedAxis(settings, 1) -- TransY Locked
				lib.JPH_SixDOFConstraintSettings_MakeFixedAxis(settings, 2) -- TransZ Locked

				if limitMinRot ~= nil and limitMaxRot ~= nil then
					lib.JPH_SixDOFConstraintSettings_SetLimitedAxis(settings, 3, limitMinRot, limitMaxRot)
				else
					lib.JPH_SixDOFConstraintSettings_MakeFreeAxis(settings, 3) -- RotX Free
				end

				lib.JPH_SixDOFConstraintSettings_MakeFixedAxis(settings, 4) -- RotY Locked
				lib.JPH_SixDOFConstraintSettings_MakeFixedAxis(settings, 5) -- RotZ Locked

				local constraint = lib.JPH_SixDOFConstraint_Create(settings, bodyA, bodyB)
				if constraint ~= ffi.null then
					lib.JPH_PhysicsSystem_AddConstraint(physicsSystem, constraint)
				end
				return constraint
			end,

			SetHingeMotorState = function(constraint, state)
				if not constraint then
					return
				end
				-- state: 0=Off, 1=Velocity, 2=Position
				lib.JPH_HingeConstraint_SetMotorState(constraint, state)
			end,

			SetHingeTargetVelocity = function(constraint, velocity)
				if not constraint then
					return
				end
				lib.JPH_HingeConstraint_SetTargetAngularVelocity(constraint, velocity)
			end,

			SetHingeTargetAngle = function(constraint, angle)
				if not constraint then
					return
				end
				lib.JPH_HingeConstraint_SetTargetAngle(constraint, angle)
			end,
			GetHingeAngle = function(constraint)
				if not constraint then
					return 0
				end
				return lib.JPH_HingeConstraint_GetCurrentAngle(constraint)
			end,

			SetHingeLimits = function(constraint, min, max)
				if not constraint then
					return
				end
				lib.JPH_HingeConstraint_SetLimits(constraint, min, max)
			end,

			SetHingeMotorSettings = function(constraint, maxTorque)
				if not constraint then
					return
				end
				local MS = structs.JPH_MotorSettings
				local SS = structs.JPH_SpringSettings
				local settings = ffi.alloc(MS:size(), MS:alignment())
				-- springSettings first (offset 0 within MotorSettings)
				settings:writeu32(MS:offset("springSettings") + SS:offset("mode"), 0) -- FrequencyAndDamping
				settings:writef32(MS:offset("springSettings") + SS:offset("frequencyOrStiffness"), 10.0)
				settings:writef32(MS:offset("springSettings") + SS:offset("damping"), 0.5)
				-- then force/torque limits
				settings:writef32(MS:offset("minForceLimit"), -maxTorque)
				settings:writef32(MS:offset("maxForceLimit"), maxTorque)
				settings:writef32(MS:offset("minTorqueLimit"), -maxTorque)
				settings:writef32(MS:offset("maxTorqueLimit"), maxTorque)
				lib.JPH_HingeConstraint_SetMotorSettings(constraint, settings)
			end,

			ActivatePart = function(part)
				local bodyID = bodiesMap[part]
				if bodyID then
					lib.JPH_BodyInterface_ActivateBody(bodyInterface, bodyID)
				end
			end,

			CreateSpring = function(
				partA,
				partB,
				point1,
				point2,
				minDistance,
				maxDistance,
				springMode,
				frequencyOrStiffness,
				damping
			)
				local bodyA = bodyPointerMap[partA]
				local bodyB = bodyPointerMap[partB]
				if not bodyA or not bodyB then
					return
				end

				local DCS = structs.JPH_DistanceConstraintSettings
				local settings = ffi.alloc(DCS:size(), DCS:alignment())
				lib.JPH_DistanceConstraintSettings_Init(settings)

				local function setRVec3(offset, v)
					settings:writef64(offset, v.X)
					settings:writef64(offset + 8, v.Y)
					settings:writef64(offset + 16, v.Z)
				end

				settings:writei32(DCS:offset("space"), 1) -- JPH_ConstraintSpace_WorldSpace
				setRVec3(DCS:offset("point1"), point1)
				setRVec3(DCS:offset("point2"), point2)

				settings:writef32(DCS:offset("minDistance"), minDistance)
				settings:writef32(DCS:offset("maxDistance"), maxDistance)

				local SS = structs.JPH_SpringSettings
				local springOffset = DCS:offset("limitsSpringSettings")
				settings:writeu32(springOffset + SS:offset("mode"), springMode)
				settings:writef32(springOffset + SS:offset("frequencyOrStiffness"), frequencyOrStiffness)
				settings:writef32(springOffset + SS:offset("damping"), damping)

				local constraint = lib.JPH_DistanceConstraint_Create(settings, bodyA, bodyB)
				if constraint ~= ffi.null then
					lib.JPH_PhysicsSystem_AddConstraint(physicsSystem, constraint)
				end
				return constraint
			end,

			SetSpringLimits = function(constraint, minDistance, maxDistance)
				if not constraint then
					return
				end
				lib.JPH_DistanceConstraint_SetDistance(constraint, minDistance, maxDistance)
			end,

			SetSpringSettings = function(constraint, springMode, frequencyOrStiffness, damping)
				if not constraint then
					return
				end
				local SS = structs.JPH_SpringSettings
				local settings = ffi.alloc(SS:size(), SS:alignment())
				settings:writeu32(SS:offset("mode"), springMode)
				settings:writef32(SS:offset("frequencyOrStiffness"), frequencyOrStiffness)
				settings:writef32(SS:offset("damping"), damping)
				lib.JPH_DistanceConstraint_SetLimitsSpringSettings(constraint, settings)
			end,

			CreateSlider = function(partA, partB, point1, axis1, normal1, point2, axis2, normal2)
				local bodyA = bodyPointerMap[partA]
				local bodyB = bodyPointerMap[partB]
				if not bodyA or not bodyB then
					return
				end

				local SCS = structs.JPH_SliderConstraintSettings
				local settings = ffi.alloc(SCS:size(), SCS:alignment())
				lib.JPH_SliderConstraintSettings_Init(settings)

				settings:writei32(SCS:offset("space"), 0) -- JPH_ConstraintSpace_LocalToBodyCOM (0)

				local function setVec3(offset, v)
					settings:writef32(offset, v.X)
					settings:writef32(offset + 4, v.Y)
					settings:writef32(offset + 8, v.Z)
				end

				local function setRVec3(offset, v)
					settings:writef64(offset, v.X)
					settings:writef64(offset + 8, v.Y)
					settings:writef64(offset + 16, v.Z)
				end

				setRVec3(SCS:offset("point1"), point1)
				setVec3(SCS:offset("sliderAxis1"), axis1)
				setVec3(SCS:offset("normalAxis1"), normal1)

				setRVec3(SCS:offset("point2"), point2)
				setVec3(SCS:offset("sliderAxis2"), axis2)
				setVec3(SCS:offset("normalAxis2"), normal2)

				local constraint = lib.JPH_SliderConstraint_Create(settings, bodyA, bodyB)
				if constraint ~= ffi.null then
					lib.JPH_PhysicsSystem_AddConstraint(physicsSystem, constraint)
				end
				return constraint
			end,

			SetSliderLimits = function(constraint, min, max)
				if not constraint then
					return
				end
				lib.JPH_SliderConstraint_SetLimits(constraint, min, max)
			end,

			SetSliderMotorSettings = function(constraint, maxForce)
				if not constraint then
					return
				end
				local MS = structs.JPH_MotorSettings
				local SS = structs.JPH_SpringSettings
				local settings = ffi.alloc(MS:size(), MS:alignment())
				-- springSettings first (offset 0 within MotorSettings)
				settings:writeu32(MS:offset("springSettings") + SS:offset("mode"), 0) -- FrequencyAndDamping
				settings:writef32(MS:offset("springSettings") + SS:offset("frequencyOrStiffness"), 10.0)
				settings:writef32(MS:offset("springSettings") + SS:offset("damping"), 0.5)
				-- then force limits
				settings:writef32(MS:offset("minForceLimit"), -maxForce)
				settings:writef32(MS:offset("maxForceLimit"), maxForce)
				lib.JPH_SliderConstraint_SetMotorSettings(constraint, settings)
			end,

			SetSliderMotorState = function(constraint, state)
				if not constraint then
					return
				end
				lib.JPH_SliderConstraint_SetMotorState(constraint, state)
			end,

			SetSliderTargetVelocity = function(constraint, velocity)
				if not constraint then
					return
				end
				lib.JPH_SliderConstraint_SetTargetVelocity(constraint, velocity)
			end,

			SetSliderTargetPosition = function(constraint, position)
				if not constraint then
					return
				end
				lib.JPH_SliderConstraint_SetTargetPosition(constraint, position)
			end,

			GetSliderPosition = function(constraint)
				if not constraint then
					return 0
				end
				return lib.JPH_SliderConstraint_GetCurrentPosition(constraint)
			end,

			SetVelocity = function(part, velocity)
				local bodyID = bodiesMap[part]
				if not bodyID then
					return
				end

				local jVel = structs.JPH_Vec3:new(ToJoltVec3(velocity))
				lib.JPH_BodyInterface_SetLinearVelocity(bodyInterface, bodyID, jVel)
			end,

			Unload = function()
				if physicsUnloaded then
					return
				end
				physicsUnloaded = true
				lib.JPH_PhysicsSystem_SetContactListener(physicsSystem, ffi.null)
				if contactListener ~= ffi.null then
					lib.JPH_ContactListener_Destroy(contactListener)
					contactListener = ffi.null
				end
				table.clear(activeContactsByBody)
				pendingTouchEventCount = 0

				-- added this function for
				-- Memory purposes........
				for part, bodyID in pairs(bodiesMap) do
					local connection = bodyConnections[part]
					if connection then
						connection:Disconnect()
					end
					lib.JPH_BodyInterface_RemoveAndDestroyBody(bodyInterface, bodyID)
				end
				table.clear(bodyConnections)
				table.clear(bodiesMap)
				table.clear(movingBodiesMap)
				table.clear(bodyPointerMap)
				table.clear(bodyTransformDirty)
				table.clear(inverseMap)

				lib.JPH_JobSystem_Destroy(jobSystem)
				lib.JPH_PhysicsSystem_Destroy(physicsSystem)
				lib.JPH_Shutdown()
			end,

			DeltatimeMultiplier = 1,
			CollisionSteps = 2,

			GetBodies = function()
				return bodiesMap
			end,

			GetPhysicsBodyCount = function()
				local i = 0
				for _, v in pairs(bodiesMap) do
					i += 1
				end
				return i
			end,

			RemoveConstraint = function(constraint)
				if constraint and constraint ~= ffi.null then
					lib.JPH_PhysicsSystem_RemoveConstraint(physicsSystem, constraint)
				end
			end,

			GetVelocity = function(part)
				local bodyID = bodiesMap[part]
				if not bodyID then
					return Vector3.new()
				end

				local velocity = tempBodyLinear
				lib.JPH_BodyInterface_GetLinearVelocity(bodyInterface, bodyID, velocity)
				return Vector3.new(velocity:readf32(0), velocity:readf32(4), velocity:readf32(8))
			end,

			jolt = {
				lib = jolt.lib,
				structs = jolt.structs,
				physicsSystem = physicsSystem,
				jobSystem = jobSystem,
				bodyInterface = bodyInterface,
				broadPhaseLayerInterface = broadPhaseLayerInterface,
				objectVsBroadPhaseFilter = objectVsBroadPhaseFilter,
				ToJoltVec3 = ToJoltVec3,
				FromJoltVec3 = FromJoltVec3,
				RVec3 = RVec3,
			},
		}

		local lastGravity = nil
		local lastWind = nil

		renderer.Hook.new("Renderstep", function(dt)
			local perfStats = renderer.PerfStats
			local physicsStepMs = 0
			local proxySyncMs = 0
			local proxySyncCount = 0
			if debugBodiesCreated > 0 then
				print(string.format("[Physics] Created %d Jolt bodies this frame", debugBodiesCreated))
				lib.JPH_PhysicsSystem_OptimizeBroadPhase(physicsSystem)
				debugBodiesCreated = 0
			end

			if not game["Workspace"] then
				print("Workspace not found, Whoever renamed it, Good luck developing on your shit..")
				return
			end
			if
				game.Workspace.PhysicsEngine == Enum.PhysicsEngine.Jolt
				or game.Workspace.PhysicsEngine == Enum.PhysicsEngine.Default
			then
				local newGravity = game.Workspace.Gravity
				local newWind = game.Workspace.GlobalWind
				if newGravity ~= lastGravity or newWind ~= lastWind then
					setGravity(physicsSystem, newGravity, newWind)
					lastGravity = newGravity
					lastWind = newWind
				end

				local proxySyncStart = os.clock()
				for part in pairs(bodyTransformDirty) do
					local bodyID = bodiesMap[part]
					if not bodyID or part.Parent == nil then
						bodyTransformDirty[part] = nil
						continue
					end

					if getMotionTypeForPart(part) ~= 2 then
						syncBodyTransformFromPart(part, bodyInterface, bodyID)
						proxySyncCount += 1
					end
					bodyTransformDirty[part] = nil
				end
				proxySyncMs = (os.clock() - proxySyncStart) * 1000

				if next(movingBodiesMap) ~= nil or next(softBodiesMap) ~= nil then
					renderer_signal:Fire("PrePhysics")
					local _pst = os.clock()
					local collisionSteps = math.clamp(
						math.floor(
							(KinemiumPhysicsService.CollisionSteps or 2)
									* (KinemiumPhysicsService.DeltatimeMultiplier or 1)
								+ 0.5
						),
						1,
						8
					)
					lib.JPH_PhysicsSystem_Update(physicsSystem, dt, collisionSteps, jobSystem)
					local _pdur = os.clock() - _pst
					physicsStepMs = _pdur * 1000
					if _pdur > 0.05 then
						print(string.format("[Physics] JPH_PhysicsSystem_Update took %.2f ms", _pdur * 1000))
					end
					renderer_signal:Fire("PhysicsF")
				end

				local _syncStart = os.clock()
				local _nSimulated = 0
				for part, bodyID in pairs(movingBodiesMap) do
					if part.Parent == nil then
						continue
					end

					if lib.JPH_BodyInterface_IsActive(bodyInterface, bodyID) == 0 then
						continue
					end

					_nSimulated += 1

					local cf, linear, angular = CalculateBodyPhysics(part, bodyInterface, bodyID, true)

					if not cf or not part.Parent then
						continue
					end

					if part then
						local currentCFrame = part.CFrame
						local transformChanged = not currentCFrame
							or not currentCFrame:IsSameTransform(cf, 1e-4)
						if transformChanged then
							part.CFrame = cf
						end

						local currentLinear = part.AssemblyLinearVelocity
						if not currentLinear or currentLinear:DistanceSquared(linear) > 1e-8 then
							part.AssemblyLinearVelocity = linear
						end

						local currentAngular = part.AssemblyAngularVelocity
						if not currentAngular or currentAngular:DistanceSquared(angular) > 1e-8 then
							part.AssemblyAngularVelocity = angular
						end

						if transformChanged then
							rawset(part, "__matrixDirty", true)
							rawset(part, "__partAABB", nil)
							local batch = rawget(part, "__workspaceBatch")
							if batch then
								batch.instancesDirty = true
							end
							local chunk = rawget(part, "__workspaceChunk")
							if chunk then
								chunk.instanceDataDirty = true
							end
						end
					end
				end
				local _syncDur = os.clock() - _syncStart
				local moving = 0
				for _ in pairs(movingBodiesMap) do
					moving += 1
				end
				if perfStats then
					perfStats.physics_step_ms = physicsStepMs
					perfStats.physics_sync_ms = _syncDur * 1000
					perfStats.physics_proxy_sync_ms = proxySyncMs
					perfStats.physics_proxy_updates = proxySyncCount
					perfStats.physics_active_bodies = _nSimulated
					perfStats.physics_owned_bodies = moving
					perfStats.physics_collision_steps = KinemiumPhysicsService.CollisionSteps or 2
				end
				if _syncDur > 0.05 then
					print(string.format("[Physics] CFrame Sync took %.2f ms (%d parts)", _syncDur * 1000, _nSimulated))
				end

				for softBody, bodyID in pairs(softBodiesMap) do
					local bodyPtr = bodyPointerMap[softBody]
					if not bodyPtr then
						continue
					end

					local numVertices = lib.JPH_SoftBody_GetNumVertices(bodyPtr)
					local bufferSize = numVertices * structs.JPH_SoftBodyVertex:size()
					local resultBuffer = ffi.alloc(bufferSize, structs.JPH_SoftBodyVertex:alignment())

					lib.JPH_SoftBody_GetVertices(bodyPtr, resultBuffer, numVertices)

					local mesh = softBody.Mesh
					local state = softBodyStates[softBody]
					if mesh and state then
						for index, id in ipairs(state.vIds) do
							local offset = (index - 1) * structs.JPH_SoftBodyVertex:size()
							local px = buffer.readf32(resultBuffer, offset)
							local py = buffer.readf32(resultBuffer, offset + 4)
							local pz = buffer.readf32(resultBuffer, offset + 8)

							mesh._vertices[id] = Vector3.new(px, py, pz)
						end
						mesh._geometryDirty = true
					end
				end
			end

			pollContactEvents()
		end)

		propTable.AddBody = CreateBodyForPart

		propTable.HandleRendererSignal = function(route, data)
			if route == "UpdatePart" or route == "AddedPartToRenderPool" then
				if not data.Parent or not data:IsDescendantOf(game.Workspace) then
					RemoveBody(data)
					return
				end
				if not shouldHavePhysicsBody(data) then
					RemoveBody(data)
					return
				end
				local bodyID = bodiesMap[data]
				if not bodyID then
					CreateBodyForPart(data)
				else
					propTable.UpdatePart(data)
				end
			elseif route == "RemovedPartFromRenderPool" then
				RemoveBody(data)
			end
		end

		table.insert(game.ShutdownCallbacks, propTable.Unload)
		KinemiumPhysicsService:SetProperties(propTable)

		local UPS = game:GetService("UnifiedPhysicsService")
		while not UPS do
			task.wait()
			UPS = game:GetService("UnifiedPhysicsService")
		end

		log("[Physics] Registering Jolt with UnifiedPhysicsService")

		propTable.CreateCharacterController = propTable.CreateHumanoidController
		propTable.DestroyCharacterController = propTable.DestroyHumanoidController
		propTable.StepCharacterController = propTable.StepHumanoidController
		UPS:RegisterEngine("Jolt", propTable)
		if not UPS:GetPrimaryEngineName() then
			UPS:SetPrimaryEngine("Jolt")
		end
	end)
end

return KinemiumPhysicsService
