local dllLib = {}
local ffi = zune.ffi
local fs = zune.fs

function dllLib.open(path, name, functions)
	local newName = name .. "." .. ffi.suffix
	local file = path .. "/" .. newName
	local stat = fs.stat(file)

	local success, result = pcall(function(...)
		return ffi.dlopen(file, functions)
	end)

	if not success then
		if string.find(result, "FileNotFound") then
			if stat.kind == "none" then
				error("Dll not found")
			else
				error("Something wrong happened with the dll, maybe check the dependencies?")
			end
		end
	else
		return result
	end
end

return dllLib
