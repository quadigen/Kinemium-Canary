// Kinemium Box2D C ABI wrapper
//
// Targeted at the Box2D development API used by the original wrapper:
// joint definitions expose `base.localFrameA/B` and `b2DestroyJoint(id, wakeAttached)`.
// This API shape is different from tagged Box2D v3.1.1 and from newer `main` revisions.

#include <box2d/box2d.h>

#include <algorithm>
#include <cmath>
#include <new>

#if defined(_WIN32)
#define KINE_BOX2D_API extern "C" __declspec(dllexport)
#else
#define KINE_BOX2D_API extern "C" __attribute__((visibility("default")))
#endif

namespace
{
constexpr float kMinLength = 0.01f;
constexpr float kMaxHingeAngle = 0.99f * B2_PI;
constexpr int kDefaultSubSteps = 4;

struct KineBox2DWorld
{
    b2WorldId id = b2_nullWorldId;
};

struct KineBox2DBody
{
    b2BodyId id = b2_nullBodyId;
    b2ShapeId shape = b2_nullShapeId;
};

struct KineBox2DJoint
{
    b2JointId id = b2_nullJointId;
};

inline bool IsFinite(float value)
{
    return std::isfinite(value);
}

inline float NonNegative(float value)
{
    return IsFinite(value) ? std::max(value, 0.0f) : 0.0f;
}

inline float PositiveLength(float value)
{
    return IsFinite(value) ? std::max(value, kMinLength) : kMinLength;
}

inline KineBox2DWorld* WorldFrom(void* handle)
{
    auto* world = static_cast<KineBox2DWorld*>(handle);
    return world && b2World_IsValid(world->id) ? world : nullptr;
}

inline KineBox2DBody* BodyFrom(void* handle)
{
    auto* body = static_cast<KineBox2DBody*>(handle);
    return body && b2Body_IsValid(body->id) ? body : nullptr;
}

inline KineBox2DJoint* JointFrom(void* handle)
{
    auto* joint = static_cast<KineBox2DJoint*>(handle);
    return joint && b2Joint_IsValid(joint->id) ? joint : nullptr;
}

inline KineBox2DJoint* JointFrom(void* handle, b2JointType expectedType)
{
    auto* joint = JointFrom(handle);
    return joint && b2Joint_GetType(joint->id) == expectedType ? joint : nullptr;
}

inline bool SameWorld(const KineBox2DWorld* world, const KineBox2DBody* body)
{
    if (!world || !body)
    {
        return false;
    }

    return b2StoreWorldId(b2Body_GetWorld(body->id)) == b2StoreWorldId(world->id);
}

inline bool CanJoin(const KineBox2DWorld* world, const KineBox2DBody* bodyA, const KineBox2DBody* bodyB)
{
    if (!world || !bodyA || !bodyB)
    {
        return false;
    }

    if (!SameWorld(world, bodyA) || !SameWorld(world, bodyB))
    {
        return false;
    }

    return !B2_ID_EQUALS(bodyA->id, bodyB->id);
}

KineBox2DJoint* WrapJoint(b2JointId id)
{
    if (!b2Joint_IsValid(id))
    {
        return nullptr;
    }

    auto* joint = new (std::nothrow) KineBox2DJoint{id};
    if (!joint)
    {
        b2DestroyJoint(id, true);
        return nullptr;
    }

    return joint;
}

b2Vec2 NormalizeAxis(float x, float y, bool* ok)
{
    if (!IsFinite(x) || !IsFinite(y))
    {
        *ok = false;
        return {1.0f, 0.0f};
    }

    const float lengthSquared = x * x + y * y;
    if (lengthSquared <= 1.0e-12f)
    {
        *ok = false;
        return {1.0f, 0.0f};
    }

    const float inverseLength = 1.0f / std::sqrt(lengthSquared);
    *ok = true;
    return {x * inverseLength, y * inverseLength};
}

bool SetAxisFrames(
    b2JointDef& base,
    const KineBox2DBody* bodyA,
    const KineBox2DBody* bodyB,
    float anchorAx,
    float anchorAy,
    float anchorBx,
    float anchorBy,
    float axisAx,
    float axisAy)
{
    bool validAxis = false;
    const b2Vec2 localAxisA = NormalizeAxis(axisAx, axisAy, &validAxis);
    if (!validAxis)
    {
        return false;
    }

    const b2Vec2 worldAxis = b2Body_GetWorldVector(bodyA->id, localAxisA);
    b2Vec2 localAxisB = b2Body_GetLocalVector(bodyB->id, worldAxis);

    bool validAxisB = false;
    localAxisB = NormalizeAxis(localAxisB.x, localAxisB.y, &validAxisB);
    if (!validAxisB)
    {
        return false;
    }

    base.localFrameA.p = {anchorAx, anchorAy};
    base.localFrameA.q = b2MakeRotFromUnitVector(localAxisA);
    base.localFrameB.p = {anchorBx, anchorBy};
    base.localFrameB.q = b2MakeRotFromUnitVector(localAxisB);
    return true;
}

void SetFrames(
    b2JointDef& base,
    float ax,
    float ay,
    float ar,
    float bx,
    float by,
    float br)
{
    base.localFrameA.p = {ax, ay};
    base.localFrameA.q = b2MakeRot(ar);
    base.localFrameB.p = {bx, by};
    base.localFrameB.q = b2MakeRot(br);
}

void SetPreservedFrames(b2JointDef& base, const KineBox2DBody* bodyA, const KineBox2DBody* bodyB)
{
    const b2Pos anchor = b2Body_GetPosition(bodyA->id);
    base.localFrameA.p = {0.0f, 0.0f};
    base.localFrameA.q = b2Rot_identity;
    base.localFrameB.p = b2Body_GetLocalPoint(bodyB->id, anchor);
    base.localFrameB.q = b2InvMulRot(b2Body_GetRotation(bodyB->id), b2Body_GetRotation(bodyA->id));
}

void SanitizeRange(float& lower, float& upper)
{
    if (!IsFinite(lower))
    {
        lower = 0.0f;
    }
    if (!IsFinite(upper))
    {
        upper = lower;
    }
    if (lower > upper)
    {
        std::swap(lower, upper);
    }
}

void SanitizeHingeRange(float& lower, float& upper)
{
    lower = IsFinite(lower) ? std::clamp(lower, -kMaxHingeAngle, kMaxHingeAngle) : 0.0f;
    upper = IsFinite(upper) ? std::clamp(upper, -kMaxHingeAngle, kMaxHingeAngle) : 0.0f;
    if (lower > upper)
    {
        std::swap(lower, upper);
    }
}
} // namespace

