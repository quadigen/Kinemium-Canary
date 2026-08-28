local ffi = zune.ffi

type int = number
type uint = number
type size_t = number
type FFIPointer = typeof(ffi.types.pointer)

export type Fns = {
	Kine_ENet_Initialize: () -> int,
	Kine_ENet_Deinitialize: () -> (),
	Kine_ENet_Host_Create: (FFIPointer?, uint, size_t, size_t, uint, uint) -> FFIPointer,
	Kine_ENet_Host_Destroy: (FFIPointer) -> (),
	Kine_ENet_Host_Flush: (FFIPointer) -> (),
	Kine_ENet_Host_Service: (FFIPointer, FFIPointer, uint) -> int,
	Kine_ENet_Host_Connect: (FFIPointer, FFIPointer, uint, size_t, uint) -> FFIPointer,
	Kine_ENet_Peer_Send: (FFIPointer, uint, FFIPointer, size_t, int) -> int,
	Kine_ENet_Peer_Disconnect: (FFIPointer, uint) -> (),
	Kine_ENet_Peer_Reset: (FFIPointer) -> (),
	Kine_ENet_Peer_GetAddress: (FFIPointer, FFIPointer, size_t, FFIPointer) -> int,
	Kine_ENet_Peer_GetPendingReliableBytes: (FFIPointer) -> uint,
	Kine_ENet_Event_Create: () -> FFIPointer,
	Kine_ENet_Event_Release: (FFIPointer) -> (),
	Kine_ENet_Event_Destroy: (FFIPointer) -> (),
	Kine_ENet_Event_GetType: (FFIPointer) -> int,
	Kine_ENet_Event_GetPeer: (FFIPointer) -> FFIPointer,
	Kine_ENet_Event_GetChannel: (FFIPointer) -> uint,
	Kine_ENet_Event_GetData: (FFIPointer) -> uint,
	Kine_ENet_Event_GetPayload: (FFIPointer) -> FFIPointer,
	Kine_ENet_Event_GetPayloadSize: (FFIPointer) -> uint,
}

local ptr = ffi.types.pointer
local u64 = ffi.types.u64
local u32 = ffi.types.u32
local u16 = ffi.types.u16
local u8 = ffi.types.u8
local i32 = ffi.types.i32

return {
	Kine_ENet_Initialize = { returns = i32, args = {} },
	Kine_ENet_Deinitialize = { returns = ffi.types.void, args = {} },
	Kine_ENet_Host_Create = { returns = ptr, args = { ptr, u16, u64, u64, u32, u32 } },
	Kine_ENet_Host_Destroy = { returns = ffi.types.void, args = { ptr } },
	Kine_ENet_Host_Flush = { returns = ffi.types.void, args = { ptr } },
	Kine_ENet_Host_Service = { returns = i32, args = { ptr, ptr, u32 } },
	Kine_ENet_Host_Connect = { returns = ptr, args = { ptr, ptr, u16, u64, u32 } },
	Kine_ENet_Peer_Send = { returns = i32, args = { ptr, u8, ptr, u64, i32 } },
	Kine_ENet_Peer_Disconnect = { returns = ffi.types.void, args = { ptr, u32 } },
	Kine_ENet_Peer_Reset = { returns = ffi.types.void, args = { ptr } },
	Kine_ENet_Peer_GetAddress = { returns = i32, args = { ptr, ptr, u64, ptr } },
	Kine_ENet_Peer_GetPendingReliableBytes = { returns = u32, args = { ptr } },
	Kine_ENet_Event_Create = { returns = ptr, args = {} },
	Kine_ENet_Event_Release = { returns = ffi.types.void, args = { ptr } },
	Kine_ENet_Event_Destroy = { returns = ffi.types.void, args = { ptr } },
	Kine_ENet_Event_GetType = { returns = i32, args = { ptr } },
	Kine_ENet_Event_GetPeer = { returns = ptr, args = { ptr } },
	Kine_ENet_Event_GetChannel = { returns = u8, args = { ptr } },
	Kine_ENet_Event_GetData = { returns = u32, args = { ptr } },
	Kine_ENet_Event_GetPayload = { returns = ptr, args = { ptr } },
	Kine_ENet_Event_GetPayloadSize = { returns = u32, args = { ptr } },
} :: Fns
