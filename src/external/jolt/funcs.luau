--!strict
--!optimize 2

-- FFI function table for JoltWrapper.dll.
-- Every entry here corresponds directly to a JPH_API-decorated symbol in
-- external/kine_jolt/include/jph_api.h.  Nothing more, nothing less.

local ffi = zune.ffi

local ptr = ffi.types.pointer
local void = ffi.types.void
local i32 = ffi.types.i32
local u32 = ffi.types.u32
local f32 = ffi.types.float

-- ─── Lifecycle ───────────────────────────────────────────────────────────────

-- int32_t JPH_Init(void)
-- Returns 1 on first init, 0 if already initialised.
local JPH_Init = { returns = i32, args = {} }

-- void JPH_Shutdown(void)
local JPH_Shutdown = { returns = void, args = {} }

-- ─── Job system ──────────────────────────────────────────────────────────────

-- JPH_JobSystemRef JPH_JobSystemThreadPool_Create(const JPH_JobSystemConfig*)
local JPH_JobSystemThreadPool_Create = { returns = ptr, args = { ptr } }

-- void JPH_JobSystem_Destroy(JPH_JobSystemRef)
local JPH_JobSystem_Destroy = { returns = void, args = { ptr } }

-- ─── Broad-phase layer interface ─────────────────────────────────────────────

-- JPH_BroadPhaseLayerInterfaceRef
--   JPH_BroadPhaseLayerInterfaceTable_Create(uint32_t numObjectLayers,
--                                            uint32_t numBroadPhaseLayers)
local JPH_BroadPhaseLayerInterfaceTable_Create = { returns = ptr, args = { u32, u32 } }

-- void JPH_BroadPhaseLayerInterfaceTable_MapObjectToBroadPhaseLayer(
--   JPH_BroadPhaseLayerInterfaceRef, uint32_t objectLayer,
--   uint32_t broadPhaseLayer)
local JPH_BroadPhaseLayerInterfaceTable_MapObjectToBroadPhaseLayer = {
	returns = void,
	args = { ptr, u32, u32 },
}

-- ─── Object-layer pair filter ─────────────────────────────────────────────────

-- JPH_ObjectLayerPairFilterRef
--   JPH_ObjectLayerPairFilterTable_Create(uint32_t numObjectLayers)
local JPH_ObjectLayerPairFilterTable_Create = { returns = ptr, args = { u32 } }

-- void JPH_ObjectLayerPairFilterTable_EnableCollision(
--   JPH_ObjectLayerPairFilterRef, uint32_t layer1, uint32_t layer2)
local JPH_ObjectLayerPairFilterTable_EnableCollision = {
	returns = void,
	args = { ptr, u32, u32 },
}

-- void JPH_ObjectLayerPairFilterTable_DisableCollision(
--   JPH_ObjectLayerPairFilterRef, uint32_t layer1, uint32_t layer2)
local JPH_ObjectLayerPairFilterTable_DisableCollision = {
	returns = void,
	args = { ptr, u32, u32 },
}

-- ─── Object-vs-broad-phase layer filter ──────────────────────────────────────

-- JPH_ObjectVsBroadPhaseLayerFilterRef
--   JPH_ObjectVsBroadPhaseLayerFilterTable_Create(
--     JPH_BroadPhaseLayerInterfaceRef, uint32_t numBroadPhaseLayers,
--     JPH_ObjectLayerPairFilterRef,    uint32_t numObjectLayers)
local JPH_ObjectVsBroadPhaseLayerFilterTable_Create = {
	returns = ptr,
	args = { ptr, u32, ptr, u32 },
}

-- ─── Shapes ───────────────────────────────────────────────────────────────────

-- JPH_ShapeRef JPH_BoxShape_Create(const JPH_Vec3* halfExtent,
--                                  float convexRadius)
local JPH_BoxShape_Create = { returns = ptr, args = { ptr, f32 } }

-- JPH_ShapeRef JPH_SphereShape_Create(float radius)
local JPH_SphereShape_Create = { returns = ptr, args = { f32 } }

-- JPH_ShapeRef JPH_ConvexHullShape_Create(
--   const JPH_Vec3* points, uint32_t pointCount, float maxConvexRadius)
local JPH_ConvexHullShape_Create = { returns = ptr, args = { ptr, u32, f32 } }

