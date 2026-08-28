#ifndef KINE_ENET_H
#define KINE_ENET_H

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#  if defined(KINE_ENET_BUILD_EXPORTS)
#    define KINE_ENET_API __declspec(dllexport)
#  else
#    define KINE_ENET_API __declspec(dllimport)
#  endif
#else
#  define KINE_ENET_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct KineEnetEvent KineEnetEvent;

enum {
    KINE_ENET_EVENT_NONE = 0,
    KINE_ENET_EVENT_CONNECT = 1,
    KINE_ENET_EVENT_DISCONNECT = 2,
    KINE_ENET_EVENT_RECEIVE = 3
};

KINE_ENET_API int Kine_ENet_Initialize(void);
KINE_ENET_API void Kine_ENet_Deinitialize(void);

KINE_ENET_API void* Kine_ENet_Host_Create(
    const char* bindAddress,
    uint16_t port,
    size_t maxPeers,
    size_t channelCount,
    uint32_t incomingBandwidth,
    uint32_t outgoingBandwidth);
KINE_ENET_API void Kine_ENet_Host_Destroy(void* host);
KINE_ENET_API void Kine_ENet_Host_Flush(void* host);
KINE_ENET_API int Kine_ENet_Host_Service(void* host, KineEnetEvent* event, uint32_t timeoutMs);
KINE_ENET_API void* Kine_ENet_Host_Connect(
    void* host,
    const char* address,
    uint16_t port,
    size_t channelCount,
    uint32_t data);

KINE_ENET_API int Kine_ENet_Peer_Send(
    void* peer,
    uint8_t channel,
    const void* data,
    size_t size,
    int reliable);
KINE_ENET_API void Kine_ENet_Peer_Disconnect(void* peer, uint32_t data);
KINE_ENET_API void Kine_ENet_Peer_Reset(void* peer);
KINE_ENET_API int Kine_ENet_Peer_GetAddress(
    void* peer,
    char* outAddress,
    size_t addressCapacity,
    uint16_t* outPort);
KINE_ENET_API uint32_t Kine_ENet_Peer_GetPendingReliableBytes(void* peer);

KINE_ENET_API KineEnetEvent* Kine_ENet_Event_Create(void);
KINE_ENET_API void Kine_ENet_Event_Release(KineEnetEvent* event);
KINE_ENET_API void Kine_ENet_Event_Destroy(KineEnetEvent* event);
KINE_ENET_API int Kine_ENet_Event_GetType(const KineEnetEvent* event);
KINE_ENET_API void* Kine_ENet_Event_GetPeer(const KineEnetEvent* event);
KINE_ENET_API uint8_t Kine_ENet_Event_GetChannel(const KineEnetEvent* event);
KINE_ENET_API uint32_t Kine_ENet_Event_GetData(const KineEnetEvent* event);
KINE_ENET_API const void* Kine_ENet_Event_GetPayload(const KineEnetEvent* event);
KINE_ENET_API uint32_t Kine_ENet_Event_GetPayloadSize(const KineEnetEvent* event);

#ifdef __cplusplus
}
#endif

#endif
