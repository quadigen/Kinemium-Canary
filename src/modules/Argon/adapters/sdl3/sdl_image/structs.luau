--!strict
--!optimize 2
--!native

local ffi = zune.ffi

-- Basic type aliases
local int = ffi.types.i32
local uint = ffi.types.u32
local bool = ffi.types.u8
local float = ffi.types.float
local double = ffi.types.double

local IMG_Animation = ffi.struct({
	{ w = ffi.types.i32 },
	{ h = ffi.types.i32 },
	{ count = ffi.types.i32 },
	{ frames = ffi.types.pointer },
	{ delays = ffi.types.pointer },
})
export type IMG_Animation = typeof(IMG_Animation:new({}))

local structs = {
	IMG_Animation = IMG_Animation,
}

return structs