-- JPH_ShapeRef JPH_MeshShape_Create(
--   const JPH_Triangle* triangles, uint32_t triangleCount)
local JPH_MeshShape_Create = { returns = ptr, args = { ptr, u32 } }

-- void JPH_Shape_Destroy(JPH_ShapeRef shape)
local JPH_Shape_Destroy = { returns = void, args = { ptr } }

-- ─── Body creation settings ───────────────────────────────────────────────────

-- JPH_BodyCreationSettingsRef JPH_BodyCreationSettings_Create3(
--   JPH_ShapeRef, const JPH_RVec3* position, const JPH_Quat* rotation,
--   int32_t motionType, uint32_t objectLayer)
local JPH_BodyCreationSettings_Create3 = {
	returns = ptr,
	args = { ptr, ptr, ptr, i32, u32 },
}

-- void JPH_BodyCreationSettings_Destroy(JPH_BodyCreationSettingsRef)
local JPH_BodyCreationSettings_Destroy = { returns = void, args = { ptr } }

-- void JPH_BodyCreationSettings_SetAllowSleeping(
--   JPH_BodyCreationSettingsRef, int32_t allow)
local JPH_BodyCreationSettings_SetAllowSleeping = { returns = void, args = { ptr, i32 } }

-- void JPH_BodyCreationSettings_SetAllowDynamicOrKinematic(
--   JPH_BodyCreationSettingsRef, int32_t allow)
local JPH_BodyCreationSettings_SetAllowDynamicOrKinematic = {
	returns = void,
	args = { ptr, i32 },
}

-- void JPH_BodyCreationSettings_SetFriction(
--   JPH_BodyCreationSettingsRef, float friction)
local JPH_BodyCreationSettings_SetFriction = { returns = void, args = { ptr, f32 } }

-- void JPH_BodyCreationSettings_SetRestitution(
--   JPH_BodyCreationSettingsRef, float restitution)
local JPH_BodyCreationSettings_SetRestitution = { returns = void, args = { ptr, f32 } }

-- void JPH_BodyCreationSettings_SetLinearDamping(
--   JPH_BodyCreationSettingsRef, float damping)
local JPH_BodyCreationSettings_SetLinearDamping = { returns = void, args = { ptr, f32 } }

-- void JPH_BodyCreationSettings_SetAngularDamping(
--   JPH_BodyCreationSettingsRef, float damping)
local JPH_BodyCreationSettings_SetAngularDamping = { returns = void, args = { ptr, f32 } }

-- void JPH_BodyCreationSettings_SetGravityFactor(
--   JPH_BodyCreationSettingsRef, float factor)
local JPH_BodyCreationSettings_SetGravityFactor = { returns = void, args = { ptr, f32 } }

-- ─── Physics system ───────────────────────────────────────────────────────────

-- JPH_PhysicsSystemRef JPH_PhysicsSystem_Create(
--   const JPH_PhysicsSystemSettings*)
local JPH_PhysicsSystem_Create = { returns = ptr, args = { ptr } }

-- void JPH_PhysicsSystem_Destroy(JPH_PhysicsSystemRef)
local JPH_PhysicsSystem_Destroy = { returns = void, args = { ptr } }

-- JPH_BodyInterfaceRef JPH_PhysicsSystem_GetBodyInterface(
--   JPH_PhysicsSystemRef)
local JPH_PhysicsSystem_GetBodyInterface = { returns = ptr, args = { ptr } }

-- void JPH_PhysicsSystem_SetGravity(JPH_PhysicsSystemRef,
--                                   const JPH_Vec3* gravity)
local JPH_PhysicsSystem_SetGravity = { returns = void, args = { ptr, ptr } }

-- void JPH_PhysicsSystem_Update(JPH_PhysicsSystemRef, float deltaTime,
--                               int32_t collisionSteps,
--                               JPH_JobSystemRef jobSystem)
local JPH_PhysicsSystem_Update = { returns = void, args = { ptr, f32, i32, ptr } }

-- void JPH_PhysicsSystem_OptimizeBroadPhase(JPH_PhysicsSystemRef)
local JPH_PhysicsSystem_OptimizeBroadPhase = { returns = void, args = { ptr } }

-- void JPH_PhysicsSystem_SetContactListener(JPH_PhysicsSystemRef,
--                                           JPH_ContactListenerRef)
local JPH_PhysicsSystem_SetContactListener = { returns = void, args = { ptr, ptr } }

