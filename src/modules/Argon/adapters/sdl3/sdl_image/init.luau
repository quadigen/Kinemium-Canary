--!strict
--!optimize 2
-- Made by FFIGen (Kinemium)

local dll = "./vendor/"
local ffi = zune.ffi

local structs = require("./sdl_image/structs")
local funcs = require("./sdl_image/funcs")
local constants = require("./sdl_image/constants")
local zembed = require("@zembed")

if zembed.IsEmbedded() then
	dll = "./"
end

local libname = "KinemiumLibs." .. ffi.suffix

local SDL3_image: funcs.Fns = ffi.dlopen(dll .. libname, funcs)

return {
	lib = SDL3_image,
	structs = structs,
	constants = constants,
}
