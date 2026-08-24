--!strict
--!optimize 2
-- Made by FFIGen (Kinemium)

local ffi = zune.ffi

local structs = require("./sdl_image/structs")
local funcs = require("./sdl_image/funcs")
local constants = require("./sdl_image/constants")
local zembed = require("@zembed")

local libname = "KinemiumLibs." .. ffi.suffix

local function getLibraryPath(): string
	if zembed.IsEmbedded() then
		return zembed.RuntimePath(libname)
	end

	local paths = {
		"./vendor/" .. libname,
		"../vendor/" .. libname,
		"./" .. libname,
	}

	for _, path in paths do
		local ok, stat = pcall(zune.fs.stat, path)
		if ok and stat.kind == "file" then
			return path
		end
	end

	return paths[1]
end

local SDL3_image: funcs.Fns = ffi.dlopen(getLibraryPath(), funcs)

return {
	lib = SDL3_image,
	structs = structs,
	constants = constants,
}
