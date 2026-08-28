--!strict
--!optimize 2

local ffi = zune.ffi
local zembed = require("@zembed")
local funcs = require("./enet/funcs")

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
	for _, path in ipairs(paths) do
		local ok, stat = pcall(zune.fs.stat, path)
		if ok and stat.kind == "file" then
			return path
		end
	end
	return paths[1]
end

local lib: funcs.Fns = ffi.dlopen(getLibraryPath(), funcs)

return {
	lib = lib,
	Event = {
		None = 0,
		Connect = 1,
		Disconnect = 2,
		Receive = 3,
	},
}

