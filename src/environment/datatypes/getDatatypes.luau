local fs = zune.fs
local datatypes = {}

local zembed = require("@zembed")
local kilang = require("@kilang")

local entries

if zembed.IsEmbedded() then
	entries = zembed.GetScriptsThatHas([[environment\datatypes]])
else
	entries = fs.entries("./src/environment/datatypes")
end

function datatypes:Init(datamodel, renderer, types)
	for _, file in pairs(entries) do
		local moduleName
		if zembed.IsEmbedded() then
			local stem = fs.path.stem(file)
			moduleName = fs.path.basename(file)
			moduleName = moduleName:gsub("%.luau$", "")
			if moduleName == "getDatatypes" then
				continue
			end

			moduleName = "datatypes/" .. moduleName
			local success, result = pcall(require, "../" .. moduleName)
			if not success then
				warn("Failed to add datatype " .. tostring(file) .. ": " .. tostring(result))
				continue
			end

			types[stem] = result
			datatypes[stem] = result
			if type(types[stem]) == "table" then
				types[stem].__type = stem
				types[stem].__datatype = true
			end
		else
			if file.name == "getDatatypes.luau" then
				continue
			end
			moduleName = file.name:gsub("%.luau$", "")

			local path = "./src/environment/datatypes/" .. moduleName .. ".luau"
			local read = zune.fs.readFile(path)
			local thread, success, result, _, getResult = kilang:execute(
				read,
				{ StackId = path },
				{ game = datamodel, renderer = renderer }
			)
			if getResult then
				success, result = getResult()
			end

			if not success then
				warn("Failed to add datatype " .. path .. ": " .. result)
				continue
			end
			kilang:remove(thread)
			types[moduleName] = result
			datatypes[moduleName] = result

			if type(types[moduleName]) == "table" then
				types[moduleName].__type = moduleName
				types[moduleName].__datatype = true
			end
		end
	end
end

return datatypes
