--!strict
--!optimize 2
-- Made by FFIGen (Kinemium)

local ffi = zune.ffi
local zembed = require("@zembed")

local structs = require("./manifold/structs")
local funcs = require("./manifold/funcs")
local constants = require("./manifold/constants")

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

local manifold: funcs.Fns = ffi.dlopen(getLibraryPath(), funcs)

return {
	lib = manifold,
	structs = structs,
	constants = constants,
}
