local ffi = zune.ffi

local zembed = require("@zembed")

local name = "KinemiumLibs." .. ffi.suffix
local path = if zembed.IsEmbedded() then zembed.RuntimePath(name) else "./vendor/" .. name

local types = ffi.types

local void = types.void
local ptr = types.pointer
local f32 = types.float
local i32 = types.i32

local function fn(returns, ...)
	return {
		returns = returns,
		args = { ... },
	}
end

return ffi.dlopen(path, {
	-- World

	Kine_Box2D_CreateWorld = fn(ptr, f32, f32),
	Kine_Box2D_DestroyWorld = fn(void, ptr),
	Kine_Box2D_IsWorldValid = fn(i32, ptr),

	Kine_Box2D_SetGravity = fn(void, ptr, f32, f32),
	Kine_Box2D_GetGravity = fn(void, ptr, ptr, ptr),

	Kine_Box2D_Step = fn(void, ptr, f32, i32),
	Kine_Box2D_StepWithGravity = fn(void, ptr, f32, i32, f32, f32),

	-- Bodies

	Kine_Box2D_CreateBoxBody = fn(ptr, ptr, f32, f32, f32, f32, f32, i32, f32, f32, f32, i32),

	Kine_Box2D_DestroyBody = fn(void, ptr),
	Kine_Box2D_IsBodyValid = fn(i32, ptr),

	Kine_Box2D_SetBodyTransform = fn(void, ptr, f32, f32, f32),
	Kine_Box2D_GetBodyTransform = fn(void, ptr, ptr, ptr, ptr),

	-- Old compatibility API:
	-- 0 = static
	-- non-zero = dynamic
	Kine_Box2D_SetBodyType = fn(void, ptr, i32),

	-- Full body type API:
	-- 0 = static
	-- 1 = kinematic
	-- 2 = dynamic
	Kine_Box2D_SetBodyMotionType = fn(void, ptr, i32),

	Kine_Box2D_SetBodyVelocity = fn(void, ptr, f32, f32, f32),
	Kine_Box2D_GetBodyVelocity = fn(void, ptr, ptr, ptr, ptr),

	Kine_Box2D_ApplyForceToCenter = fn(void, ptr, f32, f32, i32),
	Kine_Box2D_ApplyImpulseToCenter = fn(void, ptr, f32, f32, i32),

	-- Distance Constraint

	Kine_Box2D_CreateDistanceJoint = fn(ptr, ptr, ptr, ptr, f32, f32, f32, f32, f32, i32, f32, f32, i32, f32, f32, i32),

	Kine_Box2D_SetDistanceLength = fn(void, ptr, f32),
	Kine_Box2D_GetDistanceLength = fn(f32, ptr),
	Kine_Box2D_GetDistanceCurrentLength = fn(f32, ptr),

	Kine_Box2D_SetDistanceSpring = fn(void, ptr, i32, f32, f32),
	Kine_Box2D_SetDistanceSpringForceRange = fn(void, ptr, f32, f32),

	Kine_Box2D_SetDistanceLimits = fn(void, ptr, i32, f32, f32),

	Kine_Box2D_SetDistanceMotor = fn(void, ptr, i32, f32, f32),
	Kine_Box2D_GetDistanceMotorForce = fn(f32, ptr),

	-- Hinge / Revolute Constraint

	Kine_Box2D_CreateHingeJoint = fn(
		ptr,
		ptr,
		ptr,
		ptr,
		f32,
		f32,
		f32,
		f32,
		f32,
		f32,
		i32,
		f32,
		f32,
		i32,
		f32,
		f32,
		i32
	),

	Kine_Box2D_SetHingeSpring = fn(void, ptr, i32, f32, f32, f32),
	Kine_Box2D_SetHingeLimits = fn(void, ptr, i32, f32, f32),
	Kine_Box2D_SetHingeMotor = fn(void, ptr, i32, f32, f32),

	Kine_Box2D_GetHingeAngle = fn(f32, ptr),
	Kine_Box2D_GetHingeMotorTorque = fn(f32, ptr),

	-- Weld Constraint

	Kine_Box2D_CreateWeldJoint = fn(ptr, ptr, ptr, ptr, f32, f32, f32, f32, f32, f32, f32, f32, f32, f32, i32, i32),

	Kine_Box2D_SetWeldTuning = fn(void, ptr, f32, f32, f32, f32),

	-- Prismatic / Slider Constraint

	Kine_Box2D_CreatePrismaticJoint = fn(ptr, ptr, ptr, ptr, f32, f32, f32, f32, f32, f32, i32, f32, f32, f32, i32, f32, f32, i32, f32, f32, i32),

	Kine_Box2D_SetPrismaticSpring = fn(void, ptr, i32, f32, f32, f32),

	Kine_Box2D_SetPrismaticLimits = fn(void, ptr, i32, f32, f32),

	Kine_Box2D_SetPrismaticMotor = fn(void, ptr, i32, f32, f32),

	Kine_Box2D_GetPrismaticTranslation = fn(f32, ptr),
	Kine_Box2D_GetPrismaticSpeed = fn(f32, ptr),
	Kine_Box2D_GetPrismaticMotorForce = fn(f32, ptr),

	-- Wheel Constraint

	Kine_Box2D_CreateWheelJoint = fn(ptr, ptr, ptr, ptr, f32, f32, f32, f32, f32, f32, i32, f32, f32, i32, f32, f32, i32, f32, f32, i32),

	Kine_Box2D_SetWheelSpring = fn(void, ptr, i32, f32, f32),

	Kine_Box2D_SetWheelLimits = fn(void, ptr, i32, f32, f32),

	Kine_Box2D_SetWheelMotor = fn(void, ptr, i32, f32, f32),

	Kine_Box2D_GetWheelMotorTorque = fn(f32, ptr),

	-- Motor Constraint

	Kine_Box2D_CreateMotorJoint = fn(ptr, ptr, ptr, ptr, f32, f32, f32, f32, f32, f32, f32, f32, f32, f32, f32, f32, f32, f32, f32, f32, f32, i32),

	Kine_Box2D_SetMotorJointVelocity = fn(void, ptr, f32, f32, f32),

	Kine_Box2D_SetMotorJointVelocityLimits = fn(void, ptr, f32, f32),

	Kine_Box2D_SetMotorJointSpring = fn(void, ptr, f32, f32, f32, f32, f32, f32),

	-- Filter Constraint

	Kine_Box2D_CreateFilterJoint = fn(ptr, ptr, ptr, ptr),

	-- Generic Constraint API

	Kine_Box2D_DestroyJoint = fn(void, ptr),
	Kine_Box2D_IsJointValid = fn(i32, ptr),

	Kine_Box2D_GetJointType = fn(i32, ptr),

	Kine_Box2D_SetJointCollideConnected = fn(void, ptr, i32),
	Kine_Box2D_GetJointCollideConnected = fn(i32, ptr),

	Kine_Box2D_WakeJointBodies = fn(void, ptr),

	Kine_Box2D_GetJointConstraintForce = fn(void, ptr, ptr, ptr),

	Kine_Box2D_GetJointConstraintTorque = fn(f32, ptr),

	Kine_Box2D_GetJointLinearSeparation = fn(f32, ptr),
	Kine_Box2D_GetJointAngularSeparation = fn(f32, ptr),

	Kine_Box2D_ShouldBreakJoint = fn(i32, ptr, f32, f32),

	Kine_Box2D_SetJointConstraintTuning = fn(void, ptr, f32, f32),

	Kine_Box2D_GetJointConstraintTuning = fn(void, ptr, ptr, ptr),

	Kine_Box2D_SetJointEventThresholds = fn(void, ptr, f32, f32),

	Kine_Box2D_GetJointEventThresholds = fn(void, ptr, ptr, ptr),

	Kine_Box2D_SetJointFrames = fn(void, ptr, f32, f32, f32, f32, f32, f32),
})
