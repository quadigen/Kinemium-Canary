--!strict
--!optimize 2
-- Made by FFIGen (Kinemium)

local dll = "./vendor/"
local ffi = zune.ffi
local platform = zune.platform

local structs = require("./sdl_image/structs")
local funcs = require("./sdl_image/funcs")
local constants = require("./sdl_image/constants")

local libname
if platform.os == "windows" then
	libname = "SDL3_image.dll"
elseif platform.os == "linux" then
	libname = "SDL3_image.so"
elseif platform.os == "macos" then
	libname = "SDL3_image.dylib"
end

local SDL3_image: funcs.Fns = ffi.dlopen(dll .. libname, funcs)

return {
	lib = SDL3_image,
	structs = structs,
	constants = constants,
}