-- int32_t JPH_PhysicsSystem_CastRay(JPH_PhysicsSystemRef,
--   const JPH_RVec3* origin, const JPH_Vec3* direction,
--   const JPH_BodyID* bodyIDs, uint32_t bodyIDCount, int32_t filterMode,
--   JPH_RayCastResult* outResult)
local JPH_PhysicsSystem_CastRay = {
	returns = i32,
	args = { ptr, ptr, ptr, ptr, u32, i32, ptr },
}

-- ─── Body interface ───────────────────────────────────────────────────────────

-- JPH_BodyRef JPH_BodyInterface_CreateBody(JPH_BodyInterfaceRef,
--                                          JPH_BodyCreationSettingsRef)
local JPH_BodyInterface_CreateBody = { returns = ptr, args = { ptr, ptr } }

-- void JPH_BodyInterface_AddBody(JPH_BodyInterfaceRef, JPH_BodyID,
--                                int32_t activationMode)
-- activationMode: 0 = Activate, 1 = DontActivate
local JPH_BodyInterface_AddBody = { returns = void, args = { ptr, u32, i32 } }

-- void JPH_BodyInterface_RemoveAndDestroyBody(JPH_BodyInterfaceRef,
--                                             JPH_BodyID)
local JPH_BodyInterface_RemoveAndDestroyBody = { returns = void, args = { ptr, u32 } }

-- void JPH_BodyInterface_SetShape(JPH_BodyInterfaceRef, JPH_BodyID,
--                                 JPH_ShapeRef shape,
--                                 int32_t updateMassProperties,
--                                 int32_t activationMode)
local JPH_BodyInterface_SetShape = {
	returns = void,
	args = { ptr, u32, ptr, i32, i32 },
}

-- void JPH_BodyInterface_SetMotionType(JPH_BodyInterfaceRef, JPH_BodyID,
--                                      int32_t motionType,
--                                      int32_t activationMode)
-- motionType: 0=Static, 1=Kinematic, 2=Dynamic
local JPH_BodyInterface_SetMotionType = { returns = void, args = { ptr, u32, i32, i32 } }

-- void JPH_BodyInterface_SetObjectLayer(JPH_BodyInterfaceRef, JPH_BodyID,
--                                       uint32_t layer)
local JPH_BodyInterface_SetObjectLayer = { returns = void, args = { ptr, u32, u32 } }

-- void JPH_BodyInterface_ActivateBody(JPH_BodyInterfaceRef, JPH_BodyID)
local JPH_BodyInterface_ActivateBody = { returns = void, args = { ptr, u32 } }

-- int32_t JPH_BodyInterface_IsActive(JPH_BodyInterfaceRef, JPH_BodyID)
local JPH_BodyInterface_IsActive = { returns = i32, args = { ptr, u32 } }

-- int32_t JPH_BodyInterface_IsAdded(JPH_BodyInterfaceRef, JPH_BodyID)
local JPH_BodyInterface_IsAdded = { returns = i32, args = { ptr, u32 } }

-- void JPH_BodyInterface_SetPosition(JPH_BodyInterfaceRef, JPH_BodyID,
--                                    const JPH_RVec3* position,
--                                    int32_t activationMode)
local JPH_BodyInterface_SetPosition = { returns = void, args = { ptr, u32, ptr, i32 } }

-- void JPH_BodyInterface_SetPositionAndRotation(JPH_BodyInterfaceRef,
--                                               JPH_BodyID,
--                                               const JPH_RVec3* position,
--                                               const JPH_Quat* rotation,
--                                               int32_t activationMode)
local JPH_BodyInterface_SetPositionAndRotation = {
	returns = void,
	args = { ptr, u32, ptr, ptr, i32 },
}

-- void JPH_BodyInterface_SetRotation(JPH_BodyInterfaceRef, JPH_BodyID,
--                                    const JPH_Quat* rotation,
--                                    int32_t activationMode)
local JPH_BodyInterface_SetRotation = { returns = void, args = { ptr, u32, ptr, i32 } }

-- void JPH_BodyInterface_SetLinearVelocity(JPH_BodyInterfaceRef, JPH_BodyID,
--                                          const JPH_Vec3* velocity)
local JPH_BodyInterface_SetLinearVelocity = { returns = void, args = { ptr, u32, ptr } }

