--!strict
--!optimize 2
-- Made by FFIGen (Kinemium)

local dll = "./vendor/"
local ffi = zune.ffi

local structs = require("./sdl/structs")
local funcs = require("./sdl/funcs")
local zembed = require("@zembed")
if zembed.IsEmbedded() then
	dll = "./"
end

local libname = "KinemiumLibs." .. ffi.suffix

local sdl3: typeof(funcs) = ffi.dlopen(dll .. libname, funcs)

return {
	lib = sdl3,
	structs = structs,
}
