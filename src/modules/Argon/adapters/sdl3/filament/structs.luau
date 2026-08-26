--!strict
-- Filament FFI Structs

local ffi = zune.ffi

local KineFilamentDrawItem = ffi.struct({
	{ mesh = ffi.types.pointer },
	{ tex = ffi.types.pointer },
	{ transform = ffi.types.float:array(16) },
	{ r = ffi.types.float },
	{ g = ffi.types.float },
	{ b = ffi.types.float },
	{ param1 = ffi.types.float },
	{ param2 = ffi.types.float },
	{ param3 = ffi.types.float },
	{ transmission = ffi.types.float },
	{ materialKind = ffi.types.i32 },
	{ flags = ffi.types.u32 },
	{ reserved = ffi.types.u32 },
})

return {
	KineFilamentDrawItem = KineFilamentDrawItem,
}
