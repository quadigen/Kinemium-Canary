--!strict
--!optimize 2
--!native

local ffi = zune.ffi

local funcs = require("./filament/funcs")
local structs = require("./filament/structs")
local const = require("./filament/constants")

local libLocation = "./vendor/KinemiumLibs." .. ffi.suffix
local zembed = require("@zembed")
if zembed.IsEmbedded() then
	libLocation = zembed.RuntimePath("KinemiumLibs." .. ffi.suffix)
end

local lib = ffi.dlopen(libLocation, funcs)

return {
	structs = structs,
	const = const,
	lib = lib :: funcs.Fns,
}