// -----------------------------------------------------------------------------
// World
// -----------------------------------------------------------------------------

KINE_BOX2D_API void* Kine_Box2D_CreateWorld(float gravityX, float gravityY)
{
    if (!IsFinite(gravityX) || !IsFinite(gravityY))
    {
        return nullptr;
    }

    b2WorldDef definition = b2DefaultWorldDef();
    definition.gravity = {gravityX, gravityY};

    const b2WorldId id = b2CreateWorld(&definition);
    if (!b2World_IsValid(id))
    {
        return nullptr;
    }

    auto* world = new (std::nothrow) KineBox2DWorld{id};
    if (!world)
    {
        b2DestroyWorld(id);
        return nullptr;
    }

    return world;
}

KINE_BOX2D_API void Kine_Box2D_DestroyWorld(void* handle)
{
    auto* world = static_cast<KineBox2DWorld*>(handle);
    if (!world)
    {
        return;
    }

    if (b2World_IsValid(world->id))
    {
        b2DestroyWorld(world->id);
    }

    world->id = b2_nullWorldId;
    delete world;
}

KINE_BOX2D_API int Kine_Box2D_IsWorldValid(void* handle)
{
    return WorldFrom(handle) != nullptr;
}

KINE_BOX2D_API void Kine_Box2D_SetGravity(void* handle, float x, float y)
{
    auto* world = WorldFrom(handle);
    if (!world || !IsFinite(x) || !IsFinite(y))
    {
        return;
    }

    b2World_SetGravity(world->id, {x, y});
}

KINE_BOX2D_API void Kine_Box2D_GetGravity(void* handle, float* x, float* y)
{
    auto* world = WorldFrom(handle);
    if (!world)
    {
        return;
    }

    const b2Vec2 gravity = b2World_GetGravity(world->id);
    if (x)
    {
        *x = gravity.x;
    }
    if (y)
    {
        *y = gravity.y;
    }
}

KINE_BOX2D_API void Kine_Box2D_Step(void* handle, float deltaTime, int subSteps)
{
    auto* world = WorldFrom(handle);
    if (!world || !IsFinite(deltaTime) || deltaTime <= 0.0f)
    {
        return;
    }

    b2World_Step(world->id, deltaTime, subSteps > 0 ? subSteps : kDefaultSubSteps);
}

KINE_BOX2D_API void Kine_Box2D_StepWithGravity(
    void* handle,
    float deltaTime,
    int subSteps,
    float gravityX,
    float gravityY)
{
    auto* world = WorldFrom(handle);
    if (!world || !IsFinite(deltaTime) || deltaTime <= 0.0f || !IsFinite(gravityX) || !IsFinite(gravityY))
    {
        return;
    }

    b2World_SetGravity(world->id, {gravityX, gravityY});
    b2World_Step(world->id, deltaTime, subSteps > 0 ? subSteps : kDefaultSubSteps);
}

// -----------------------------------------------------------------------------
// Bodies
// -----------------------------------------------------------------------------

KINE_BOX2D_API void* Kine_Box2D_CreateBoxBody(
    void* worldHandle,
    float x,
    float y,
    float width,
    float height,
    float angle,
    int dynamicBody,
    float density,
    float friction,
    float restitution,
    int sensor)
{
    auto* world = WorldFrom(worldHandle);
    if (!world || !IsFinite(x) || !IsFinite(y) || !IsFinite(width) || !IsFinite(height) || !IsFinite(angle))
    {
        return nullptr;
    }

    if (width <= 0.0f || height <= 0.0f)
    {
        return nullptr;
    }

    b2BodyDef bodyDefinition = b2DefaultBodyDef();
    bodyDefinition.type = dynamicBody != 0 ? b2_dynamicBody : b2_staticBody;
    bodyDefinition.position = {x, y};
    bodyDefinition.rotation = b2MakeRot(angle);

    const b2BodyId bodyId = b2CreateBody(world->id, &bodyDefinition);
    if (!b2Body_IsValid(bodyId))
    {
        return nullptr;
    }

    b2ShapeDef shapeDefinition = b2DefaultShapeDef();
    shapeDefinition.density = NonNegative(density);
    shapeDefinition.material.friction = NonNegative(friction);
    shapeDefinition.material.restitution = NonNegative(restitution);
    shapeDefinition.isSensor = sensor != 0;

    const b2Polygon polygon = b2MakeBox(width * 0.5f, height * 0.5f);
    const b2ShapeId shapeId = b2CreatePolygonShape(bodyId, &shapeDefinition, &polygon);
    if (!b2Shape_IsValid(shapeId))
    {
        b2DestroyBody(bodyId);
        return nullptr;
    }

    auto* body = new (std::nothrow) KineBox2DBody{bodyId, shapeId};
    if (!body)
    {
        b2DestroyBody(bodyId);
        return nullptr;
    }

    return body;
}

KINE_BOX2D_API void Kine_Box2D_DestroyBody(void* handle)
{
    auto* body = static_cast<KineBox2DBody*>(handle);
    if (!body)
    {
        return;
    }

    if (b2Body_IsValid(body->id))
    {
        b2DestroyBody(body->id);
    }

    body->id = b2_nullBodyId;
    body->shape = b2_nullShapeId;
    delete body;
}