-- void JPH_BodyInterface_SetAngularVelocity(JPH_BodyInterfaceRef, JPH_BodyID,
--                                           const JPH_Vec3* velocity)
local JPH_BodyInterface_SetAngularVelocity = { returns = void, args = { ptr, u32, ptr } }

-- void JPH_BodyInterface_GetPosition(JPH_BodyInterfaceRef, JPH_BodyID,
--                                    JPH_RVec3* outPosition)
local JPH_BodyInterface_GetPosition = { returns = void, args = { ptr, u32, ptr } }

-- void JPH_BodyInterface_GetPositionAndRotation(JPH_BodyInterfaceRef,
--                                               JPH_BodyID,
--                                               JPH_RVec3* outPosition,
--                                               JPH_Quat* outRotation)
local JPH_BodyInterface_GetPositionAndRotation = {
	returns = void,
	args = { ptr, u32, ptr, ptr },
}

-- void JPH_BodyInterface_GetRotation(JPH_BodyInterfaceRef, JPH_BodyID,
--                                    JPH_Quat* outRotation)
local JPH_BodyInterface_GetRotation = { returns = void, args = { ptr, u32, ptr } }

-- void JPH_BodyInterface_GetLinearVelocity(JPH_BodyInterfaceRef, JPH_BodyID,
--                                          JPH_Vec3* outVelocity)
local JPH_BodyInterface_GetLinearVelocity = { returns = void, args = { ptr, u32, ptr } }

-- void JPH_BodyInterface_GetAngularVelocity(JPH_BodyInterfaceRef, JPH_BodyID,
--                                           JPH_Vec3* outVelocity)
local JPH_BodyInterface_GetAngularVelocity = { returns = void, args = { ptr, u32, ptr } }

-- void JPH_BodyInterface_AddImpulse(JPH_BodyInterfaceRef, JPH_BodyID,
--                                   const JPH_Vec3* impulse)
local JPH_BodyInterface_AddImpulse = { returns = void, args = { ptr, u32, ptr } }

-- void JPH_BodyInterface_AddForce(JPH_BodyInterfaceRef, JPH_BodyID,
--                                 const JPH_Vec3* force)
local JPH_BodyInterface_AddForce = { returns = void, args = { ptr, u32, ptr } }

-- void JPH_BodyInterface_AddForce2(JPH_BodyInterfaceRef, JPH_BodyID,
--                                  const JPH_Vec3* force,
--                                  const JPH_RVec3* position)
local JPH_BodyInterface_AddForce2 = { returns = void, args = { ptr, u32, ptr, ptr } }

-- void JPH_BodyInterface_AddTorque(JPH_BodyInterfaceRef, JPH_BodyID,
--                                  const JPH_Vec3* torque)
local JPH_BodyInterface_AddTorque = { returns = void, args = { ptr, u32, ptr } }

-- ─── Body ─────────────────────────────────────────────────────────────────────

-- JPH_BodyID JPH_Body_GetID(JPH_BodyRef)
local JPH_Body_GetID = { returns = u32, args = { ptr } }

-- JPH_MotionPropertiesRef JPH_Body_GetMotionProperties(JPH_BodyRef)
local JPH_Body_GetMotionProperties = { returns = ptr, args = { ptr } }

-- void JPH_Body_SetFriction(JPH_BodyRef, float friction)
local JPH_Body_SetFriction = { returns = void, args = { ptr, f32 } }

-- ─── Motion properties ────────────────────────────────────────────────────────

-- void JPH_MotionProperties_ScaleToMass(JPH_MotionPropertiesRef, float mass)
local JPH_MotionProperties_ScaleToMass = { returns = void, args = { ptr, f32 } }

-- ─── Contact listener ─────────────────────────────────────────────────────────

-- JPH_ContactListenerRef JPH_ContactListener_Create(void)
local JPH_ContactListener_Create = { returns = ptr, args = {} }

-- void JPH_ContactListener_Destroy(JPH_ContactListenerRef)
local JPH_ContactListener_Destroy = { returns = void, args = { ptr } }

-- uint32_t JPH_ContactListener_PollEvents(
--   JPH_ContactListenerRef, const JPH_ContactListener_Procs*, uint32_t maxEvents)
-- Pass maxEvents = 0 to drain the entire queue.
local JPH_ContactListener_PollEvents = { returns = u32, args = { ptr, ptr, u32 } }

