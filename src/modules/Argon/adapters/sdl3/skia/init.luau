--!strict
--!optimize 2
-- Made by FFIGen (Kinemium)

local dll = "./vendor/"
local ffi = zune.ffi

local funcs = require("./skia/funcs")
local zembed = require("@zembed")
if zembed.IsEmbedded() then
	dll = "./"
end

local libname = "KinemiumLibs." .. ffi.suffix

local skia: typeof(funcs) = ffi.dlopen(dll .. libname, funcs)

return {
	lib = skia,
}