KINE_BOX2D_API int Kine_Box2D_IsBodyValid(void* handle)
{
    return BodyFrom(handle) != nullptr;
}

KINE_BOX2D_API void Kine_Box2D_SetBodyTransform(void* handle, float x, float y, float angle)
{
    auto* body = BodyFrom(handle);
    if (!body || !IsFinite(x) || !IsFinite(y) || !IsFinite(angle))
    {
        return;
    }

    b2Body_SetTransform(body->id, {x, y}, b2MakeRot(angle));
}

KINE_BOX2D_API void Kine_Box2D_GetBodyTransform(void* handle, float* x, float* y, float* angle)
{
    auto* body = BodyFrom(handle);
    if (!body)
    {
        return;
    }

    const b2Pos position = b2Body_GetPosition(body->id);
    const b2Rot rotation = b2Body_GetRotation(body->id);

    if (x)
    {
        *x = static_cast<float>(position.x);
    }
    if (y)
    {
        *y = static_cast<float>(position.y);
    }
    if (angle)
    {
        *angle = std::atan2(rotation.s, rotation.c);
    }
}

// Compatibility with the old wrapper: 0 = static, non-zero = dynamic.
KINE_BOX2D_API void Kine_Box2D_SetBodyType(void* handle, int dynamicBody)
{
    auto* body = BodyFrom(handle);
    if (body)
    {
        b2Body_SetType(body->id, dynamicBody != 0 ? b2_dynamicBody : b2_staticBody);
    }
}

// Full body type control: 0 = static, 1 = kinematic, 2 = dynamic.
KINE_BOX2D_API void Kine_Box2D_SetBodyMotionType(void* handle, int bodyType)
{
    auto* body = BodyFrom(handle);
    if (!body)
    {
        return;
    }

    const int clampedType = std::clamp(bodyType, static_cast<int>(b2_staticBody), static_cast<int>(b2_dynamicBody));
    b2Body_SetType(body->id, static_cast<b2BodyType>(clampedType));
}

KINE_BOX2D_API void Kine_Box2D_SetBodyVelocity(void* handle, float x, float y, float angularVelocity)
{
    auto* body = BodyFrom(handle);
    if (!body || !IsFinite(x) || !IsFinite(y) || !IsFinite(angularVelocity))
    {
        return;
    }

    b2Body_SetLinearVelocity(body->id, {x, y});
    b2Body_SetAngularVelocity(body->id, angularVelocity);
}

KINE_BOX2D_API void Kine_Box2D_GetBodyVelocity(void* handle, float* x, float* y, float* angularVelocity)
{
    auto* body = BodyFrom(handle);
    if (!body)
    {
        return;
    }

    const b2Vec2 velocity = b2Body_GetLinearVelocity(body->id);
    if (x)
    {
        *x = velocity.x;
    }
    if (y)
    {
        *y = velocity.y;
    }
    if (angularVelocity)
    {
        *angularVelocity = b2Body_GetAngularVelocity(body->id);
    }
}

KINE_BOX2D_API void Kine_Box2D_ApplyForceToCenter(void* handle, float x, float y, int wake)
{
    auto* body = BodyFrom(handle);
    if (body && IsFinite(x) && IsFinite(y))
    {
        b2Body_ApplyForceToCenter(body->id, {x, y}, wake != 0);
    }
}

KINE_BOX2D_API void Kine_Box2D_ApplyImpulseToCenter(void* handle, float x, float y, int wake)
{
    auto* body = BodyFrom(handle);
    if (body && IsFinite(x) && IsFinite(y))
    {
        b2Body_ApplyLinearImpulseToCenter(body->id, {x, y}, wake != 0);
    }
}

// -----------------------------------------------------------------------------
// Joint creation
// -----------------------------------------------------------------------------

KINE_BOX2D_API void* Kine_Box2D_CreateDistanceJoint(
    void* worldHandle,
    void* bodyAHandle,
    void* bodyBHandle,
    float anchorAx,
    float anchorAy,
    float anchorBx,
    float anchorBy,
    float length,
    int springEnabled,
    float hertz,
    float dampingRatio,
    int limitEnabled,
    float minLength,
    float maxLength,
    int collideConnected)
{
    auto* world = WorldFrom(worldHandle);
    auto* bodyA = BodyFrom(bodyAHandle);
    auto* bodyB = BodyFrom(bodyBHandle);
    if (!CanJoin(world, bodyA, bodyB))
    {
        return nullptr;
    }

    b2DistanceJointDef definition = b2DefaultDistanceJointDef();
    definition.base.bodyIdA = bodyA->id;
    definition.base.bodyIdB = bodyB->id;
    definition.base.localFrameA.p = {anchorAx, anchorAy};
    definition.base.localFrameB.p = {anchorBx, anchorBy};
    definition.base.collideConnected = collideConnected != 0;

    definition.length = PositiveLength(length);
    // Box2D ignores distance limits while the spring mode is disabled.
    // Enabling a limit therefore also enables spring mode (hertz may still be zero).
    definition.enableSpring = springEnabled != 0 || limitEnabled != 0;
    definition.hertz = NonNegative(hertz);
    definition.dampingRatio = NonNegative(dampingRatio);

    minLength = PositiveLength(minLength);
    maxLength = PositiveLength(maxLength);
    if (minLength > maxLength)
    {
        std::swap(minLength, maxLength);
    }

    definition.enableLimit = limitEnabled != 0;
    definition.minLength = minLength;
    definition.maxLength = maxLength;

    return WrapJoint(b2CreateDistanceJoint(world->id, &definition));
}

