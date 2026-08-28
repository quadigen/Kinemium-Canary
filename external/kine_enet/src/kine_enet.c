#include "kine_enet.h"

#include <enet/enet.h>

#include <stdlib.h>
#include <string.h>
#include <stdint.h>

struct KineEnetEvent {
    ENetEvent event;
    int ownsPacket;
};

static int kine_enet_initialized = 0;

int Kine_ENet_Initialize(void)
{
    if (kine_enet_initialized) {
        return 1;
    }
    if (enet_initialize() != 0) {
        return 0;
    }
    kine_enet_initialized = 1;
    return 1;
}

void Kine_ENet_Deinitialize(void)
{
    if (!kine_enet_initialized) {
        return;
    }
    enet_deinitialize();
    kine_enet_initialized = 0;
}

void* Kine_ENet_Host_Create(
    const char* bindAddress,
    uint16_t port,
    size_t maxPeers,
    size_t channelCount,
    uint32_t incomingBandwidth,
    uint32_t outgoingBandwidth)
{
    ENetAddress address;
    ENetAddress* addressPtr = NULL;

    if (!Kine_ENet_Initialize() || maxPeers == 0 || channelCount == 0) {
        return NULL;
    }

    if (bindAddress && bindAddress[0] != '\0') {
        memset(&address, 0, sizeof(address));
        address.port = port;
        if (strcmp(bindAddress, "0.0.0.0") == 0 || strcmp(bindAddress, "*") == 0) {
            address.host = ENET_HOST_ANY;
        } else if (enet_address_set_host(&address, bindAddress) != 0) {
            return NULL;
        }
        addressPtr = &address;
    }

    return enet_host_create(
        addressPtr,
        maxPeers,
        channelCount,
        incomingBandwidth,
        outgoingBandwidth);
}

void Kine_ENet_Host_Destroy(void* host)
{
    if (host) {
        enet_host_destroy((ENetHost*)host);
    }
}

void Kine_ENet_Host_Flush(void* host)
{
    if (host) {
        enet_host_flush((ENetHost*)host);
    }
}

int Kine_ENet_Host_Service(void* host, KineEnetEvent* event, uint32_t timeoutMs)
{
    int result;
    if (!host || !event || event->ownsPacket) {
        return -1;
    }

    memset(&event->event, 0, sizeof(event->event));
    result = enet_host_service((ENetHost*)host, &event->event, timeoutMs);
    event->ownsPacket = result > 0 && event->event.type == ENET_EVENT_TYPE_RECEIVE;
    return result;
}

void* Kine_ENet_Host_Connect(
    void* host,
    const char* address,
    uint16_t port,
    size_t channelCount,
    uint32_t data)
{
    ENetAddress remote;
    if (!host || !address || address[0] == '\0' || channelCount == 0) {
        return NULL;
    }

    memset(&remote, 0, sizeof(remote));
    remote.port = port;
    if (enet_address_set_host(&remote, address) != 0) {
        return NULL;
    }
    return enet_host_connect((ENetHost*)host, &remote, channelCount, data);
}

int Kine_ENet_Peer_Send(
    void* peer,
    uint8_t channel,
    const void* data,
    size_t size,
    int reliable)
{
    ENetPacket* packet;
    enet_uint32 flags = reliable ? ENET_PACKET_FLAG_RELIABLE : 0;
    if (!peer || (!data && size > 0)) {
        return 0;
    }

    packet = enet_packet_create(data, size, flags);
    if (!packet) {
        return 0;
    }
    if (enet_peer_send((ENetPeer*)peer, channel, packet) != 0) {
        enet_packet_destroy(packet);
        return 0;
    }
    return 1;
}

void Kine_ENet_Peer_Disconnect(void* peer, uint32_t data)
{
    if (peer) {
        enet_peer_disconnect((ENetPeer*)peer, data);
    }
}

void Kine_ENet_Peer_Reset(void* peer)
{
    if (peer) {
        enet_peer_reset((ENetPeer*)peer);
    }
}

int Kine_ENet_Peer_GetAddress(
    void* peer,
    char* outAddress,
    size_t addressCapacity,
    uint16_t* outPort)
{
    ENetPeer* enetPeer = (ENetPeer*)peer;
    if (!enetPeer || !outAddress || addressCapacity == 0) {
        return 0;
    }
    if (enet_address_get_host_ip(&enetPeer->address, outAddress, addressCapacity) != 0) {
        outAddress[0] = '\0';
        return 0;
    }
    if (outPort) {
        *outPort = enetPeer->address.port;
    }
    return 1;
}

uint32_t Kine_ENet_Peer_GetPendingReliableBytes(void* peer)
{
    ENetPeer* enetPeer = (ENetPeer*)peer;
    ENetListIterator current;
    size_t total;
    if (!enetPeer) {
        return 0;
    }

    total = enetPeer->reliableDataInTransit;
    current = enet_list_begin(&enetPeer->outgoingSendReliableCommands);
    while (current != enet_list_end(&enetPeer->outgoingSendReliableCommands)) {
        ENetOutgoingCommand* command = (ENetOutgoingCommand*)current;
        total += command->fragmentLength;
        current = enet_list_next(current);
    }
    return total > UINT32_MAX ? UINT32_MAX : (uint32_t)total;
}

KineEnetEvent* Kine_ENet_Event_Create(void)
{
    return (KineEnetEvent*)calloc(1, sizeof(KineEnetEvent));
}

void Kine_ENet_Event_Release(KineEnetEvent* event)
{
    if (!event) {
        return;
    }
    if (event->ownsPacket && event->event.packet) {
        enet_packet_destroy(event->event.packet);
    }
    memset(&event->event, 0, sizeof(event->event));
    event->ownsPacket = 0;
}

void Kine_ENet_Event_Destroy(KineEnetEvent* event)
{
    if (!event) {
        return;
    }
    Kine_ENet_Event_Release(event);
    free(event);
}

int Kine_ENet_Event_GetType(const KineEnetEvent* event)
{
    return event ? (int)event->event.type : KINE_ENET_EVENT_NONE;
}

void* Kine_ENet_Event_GetPeer(const KineEnetEvent* event)
{
    return event ? event->event.peer : NULL;
}

uint8_t Kine_ENet_Event_GetChannel(const KineEnetEvent* event)
{
    return event ? event->event.channelID : 0;
}

uint32_t Kine_ENet_Event_GetData(const KineEnetEvent* event)
{
    return event ? event->event.data : 0;
}

const void* Kine_ENet_Event_GetPayload(const KineEnetEvent* event)
{
    if (!event || !event->ownsPacket || !event->event.packet) {
        return NULL;
    }
    return event->event.packet->data;
}

uint32_t Kine_ENet_Event_GetPayloadSize(const KineEnetEvent* event)
{
    if (!event || !event->ownsPacket || !event->event.packet) {
        return 0;
    }
    return event->event.packet->dataLength > UINT32_MAX
        ? UINT32_MAX
        : (uint32_t)event->event.packet->dataLength;
}
