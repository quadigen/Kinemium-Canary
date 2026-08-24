local ffi = zune.ffi

local info = require("./bindings")

local libname = "KinemiumLibs." .. ffi.suffix

local zembed = require("@zembed")

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

local box2d: typeof(info.funcs) = ffi.dlopen(getLibraryPath(), info.funcs)

return {
	lib = box2d,
	structs = info.structs,
}