KINE_BOX2D_API void* Kine_Box2D_CreateHingeJoint(
    void* worldHandle,
    void* bodyAHandle,
    void* bodyBHandle,
    float anchorAx,
    float anchorAy,
    float frameAngleA,
    float anchorBx,
    float anchorBy,
    float frameAngleB,
    int limitsEnabled,
    float lowerAngle,
    float upperAngle,
    int motorEnabled,
    float motorSpeed,
    float maxMotorTorque,
    int collideConnected)
{
    auto* world = WorldFrom(worldHandle);
    auto* bodyA = BodyFrom(bodyAHandle);
    auto* bodyB = BodyFrom(bodyBHandle);
    if (!CanJoin(world, bodyA, bodyB))
    {
        return nullptr;
    }

    SanitizeHingeRange(lowerAngle, upperAngle);

    b2RevoluteJointDef definition = b2DefaultRevoluteJointDef();
    definition.base.bodyIdA = bodyA->id;
    definition.base.bodyIdB = bodyB->id;
    definition.base.collideConnected = collideConnected != 0;
    SetFrames(definition.base, anchorAx, anchorAy, frameAngleA, anchorBx, anchorBy, frameAngleB);

    definition.enableLimit = limitsEnabled != 0;
    definition.lowerAngle = lowerAngle;
    definition.upperAngle = upperAngle;
    definition.enableMotor = motorEnabled != 0;
    definition.motorSpeed = IsFinite(motorSpeed) ? motorSpeed : 0.0f;
    definition.maxMotorTorque = NonNegative(maxMotorTorque);

    return WrapJoint(b2CreateRevoluteJoint(world->id, &definition));
}

KINE_BOX2D_API void* Kine_Box2D_CreateWeldJoint(
    void* worldHandle,
    void* bodyAHandle,
    void* bodyBHandle,
    float anchorAx,
    float anchorAy,
    float frameAngleA,
    float anchorBx,
    float anchorBy,
    float frameAngleB,
    float linearHertz,
    float angularHertz,
    float linearDamping,
    float angularDamping,
    int preserveInitialTransform,
    int collideConnected)
{
    auto* world = WorldFrom(worldHandle);
    auto* bodyA = BodyFrom(bodyAHandle);
    auto* bodyB = BodyFrom(bodyBHandle);
    if (!CanJoin(world, bodyA, bodyB))
    {
        return nullptr;
    }

    b2WeldJointDef definition = b2DefaultWeldJointDef();
    definition.base.bodyIdA = bodyA->id;
    definition.base.bodyIdB = bodyB->id;
    definition.base.collideConnected = collideConnected != 0;

    if (preserveInitialTransform != 0)
    {
        SetPreservedFrames(definition.base, bodyA, bodyB);
    }
    else
    {
        SetFrames(definition.base, anchorAx, anchorAy, frameAngleA, anchorBx, anchorBy, frameAngleB);
    }

    definition.linearHertz = NonNegative(linearHertz);
    definition.angularHertz = NonNegative(angularHertz);
    definition.linearDampingRatio = NonNegative(linearDamping);
    definition.angularDampingRatio = NonNegative(angularDamping);

    return WrapJoint(b2CreateWeldJoint(world->id, &definition));
}

KINE_BOX2D_API void* Kine_Box2D_CreatePrismaticJoint(
    void* worldHandle,
    void* bodyAHandle,
    void* bodyBHandle,
    float anchorAx,
    float anchorAy,
    float anchorBx,
    float anchorBy,
    float axisAx,
    float axisAy,
    int springEnabled,
    float springHertz,
    float springDamping,
    float targetTranslation,
    int limitEnabled,
    float lowerTranslation,
    float upperTranslation,
    int motorEnabled,
    float motorSpeed,
    float maxMotorForce,
    int collideConnected)
{
    auto* world = WorldFrom(worldHandle);
    auto* bodyA = BodyFrom(bodyAHandle);
    auto* bodyB = BodyFrom(bodyBHandle);
    if (!CanJoin(world, bodyA, bodyB))
    {
        return nullptr;
    }

    SanitizeRange(lowerTranslation, upperTranslation);

    b2PrismaticJointDef definition = b2DefaultPrismaticJointDef();
    definition.base.bodyIdA = bodyA->id;
    definition.base.bodyIdB = bodyB->id;
    definition.base.collideConnected = collideConnected != 0;

    if (!SetAxisFrames(
            definition.base,
            bodyA,
            bodyB,
            anchorAx,
            anchorAy,
            anchorBx,
            anchorBy,
            axisAx,
            axisAy))
    {
        return nullptr;
    }

    definition.enableSpring = springEnabled != 0;
    definition.hertz = NonNegative(springHertz);
    definition.dampingRatio = NonNegative(springDamping);
    definition.targetTranslation = IsFinite(targetTranslation) ? targetTranslation : 0.0f;
    definition.enableLimit = limitEnabled != 0;
    definition.lowerTranslation = lowerTranslation;
    definition.upperTranslation = upperTranslation;
    definition.enableMotor = motorEnabled != 0;
    definition.motorSpeed = IsFinite(motorSpeed) ? motorSpeed : 0.0f;
    definition.maxMotorForce = NonNegative(maxMotorForce);

    return WrapJoint(b2CreatePrismaticJoint(world->id, &definition));
}

