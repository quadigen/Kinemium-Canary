#include <box2d/box2d.h>
#include <cmath>
#include <new>
#if defined(_WIN32)
#define KINE_BOX2D_API extern "C" __declspec(dllexport)
#else
#define KINE_BOX2D_API extern "C" __attribute__((visibility("default")))
#endif
struct KineBox2DWorld { b2WorldId id; };
struct KineBox2DBody { b2BodyId id; b2ShapeId shape; };
struct KineBox2DJoint { b2JointId id; };
KINE_BOX2D_API void* Kine_Box2D_CreateWorld(float gx, float gy) { b2WorldDef d=b2DefaultWorldDef(); d.gravity={gx,gy}; auto* w=new(std::nothrow) KineBox2DWorld{b2CreateWorld(&d)}; return w&&b2World_IsValid(w->id)?w:nullptr; }
KINE_BOX2D_API void Kine_Box2D_DestroyWorld(void* h) { auto*w=static_cast<KineBox2DWorld*>(h); if(!w)return; if(b2World_IsValid(w->id))b2DestroyWorld(w->id); delete w; }
KINE_BOX2D_API void Kine_Box2D_SetGravity(void*h,float x,float y){auto*w=static_cast<KineBox2DWorld*>(h);if(w&&b2World_IsValid(w->id))b2World_SetGravity(w->id,{x,y});}
KINE_BOX2D_API void Kine_Box2D_Step(void*h,float dt,int n){auto*w=static_cast<KineBox2DWorld*>(h);if(w&&b2World_IsValid(w->id))b2World_Step(w->id,dt,n>0?n:4);}
KINE_BOX2D_API void Kine_Box2D_StepWithGravity(void*h,float dt,int n,float gx,float gy){auto*w=static_cast<KineBox2DWorld*>(h);if(!w||!b2World_IsValid(w->id))return;b2World_SetGravity(w->id,{gx,gy});b2World_Step(w->id,dt,n>0?n:4);}
KINE_BOX2D_API void* Kine_Box2D_CreateBoxBody(void*wh,float x,float y,float width,float height,float angle,int dynamicBody,float density,float friction,float restitution,int sensor){auto*w=static_cast<KineBox2DWorld*>(wh);if(!w||!b2World_IsValid(w->id))return nullptr;b2BodyDef bd=b2DefaultBodyDef();bd.type=dynamicBody?b2_dynamicBody:b2_staticBody;bd.position={x,y};bd.rotation=b2MakeRot(angle);b2BodyId id=b2CreateBody(w->id,&bd);if(!b2Body_IsValid(id))return nullptr;b2ShapeDef sd=b2DefaultShapeDef();sd.density=density;sd.material.friction=friction;sd.material.restitution=restitution;sd.isSensor=sensor!=0;b2Polygon p=b2MakeBox(width*.5f,height*.5f);return new(std::nothrow) KineBox2DBody{id,b2CreatePolygonShape(id,&sd,&p)};}
KINE_BOX2D_API void Kine_Box2D_DestroyBody(void*h){auto*b=static_cast<KineBox2DBody*>(h);if(!b)return;if(b2Body_IsValid(b->id))b2DestroyBody(b->id);delete b;}
KINE_BOX2D_API void Kine_Box2D_SetBodyTransform(void*h,float x,float y,float a){auto*b=static_cast<KineBox2DBody*>(h);if(b&&b2Body_IsValid(b->id))b2Body_SetTransform(b->id,{x,y},b2MakeRot(a));}
KINE_BOX2D_API void Kine_Box2D_GetBodyTransform(void*h,float*x,float*y,float*a){auto*b=static_cast<KineBox2DBody*>(h);if(!b||!b2Body_IsValid(b->id))return;auto p=b2Body_GetPosition(b->id);auto r=b2Body_GetRotation(b->id);if(x)*x=p.x;if(y)*y=p.y;if(a)*a=std::atan2(r.s,r.c);}
KINE_BOX2D_API void Kine_Box2D_SetBodyType(void*h,int d){auto*b=static_cast<KineBox2DBody*>(h);if(b&&b2Body_IsValid(b->id))b2Body_SetType(b->id,d?b2_dynamicBody:b2_staticBody);}
KINE_BOX2D_API void Kine_Box2D_SetBodyVelocity(void*h,float x,float y,float a){auto*b=static_cast<KineBox2DBody*>(h);if(!b||!b2Body_IsValid(b->id))return;b2Body_SetLinearVelocity(b->id,{x,y});b2Body_SetAngularVelocity(b->id,a);}