-- ─── Constraints ─────────────────────────────────────────────────────────────

local JPH_PhysicsSystem_AddConstraint = { returns = void, args = { ptr, ptr } }
local JPH_PhysicsSystem_RemoveConstraint = { returns = void, args = { ptr, ptr } }
local JPH_FixedConstraintSettings_Init = { returns = void, args = { ptr } }
local JPH_FixedConstraint_Create = { returns = ptr, args = { ptr, ptr, ptr } }
local JPH_DistanceConstraintSettings_Init = { returns = void, args = { ptr } }
local JPH_DistanceConstraint_Create = { returns = ptr, args = { ptr, ptr, ptr } }
local JPH_DistanceConstraint_SetDistance = { returns = void, args = { ptr, f32, f32 } }
local JPH_DistanceConstraint_SetLimitsSpringSettings = { returns = void, args = { ptr, ptr } }
local JPH_HingeConstraintSettings_Init = { returns = void, args = { ptr } }
local JPH_HingeConstraint_Create = { returns = ptr, args = { ptr, ptr, ptr } }
local JPH_HingeConstraint_SetMotorState = { returns = void, args = { ptr, i32 } }
local JPH_HingeConstraint_SetTargetAngularVelocity = { returns = void, args = { ptr, f32 } }
local JPH_HingeConstraint_SetTargetAngle = { returns = void, args = { ptr, f32 } }
local JPH_HingeConstraint_GetCurrentAngle = { returns = f32, args = { ptr } }
local JPH_HingeConstraint_SetLimits = { returns = void, args = { ptr, f32, f32 } }
local JPH_HingeConstraint_SetMotorSettings = { returns = void, args = { ptr, ptr } }
local JPH_SliderConstraintSettings_Init = { returns = void, args = { ptr } }
local JPH_SliderConstraint_Create = { returns = ptr, args = { ptr, ptr, ptr } }
local JPH_SliderConstraint_SetLimits = { returns = void, args = { ptr, f32, f32 } }
local JPH_SliderConstraint_SetMotorSettings = { returns = void, args = { ptr, ptr } }
local JPH_SliderConstraint_SetMotorState = { returns = void, args = { ptr, i32 } }
local JPH_SliderConstraint_SetTargetVelocity = { returns = void, args = { ptr, f32 } }
local JPH_SliderConstraint_SetTargetPosition = { returns = void, args = { ptr, f32 } }
local JPH_SliderConstraint_GetCurrentPosition = { returns = f32, args = { ptr } }
local JPH_SixDOFConstraintSettings_Init = { returns = void, args = { ptr } }
local JPH_SixDOFConstraintSettings_MakeFixedAxis = { returns = void, args = { ptr, u32 } }
local JPH_SixDOFConstraintSettings_MakeFreeAxis = { returns = void, args = { ptr, u32 } }
local JPH_SixDOFConstraintSettings_SetLimitedAxis = { returns = void, args = { ptr, u32, f32, f32 } }
local JPH_SixDOFConstraintSettings_SetLimitsSpringSettings = { returns = void, args = { ptr, u32, ptr } }
local JPH_SixDOFConstraint_Create = { returns = ptr, args = { ptr, ptr, ptr } }

-- ─────────────────────────────────────────────────────────────────────────────