KINE_BOX2D_API void* Kine_Box2D_CreateWheelJoint(
    void* worldHandle,
    void* bodyAHandle,
    void* bodyBHandle,
    float anchorAx,
    float anchorAy,
    float anchorBx,
    float anchorBy,
    float axisAx,
    float axisAy,
    int springEnabled,
    float springHertz,
    float springDamping,
    int limitEnabled,
    float lowerTranslation,
    float upperTranslation,
    int motorEnabled,
    float motorSpeed,
    float maxMotorTorque,
    int collideConnected)
{
    auto* world = WorldFrom(worldHandle);
    auto* bodyA = BodyFrom(bodyAHandle);
    auto* bodyB = BodyFrom(bodyBHandle);
    if (!CanJoin(world, bodyA, bodyB))
    {
        return nullptr;
    }

    SanitizeRange(lowerTranslation, upperTranslation);

    b2WheelJointDef definition = b2DefaultWheelJointDef();
    definition.base.bodyIdA = bodyA->id;
    definition.base.bodyIdB = bodyB->id;
    definition.base.collideConnected = collideConnected != 0;

    if (!SetAxisFrames(
            definition.base,
            bodyA,
            bodyB,
            anchorAx,
            anchorAy,
            anchorBx,
            anchorBy,
            axisAx,
            axisAy))
    {
        return nullptr;
    }

    definition.enableSpring = springEnabled != 0;
    definition.hertz = NonNegative(springHertz);
    definition.dampingRatio = NonNegative(springDamping);
    definition.enableLimit = limitEnabled != 0;
    definition.lowerTranslation = lowerTranslation;
    definition.upperTranslation = upperTranslation;
    definition.enableMotor = motorEnabled != 0;
    definition.motorSpeed = IsFinite(motorSpeed) ? motorSpeed : 0.0f;
    definition.maxMotorTorque = NonNegative(maxMotorTorque);

    return WrapJoint(b2CreateWheelJoint(world->id, &definition));
}

KINE_BOX2D_API void* Kine_Box2D_CreateMotorJoint(
    void* worldHandle,
    void* bodyAHandle,
    void* bodyBHandle,
    float anchorAx,
    float anchorAy,
    float frameAngleA,
    float anchorBx,
    float anchorBy,
    float frameAngleB,
    float linearVelocityX,
    float linearVelocityY,
    float maxVelocityForce,
    float angularVelocity,
    float maxVelocityTorque,
    float linearHertz,
    float linearDamping,
    float maxSpringForce,
    float angularHertz,
    float angularDamping,
    float maxSpringTorque,
    int collideConnected)
{
    auto* world = WorldFrom(worldHandle);
    auto* bodyA = BodyFrom(bodyAHandle);
    auto* bodyB = BodyFrom(bodyBHandle);
    if (!CanJoin(world, bodyA, bodyB))
    {
        return nullptr;
    }

    b2MotorJointDef definition = b2DefaultMotorJointDef();
    definition.base.bodyIdA = bodyA->id;
    definition.base.bodyIdB = bodyB->id;
    definition.base.collideConnected = collideConnected != 0;
    SetFrames(definition.base, anchorAx, anchorAy, frameAngleA, anchorBx, anchorBy, frameAngleB);

    definition.linearVelocity = {
        IsFinite(linearVelocityX) ? linearVelocityX : 0.0f,
        IsFinite(linearVelocityY) ? linearVelocityY : 0.0f};
    definition.maxVelocityForce = NonNegative(maxVelocityForce);
    definition.angularVelocity = IsFinite(angularVelocity) ? angularVelocity : 0.0f;
    definition.maxVelocityTorque = NonNegative(maxVelocityTorque);
    definition.linearHertz = NonNegative(linearHertz);
    definition.linearDampingRatio = NonNegative(linearDamping);
    definition.maxSpringForce = NonNegative(maxSpringForce);
    definition.angularHertz = NonNegative(angularHertz);
    definition.angularDampingRatio = NonNegative(angularDamping);
    definition.maxSpringTorque = NonNegative(maxSpringTorque);

    return WrapJoint(b2CreateMotorJoint(world->id, &definition));
}

KINE_BOX2D_API void* Kine_Box2D_CreateFilterJoint(
    void* worldHandle,
    void* bodyAHandle,
    void* bodyBHandle)
{
    auto* world = WorldFrom(worldHandle);
    auto* bodyA = BodyFrom(bodyAHandle);
    auto* bodyB = BodyFrom(bodyBHandle);
    if (!CanJoin(world, bodyA, bodyB))
    {
        return nullptr;
    }

    b2FilterJointDef definition = b2DefaultFilterJointDef();
    definition.base.bodyIdA = bodyA->id;
    definition.base.bodyIdB = bodyB->id;
    definition.base.collideConnected = false;
    return WrapJoint(b2CreateFilterJoint(world->id, &definition));
}

// -----------------------------------------------------------------------------
// Generic joint / constraint control
// -----------------------------------------------------------------------------

KINE_BOX2D_API void Kine_Box2D_DestroyJoint(void* handle)
{
    auto* joint = static_cast<KineBox2DJoint*>(handle);
    if (!joint)
    {
        return;
    }

    if (b2Joint_IsValid(joint->id))
    {
        b2DestroyJoint(joint->id, true);
    }

    joint->id = b2_nullJointId;
    delete joint;
}

KINE_BOX2D_API int Kine_Box2D_IsJointValid(void* handle)
{
    return JointFrom(handle) != nullptr;
}

KINE_BOX2D_API int Kine_Box2D_GetJointType(void* handle)
{
    auto* joint = JointFrom(handle);
    return joint ? static_cast<int>(b2Joint_GetType(joint->id)) : -1;
}

KINE_BOX2D_API void Kine_Box2D_SetJointCollideConnected(void* handle, int collideConnected)
{
    auto* joint = JointFrom(handle);
    if (joint)
    {
        b2Joint_SetCollideConnected(joint->id, collideConnected != 0);
    }
}

KINE_BOX2D_API int Kine_Box2D_GetJointCollideConnected(void* handle)
{
    auto* joint = JointFrom(handle);
    return joint ? b2Joint_GetCollideConnected(joint->id) : 0;
}

KINE_BOX2D_API void Kine_Box2D_WakeJointBodies(void* handle)
{
    auto* joint = JointFrom(handle);
    if (joint)
    {
        b2Joint_WakeBodies(joint->id);
    }
}

KINE_BOX2D_API void Kine_Box2D_GetJointConstraintForce(void* handle, float* x, float* y)
{
    auto* joint = JointFrom(handle);
    if (!joint)
    {
        return;
    }

    const b2Vec2 force = b2Joint_GetConstraintForce(joint->id);
    if (x)
    {
        *x = force.x;
    }
    if (y)
    {
        *y = force.y;
    }
}