KINE_BOX2D_API void* Kine_Box2D_CreateDistanceJoint(
    void* wh, void* ah, void* bh,
    float ax, float ay, float bx, float by,
    float length, int springEnabled, float hertz, float dampingRatio,
    int limitEnabled, float minLength, float maxLength, int collideConnected)
{
    auto* w=static_cast<KineBox2DWorld*>(wh);auto* a=static_cast<KineBox2DBody*>(ah);auto* b=static_cast<KineBox2DBody*>(bh);
    if(!w||!a||!b||!b2World_IsValid(w->id)||!b2Body_IsValid(a->id)||!b2Body_IsValid(b->id))return nullptr;
    b2DistanceJointDef d=b2DefaultDistanceJointDef();d.base.bodyIdA=a->id;d.base.bodyIdB=b->id;
    d.base.localFrameA.p={ax,ay};d.base.localFrameB.p={bx,by};d.base.collideConnected=collideConnected!=0;
    d.length=std::fmax(length,0.01f);d.enableSpring=springEnabled!=0;d.hertz=std::fmax(hertz,0.0f);d.dampingRatio=std::fmax(dampingRatio,0.0f);
    d.enableLimit=limitEnabled!=0;d.minLength=std::fmax(minLength,0.01f);d.maxLength=std::fmax(maxLength,d.minLength);
    b2JointId id=b2CreateDistanceJoint(w->id,&d);return b2Joint_IsValid(id)?new(std::nothrow) KineBox2DJoint{id}:nullptr;
}

KINE_BOX2D_API void* Kine_Box2D_CreateHingeJoint(
    void* wh, void* ah, void* bh,
    float ax, float ay, float ar, float bx, float by, float br,
    int limitsEnabled, float lowerAngle, float upperAngle,
    int motorEnabled, float motorSpeed, float maxMotorTorque, int collideConnected)
{
    auto* w=static_cast<KineBox2DWorld*>(wh);auto* a=static_cast<KineBox2DBody*>(ah);auto* b=static_cast<KineBox2DBody*>(bh);
    if(!w||!a||!b||!b2World_IsValid(w->id)||!b2Body_IsValid(a->id)||!b2Body_IsValid(b->id))return nullptr;
    b2RevoluteJointDef d=b2DefaultRevoluteJointDef();d.base.bodyIdA=a->id;d.base.bodyIdB=b->id;
    d.base.localFrameA={.p={ax,ay},.q=b2MakeRot(ar)};d.base.localFrameB={.p={bx,by},.q=b2MakeRot(br)};d.base.collideConnected=collideConnected!=0;
    d.enableLimit=limitsEnabled!=0;d.lowerAngle=std::fmax(lowerAngle,-0.99f*B2_PI);d.upperAngle=std::fmin(upperAngle,0.99f*B2_PI);
    if(d.lowerAngle>d.upperAngle){float t=d.lowerAngle;d.lowerAngle=d.upperAngle;d.upperAngle=t;}
    d.enableMotor=motorEnabled!=0;d.motorSpeed=motorSpeed;d.maxMotorTorque=std::fmax(maxMotorTorque,0.0f);
    b2JointId id=b2CreateRevoluteJoint(w->id,&d);return b2Joint_IsValid(id)?new(std::nothrow) KineBox2DJoint{id}:nullptr;
}

KINE_BOX2D_API void* Kine_Box2D_CreateWeldJoint(
    void* wh, void* ah, void* bh,
    float ax, float ay, float ar, float bx, float by, float br,
    float linearHertz, float angularHertz, float linearDamping, float angularDamping,
    int preserveInitialTransform, int collideConnected)
{
    auto* w=static_cast<KineBox2DWorld*>(wh);auto* a=static_cast<KineBox2DBody*>(ah);auto* b=static_cast<KineBox2DBody*>(bh);
    if(!w||!a||!b||!b2World_IsValid(w->id)||!b2Body_IsValid(a->id)||!b2Body_IsValid(b->id))return nullptr;
    b2WeldJointDef d=b2DefaultWeldJointDef();d.base.bodyIdA=a->id;d.base.bodyIdB=b->id;d.base.collideConnected=collideConnected!=0;
    if(preserveInitialTransform){
        b2Pos anchor=b2Body_GetPosition(a->id);d.base.localFrameA={.p={0,0},.q=b2Rot_identity};
        d.base.localFrameB.p=b2Body_GetLocalPoint(b->id,anchor);d.base.localFrameB.q=b2InvMulRot(b2Body_GetRotation(b->id),b2Body_GetRotation(a->id));
    }else{d.base.localFrameA={.p={ax,ay},.q=b2MakeRot(ar)};d.base.localFrameB={.p={bx,by},.q=b2MakeRot(br)};}
    d.linearHertz=std::fmax(linearHertz,0.0f);d.angularHertz=std::fmax(angularHertz,0.0f);
    d.linearDampingRatio=std::fmax(linearDamping,0.0f);d.angularDampingRatio=std::fmax(angularDamping,0.0f);
    b2JointId id=b2CreateWeldJoint(w->id,&d);return b2Joint_IsValid(id)?new(std::nothrow) KineBox2DJoint{id}:nullptr;
}

KINE_BOX2D_API void Kine_Box2D_DestroyJoint(void* h){auto*j=static_cast<KineBox2DJoint*>(h);if(!j)return;if(b2Joint_IsValid(j->id))b2DestroyJoint(j->id,true);delete j;}
