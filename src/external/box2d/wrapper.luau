local ffi = zune.ffi

local info = require("./bindings")

local fileFormat = ffi.suffix

local result = "./vendor/KinemiumLibs." .. fileFormat
local zembed = require("@zembed")
if zembed.IsEmbedded() then
	result = zembed.RuntimePath("KinemiumLibs." .. fileFormat)
end
local box2d: typeof(info.funcs) = ffi.dlopen(result, info.funcs)

return {
	lib = box2d,
	structs = info.structs,
}