KINE_BOX2D_API float Kine_Box2D_GetJointConstraintTorque(void* handle)
{
    auto* joint = JointFrom(handle);
    return joint ? b2Joint_GetConstraintTorque(joint->id) : 0.0f;
}

KINE_BOX2D_API float Kine_Box2D_GetJointLinearSeparation(void* handle)
{
    auto* joint = JointFrom(handle);
    return joint ? b2Joint_GetLinearSeparation(joint->id) : 0.0f;
}

KINE_BOX2D_API float Kine_Box2D_GetJointAngularSeparation(void* handle)
{
    auto* joint = JointFrom(handle);
    return joint ? b2Joint_GetAngularSeparation(joint->id) : 0.0f;
}

KINE_BOX2D_API int Kine_Box2D_ShouldBreakJoint(void* handle, float maxForce, float maxTorque)
{
    auto* joint = JointFrom(handle);
    if (!joint)
    {
        return 0;
    }

    const bool checkForce = IsFinite(maxForce) && maxForce > 0.0f;
    const bool checkTorque = IsFinite(maxTorque) && maxTorque > 0.0f;
    if (!checkForce && !checkTorque)
    {
        return 0;
    }

    if (checkForce)
    {
        const b2Vec2 force = b2Joint_GetConstraintForce(joint->id);
        const float forceSquared = force.x * force.x + force.y * force.y;
        if (forceSquared > maxForce * maxForce)
        {
            return 1;
        }
    }

    if (checkTorque && std::fabs(b2Joint_GetConstraintTorque(joint->id)) > maxTorque)
    {
        return 1;
    }

    return 0;
}

KINE_BOX2D_API void Kine_Box2D_SetJointConstraintTuning(void* handle, float hertz, float dampingRatio)
{
    auto* joint = JointFrom(handle);
    if (joint)
    {
        b2Joint_SetConstraintTuning(joint->id, NonNegative(hertz), NonNegative(dampingRatio));
    }
}

KINE_BOX2D_API void Kine_Box2D_GetJointConstraintTuning(void* handle, float* hertz, float* dampingRatio)
{
    auto* joint = JointFrom(handle);
    if (joint)
    {
        b2Joint_GetConstraintTuning(joint->id, hertz, dampingRatio);
    }
}

// These thresholds generate Box2D joint events. They do not automatically destroy/break a joint.
KINE_BOX2D_API void Kine_Box2D_SetJointEventThresholds(void* handle, float forceThreshold, float torqueThreshold)
{
    auto* joint = JointFrom(handle);
    if (!joint)
    {
        return;
    }

    b2Joint_SetForceThreshold(joint->id, NonNegative(forceThreshold));
    b2Joint_SetTorqueThreshold(joint->id, NonNegative(torqueThreshold));
}

KINE_BOX2D_API void Kine_Box2D_GetJointEventThresholds(void* handle, float* forceThreshold, float* torqueThreshold)
{
    auto* joint = JointFrom(handle);
    if (!joint)
    {
        return;
    }

    if (forceThreshold)
    {
        *forceThreshold = b2Joint_GetForceThreshold(joint->id);
    }
    if (torqueThreshold)
    {
        *torqueThreshold = b2Joint_GetTorqueThreshold(joint->id);
    }
}

KINE_BOX2D_API void Kine_Box2D_SetJointFrames(
    void* handle,
    float anchorAx,
    float anchorAy,
    float frameAngleA,
    float anchorBx,
    float anchorBy,
    float frameAngleB)
{
    auto* joint = JointFrom(handle);
    if (!joint)
    {
        return;
    }

    b2Transform frameA = {};
    frameA.p = {anchorAx, anchorAy};
    frameA.q = b2MakeRot(frameAngleA);

    b2Transform frameB = {};
    frameB.p = {anchorBx, anchorBy};
    frameB.q = b2MakeRot(frameAngleB);

    b2Joint_SetLocalFrameA(joint->id, frameA);
    b2Joint_SetLocalFrameB(joint->id, frameB);
}

// -----------------------------------------------------------------------------
// Distance constraints
// -----------------------------------------------------------------------------

KINE_BOX2D_API void Kine_Box2D_SetDistanceLength(void* handle, float length)
{
    auto* joint = JointFrom(handle, b2_distanceJoint);
    if (joint)
    {
        b2DistanceJoint_SetLength(joint->id, PositiveLength(length));
    }
}

KINE_BOX2D_API float Kine_Box2D_GetDistanceLength(void* handle)
{
    auto* joint = JointFrom(handle, b2_distanceJoint);
    return joint ? b2DistanceJoint_GetLength(joint->id) : 0.0f;
}

KINE_BOX2D_API float Kine_Box2D_GetDistanceCurrentLength(void* handle)
{
    auto* joint = JointFrom(handle, b2_distanceJoint);
    return joint ? b2DistanceJoint_GetCurrentLength(joint->id) : 0.0f;
}

KINE_BOX2D_API void Kine_Box2D_SetDistanceSpring(void* handle, int enabled, float hertz, float dampingRatio)
{
    auto* joint = JointFrom(handle, b2_distanceJoint);
    if (!joint)
    {
        return;
    }

    b2DistanceJoint_EnableSpring(joint->id, enabled != 0);
    b2DistanceJoint_SetSpringHertz(joint->id, NonNegative(hertz));
    b2DistanceJoint_SetSpringDampingRatio(joint->id, NonNegative(dampingRatio));
}

KINE_BOX2D_API void Kine_Box2D_SetDistanceSpringForceRange(void* handle, float lowerForce, float upperForce)
{
    auto* joint = JointFrom(handle, b2_distanceJoint);
    if (!joint)
    {
        return;
    }

    if (!IsFinite(lowerForce))
    {
        lowerForce = 0.0f;
    }
    if (!IsFinite(upperForce))
    {
        upperForce = 0.0f;
    }
    if (lowerForce > upperForce)
    {
        std::swap(lowerForce, upperForce);
    }

    b2DistanceJoint_SetSpringForceRange(joint->id, lowerForce, upperForce);
}