return {
	-- Lifecycle
	JPH_Init = JPH_Init,
	JPH_Shutdown = JPH_Shutdown,

	-- Job system
	JPH_JobSystemThreadPool_Create = JPH_JobSystemThreadPool_Create,
	JPH_JobSystem_Destroy = JPH_JobSystem_Destroy,

	-- Broad-phase layer interface
	JPH_BroadPhaseLayerInterfaceTable_Create = JPH_BroadPhaseLayerInterfaceTable_Create,
	JPH_BroadPhaseLayerInterfaceTable_MapObjectToBroadPhaseLayer = JPH_BroadPhaseLayerInterfaceTable_MapObjectToBroadPhaseLayer,

	-- Object-layer pair filter
	JPH_ObjectLayerPairFilterTable_Create = JPH_ObjectLayerPairFilterTable_Create,
	JPH_ObjectLayerPairFilterTable_EnableCollision = JPH_ObjectLayerPairFilterTable_EnableCollision,
	JPH_ObjectLayerPairFilterTable_DisableCollision = JPH_ObjectLayerPairFilterTable_DisableCollision,

	-- Object-vs-broad-phase layer filter
	JPH_ObjectVsBroadPhaseLayerFilterTable_Create = JPH_ObjectVsBroadPhaseLayerFilterTable_Create,

	-- Shapes
	JPH_BoxShape_Create = JPH_BoxShape_Create,
	JPH_SphereShape_Create = JPH_SphereShape_Create,
	JPH_ConvexHullShape_Create = JPH_ConvexHullShape_Create,
	JPH_MeshShape_Create = JPH_MeshShape_Create,
	JPH_Shape_Destroy = JPH_Shape_Destroy,

	-- Body creation settings
	JPH_BodyCreationSettings_Create3 = JPH_BodyCreationSettings_Create3,
	JPH_BodyCreationSettings_Destroy = JPH_BodyCreationSettings_Destroy,
	JPH_BodyCreationSettings_SetAllowSleeping = JPH_BodyCreationSettings_SetAllowSleeping,
	JPH_BodyCreationSettings_SetAllowDynamicOrKinematic = JPH_BodyCreationSettings_SetAllowDynamicOrKinematic,
	JPH_BodyCreationSettings_SetFriction = JPH_BodyCreationSettings_SetFriction,
	JPH_BodyCreationSettings_SetRestitution = JPH_BodyCreationSettings_SetRestitution,
	JPH_BodyCreationSettings_SetLinearDamping = JPH_BodyCreationSettings_SetLinearDamping,
	JPH_BodyCreationSettings_SetAngularDamping = JPH_BodyCreationSettings_SetAngularDamping,
	JPH_BodyCreationSettings_SetGravityFactor = JPH_BodyCreationSettings_SetGravityFactor,

	-- Physics system
	JPH_PhysicsSystem_Create = JPH_PhysicsSystem_Create,
	JPH_PhysicsSystem_Destroy = JPH_PhysicsSystem_Destroy,
	JPH_PhysicsSystem_GetBodyInterface = JPH_PhysicsSystem_GetBodyInterface,
	JPH_PhysicsSystem_SetGravity = JPH_PhysicsSystem_SetGravity,
	JPH_PhysicsSystem_Update = JPH_PhysicsSystem_Update,
	JPH_PhysicsSystem_OptimizeBroadPhase = JPH_PhysicsSystem_OptimizeBroadPhase,
	JPH_PhysicsSystem_SetContactListener = JPH_PhysicsSystem_SetContactListener,
	JPH_PhysicsSystem_CastRay = JPH_PhysicsSystem_CastRay,
	JPH_PhysicsSystem_AddConstraint = JPH_PhysicsSystem_AddConstraint,
	JPH_PhysicsSystem_RemoveConstraint = JPH_PhysicsSystem_RemoveConstraint,

	-- Constraints
	JPH_FixedConstraintSettings_Init = JPH_FixedConstraintSettings_Init,
	JPH_FixedConstraint_Create = JPH_FixedConstraint_Create,
	JPH_DistanceConstraintSettings_Init = JPH_DistanceConstraintSettings_Init,
	JPH_DistanceConstraint_Create = JPH_DistanceConstraint_Create,
	JPH_DistanceConstraint_SetDistance = JPH_DistanceConstraint_SetDistance,
	JPH_DistanceConstraint_SetLimitsSpringSettings = JPH_DistanceConstraint_SetLimitsSpringSettings,
	JPH_HingeConstraintSettings_Init = JPH_HingeConstraintSettings_Init,
	JPH_HingeConstraint_Create = JPH_HingeConstraint_Create,
	JPH_HingeConstraint_SetMotorState = JPH_HingeConstraint_SetMotorState,
	JPH_HingeConstraint_SetTargetAngularVelocity = JPH_HingeConstraint_SetTargetAngularVelocity,
	JPH_HingeConstraint_SetTargetAngle = JPH_HingeConstraint_SetTargetAngle,
	JPH_HingeConstraint_GetCurrentAngle = JPH_HingeConstraint_GetCurrentAngle,
	JPH_HingeConstraint_SetLimits = JPH_HingeConstraint_SetLimits,
	JPH_HingeConstraint_SetMotorSettings = JPH_HingeConstraint_SetMotorSettings,
	JPH_SliderConstraintSettings_Init = JPH_SliderConstraintSettings_Init,
	JPH_SliderConstraint_Create = JPH_SliderConstraint_Create,
	JPH_SliderConstraint_SetLimits = JPH_SliderConstraint_SetLimits,
	JPH_SliderConstraint_SetMotorSettings = JPH_SliderConstraint_SetMotorSettings,
	JPH_SliderConstraint_SetMotorState = JPH_SliderConstraint_SetMotorState,
	JPH_SliderConstraint_SetTargetVelocity = JPH_SliderConstraint_SetTargetVelocity,
	JPH_SliderConstraint_SetTargetPosition = JPH_SliderConstraint_SetTargetPosition,
	JPH_SliderConstraint_GetCurrentPosition = JPH_SliderConstraint_GetCurrentPosition,
	JPH_SixDOFConstraintSettings_Init = JPH_SixDOFConstraintSettings_Init,
	JPH_SixDOFConstraintSettings_MakeFixedAxis = JPH_SixDOFConstraintSettings_MakeFixedAxis,
	JPH_SixDOFConstraintSettings_MakeFreeAxis = JPH_SixDOFConstraintSettings_MakeFreeAxis,
	JPH_SixDOFConstraintSettings_SetLimitedAxis = JPH_SixDOFConstraintSettings_SetLimitedAxis,
	JPH_SixDOFConstraintSettings_SetLimitsSpringSettings = JPH_SixDOFConstraintSettings_SetLimitsSpringSettings,
	JPH_SixDOFConstraint_Create = JPH_SixDOFConstraint_Create,

	-- Body interface
	JPH_BodyInterface_CreateBody = JPH_BodyInterface_CreateBody,
	JPH_BodyInterface_AddBody = JPH_BodyInterface_AddBody,
	JPH_BodyInterface_RemoveAndDestroyBody = JPH_BodyInterface_RemoveAndDestroyBody,
	JPH_BodyInterface_SetShape = JPH_BodyInterface_SetShape,
	JPH_BodyInterface_SetMotionType = JPH_BodyInterface_SetMotionType,
	JPH_BodyInterface_SetObjectLayer = JPH_BodyInterface_SetObjectLayer,
	JPH_BodyInterface_ActivateBody = JPH_BodyInterface_ActivateBody,
	JPH_BodyInterface_IsActive = JPH_BodyInterface_IsActive,
	JPH_BodyInterface_IsAdded = JPH_BodyInterface_IsAdded,
	JPH_BodyInterface_SetPosition = JPH_BodyInterface_SetPosition,
	JPH_BodyInterface_SetPositionAndRotation = JPH_BodyInterface_SetPositionAndRotation,
	JPH_BodyInterface_SetRotation = JPH_BodyInterface_SetRotation,
	JPH_BodyInterface_SetLinearVelocity = JPH_BodyInterface_SetLinearVelocity,
	JPH_BodyInterface_SetAngularVelocity = JPH_BodyInterface_SetAngularVelocity,
	JPH_BodyInterface_GetPosition = JPH_BodyInterface_GetPosition,
	JPH_BodyInterface_GetPositionAndRotation = JPH_BodyInterface_GetPositionAndRotation,
	JPH_BodyInterface_GetRotation = JPH_BodyInterface_GetRotation,
	JPH_BodyInterface_GetLinearVelocity = JPH_BodyInterface_GetLinearVelocity,
	JPH_BodyInterface_GetAngularVelocity = JPH_BodyInterface_GetAngularVelocity,
	JPH_BodyInterface_AddImpulse = JPH_BodyInterface_AddImpulse,
	JPH_BodyInterface_AddForce = JPH_BodyInterface_AddForce,
	JPH_BodyInterface_AddForce2 = JPH_BodyInterface_AddForce2,
	JPH_BodyInterface_AddTorque = JPH_BodyInterface_AddTorque,

	-- Body
	JPH_Body_GetID = JPH_Body_GetID,
	JPH_Body_GetMotionProperties = JPH_Body_GetMotionProperties,
	JPH_Body_SetFriction = JPH_Body_SetFriction,

	-- Motion properties
	JPH_MotionProperties_ScaleToMass = JPH_MotionProperties_ScaleToMass,

	-- Contact listener
	JPH_ContactListener_Create = JPH_ContactListener_Create,
	JPH_ContactListener_Destroy = JPH_ContactListener_Destroy,
	JPH_ContactListener_PollEvents = JPH_ContactListener_PollEvents,
}