KINE_BOX2D_API void Kine_Box2D_SetDistanceLimits(void* handle, int enabled, float minLength, float maxLength)
{
    auto* joint = JointFrom(handle, b2_distanceJoint);
    if (!joint)
    {
        return;
    }

    minLength = PositiveLength(minLength);
    maxLength = PositiveLength(maxLength);
    if (minLength > maxLength)
    {
        std::swap(minLength, maxLength);
    }

    b2DistanceJoint_SetLengthRange(joint->id, minLength, maxLength);
    if (enabled != 0)
    {
        b2DistanceJoint_EnableSpring(joint->id, true);
    }
    b2DistanceJoint_EnableLimit(joint->id, enabled != 0);
}

KINE_BOX2D_API void Kine_Box2D_SetDistanceMotor(void* handle, int enabled, float speed, float maxForce)
{
    auto* joint = JointFrom(handle, b2_distanceJoint);
    if (!joint)
    {
        return;
    }

    b2DistanceJoint_SetMotorSpeed(joint->id, IsFinite(speed) ? speed : 0.0f);
    b2DistanceJoint_SetMaxMotorForce(joint->id, NonNegative(maxForce));
    if (enabled != 0)
    {
        b2DistanceJoint_EnableSpring(joint->id, true);
    }
    b2DistanceJoint_EnableMotor(joint->id, enabled != 0);
}

KINE_BOX2D_API float Kine_Box2D_GetDistanceMotorForce(void* handle)
{
    auto* joint = JointFrom(handle, b2_distanceJoint);
    return joint ? b2DistanceJoint_GetMotorForce(joint->id) : 0.0f;
}

// -----------------------------------------------------------------------------
// Hinge / revolute constraints
// -----------------------------------------------------------------------------

KINE_BOX2D_API void Kine_Box2D_SetHingeSpring(
    void* handle,
    int enabled,
    float targetAngle,
    float hertz,
    float dampingRatio)
{
    auto* joint = JointFrom(handle, b2_revoluteJoint);
    if (!joint)
    {
        return;
    }

    b2RevoluteJoint_SetTargetAngle(joint->id, IsFinite(targetAngle) ? targetAngle : 0.0f);
    b2RevoluteJoint_SetSpringHertz(joint->id, NonNegative(hertz));
    b2RevoluteJoint_SetSpringDampingRatio(joint->id, NonNegative(dampingRatio));
    b2RevoluteJoint_EnableSpring(joint->id, enabled != 0);
}

KINE_BOX2D_API void Kine_Box2D_SetHingeLimits(void* handle, int enabled, float lowerAngle, float upperAngle)
{
    auto* joint = JointFrom(handle, b2_revoluteJoint);
    if (!joint)
    {
        return;
    }

    SanitizeHingeRange(lowerAngle, upperAngle);
    b2RevoluteJoint_SetLimits(joint->id, lowerAngle, upperAngle);
    b2RevoluteJoint_EnableLimit(joint->id, enabled != 0);
}

KINE_BOX2D_API void Kine_Box2D_SetHingeMotor(void* handle, int enabled, float speed, float maxTorque)
{
    auto* joint = JointFrom(handle, b2_revoluteJoint);
    if (!joint)
    {
        return;
    }

    b2RevoluteJoint_SetMotorSpeed(joint->id, IsFinite(speed) ? speed : 0.0f);
    b2RevoluteJoint_SetMaxMotorTorque(joint->id, NonNegative(maxTorque));
    b2RevoluteJoint_EnableMotor(joint->id, enabled != 0);
}

KINE_BOX2D_API float Kine_Box2D_GetHingeAngle(void* handle)
{
    auto* joint = JointFrom(handle, b2_revoluteJoint);
    return joint ? b2RevoluteJoint_GetAngle(joint->id) : 0.0f;
}

KINE_BOX2D_API float Kine_Box2D_GetHingeMotorTorque(void* handle)
{
    auto* joint = JointFrom(handle, b2_revoluteJoint);
    return joint ? b2RevoluteJoint_GetMotorTorque(joint->id) : 0.0f;
}

// -----------------------------------------------------------------------------
// Prismatic / slider constraints
// -----------------------------------------------------------------------------

KINE_BOX2D_API void Kine_Box2D_SetPrismaticSpring(
    void* handle,
    int enabled,
    float targetTranslation,
    float hertz,
    float dampingRatio)
{
    auto* joint = JointFrom(handle, b2_prismaticJoint);
    if (!joint)
    {
        return;
    }

    b2PrismaticJoint_SetTargetTranslation(joint->id, IsFinite(targetTranslation) ? targetTranslation : 0.0f);
    b2PrismaticJoint_SetSpringHertz(joint->id, NonNegative(hertz));
    b2PrismaticJoint_SetSpringDampingRatio(joint->id, NonNegative(dampingRatio));
    b2PrismaticJoint_EnableSpring(joint->id, enabled != 0);
}

KINE_BOX2D_API void Kine_Box2D_SetPrismaticLimits(void* handle, int enabled, float lower, float upper)
{
    auto* joint = JointFrom(handle, b2_prismaticJoint);
    if (!joint)
    {
        return;
    }

    SanitizeRange(lower, upper);
    b2PrismaticJoint_SetLimits(joint->id, lower, upper);
    b2PrismaticJoint_EnableLimit(joint->id, enabled != 0);
}

KINE_BOX2D_API void Kine_Box2D_SetPrismaticMotor(void* handle, int enabled, float speed, float maxForce)
{
    auto* joint = JointFrom(handle, b2_prismaticJoint);
    if (!joint)
    {
        return;
    }

    b2PrismaticJoint_SetMotorSpeed(joint->id, IsFinite(speed) ? speed : 0.0f);
    b2PrismaticJoint_SetMaxMotorForce(joint->id, NonNegative(maxForce));
    b2PrismaticJoint_EnableMotor(joint->id, enabled != 0);
}

KINE_BOX2D_API float Kine_Box2D_GetPrismaticTranslation(void* handle)
{
    auto* joint = JointFrom(handle, b2_prismaticJoint);
    return joint ? b2PrismaticJoint_GetTranslation(joint->id) : 0.0f;
}

KINE_BOX2D_API float Kine_Box2D_GetPrismaticSpeed(void* handle)
{
    auto* joint = JointFrom(handle, b2_prismaticJoint);
    return joint ? b2PrismaticJoint_GetSpeed(joint->id) : 0.0f;
}

KINE_BOX2D_API float Kine_Box2D_GetPrismaticMotorForce(void* handle)
{
    auto* joint = JointFrom(handle, b2_prismaticJoint);
    return joint ? b2PrismaticJoint_GetMotorForce(joint->id) : 0.0f;
}

// -----------------------------------------------------------------------------
// Wheel constraints
// -----------------------------------------------------------------------------

KINE_BOX2D_API void Kine_Box2D_SetWheelSpring(void* handle, int enabled, float hertz, float dampingRatio)
{
    auto* joint = JointFrom(handle, b2_wheelJoint);
    if (!joint)
    {
        return;
    }

    b2WheelJoint_SetSpringHertz(joint->id, NonNegative(hertz));
    b2WheelJoint_SetSpringDampingRatio(joint->id, NonNegative(dampingRatio));
    b2WheelJoint_EnableSpring(joint->id, enabled != 0);
}

KINE_BOX2D_API void Kine_Box2D_SetWheelLimits(void* handle, int enabled, float lower, float upper)
{
    auto* joint = JointFrom(handle, b2_wheelJoint);
    if (!joint)
    {
        return;
    }

    SanitizeRange(lower, upper);
    b2WheelJoint_SetLimits(joint->id, lower, upper);
    b2WheelJoint_EnableLimit(joint->id, enabled != 0);
}

KINE_BOX2D_API void Kine_Box2D_SetWheelMotor(void* handle, int enabled, float speed, float maxTorque)
{
    auto* joint = JointFrom(handle, b2_wheelJoint);
    if (!joint)
    {
        return;
    }

    b2WheelJoint_SetMotorSpeed(joint->id, IsFinite(speed) ? speed : 0.0f);
    b2WheelJoint_SetMaxMotorTorque(joint->id, NonNegative(maxTorque));
    b2WheelJoint_EnableMotor(joint->id, enabled != 0);
}

KINE_BOX2D_API float Kine_Box2D_GetWheelMotorTorque(void* handle)
{
    auto* joint = JointFrom(handle, b2_wheelJoint);
    return joint ? b2WheelJoint_GetMotorTorque(joint->id) : 0.0f;
}

// -----------------------------------------------------------------------------
// Weld constraints
// -----------------------------------------------------------------------------

KINE_BOX2D_API void Kine_Box2D_SetWeldTuning(
    void* handle,
    float linearHertz,
    float linearDampingRatio,
    float angularHertz,
    float angularDampingRatio)
{
    auto* joint = JointFrom(handle, b2_weldJoint);
    if (!joint)
    {
        return;
    }

    b2WeldJoint_SetLinearHertz(joint->id, NonNegative(linearHertz));
    b2WeldJoint_SetLinearDampingRatio(joint->id, NonNegative(linearDampingRatio));
    b2WeldJoint_SetAngularHertz(joint->id, NonNegative(angularHertz));
    b2WeldJoint_SetAngularDampingRatio(joint->id, NonNegative(angularDampingRatio));
}

// -----------------------------------------------------------------------------
// Motor constraints
// -----------------------------------------------------------------------------

KINE_BOX2D_API void Kine_Box2D_SetMotorJointVelocity(
    void* handle,
    float linearX,
    float linearY,
    float angularVelocity)
{
    auto* joint = JointFrom(handle, b2_motorJoint);
    if (!joint)
    {
        return;
    }

    b2MotorJoint_SetLinearVelocity(
        joint->id,
        {IsFinite(linearX) ? linearX : 0.0f, IsFinite(linearY) ? linearY : 0.0f});
    b2MotorJoint_SetAngularVelocity(joint->id, IsFinite(angularVelocity) ? angularVelocity : 0.0f);
}

KINE_BOX2D_API void Kine_Box2D_SetMotorJointVelocityLimits(void* handle, float maxForce, float maxTorque)
{
    auto* joint = JointFrom(handle, b2_motorJoint);
    if (!joint)
    {
        return;
    }

    b2MotorJoint_SetMaxVelocityForce(joint->id, NonNegative(maxForce));
    b2MotorJoint_SetMaxVelocityTorque(joint->id, NonNegative(maxTorque));
}

KINE_BOX2D_API void Kine_Box2D_SetMotorJointSpring(
    void* handle,
    float linearHertz,
    float linearDampingRatio,
    float maxSpringForce,
    float angularHertz,
    float angularDampingRatio,
    float maxSpringTorque)
{
    auto* joint = JointFrom(handle, b2_motorJoint);
    if (!joint)
    {
        return;
    }

    b2MotorJoint_SetLinearHertz(joint->id, NonNegative(linearHertz));
    b2MotorJoint_SetLinearDampingRatio(joint->id, NonNegative(linearDampingRatio));
    b2MotorJoint_SetMaxSpringForce(joint->id, NonNegative(maxSpringForce));
    b2MotorJoint_SetAngularHertz(joint->id, NonNegative(angularHertz));
    b2MotorJoint_SetAngularDampingRatio(joint->id, NonNegative(angularDampingRatio));
    b2MotorJoint_SetMaxSpringTorque(joint->id, NonNegative(maxSpringTorque));
}
