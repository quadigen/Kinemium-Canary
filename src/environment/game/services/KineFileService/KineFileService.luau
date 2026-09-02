local Instance = require("@Instance")
local Enum = require("@EnumMap")

local KineFileService = Instance.new("KineFileService")
KineFileService.ExplorerHidden = true
KineFileService._Intents = Enum.PluginIntents.Filesystem

local kine = require("@kineformat")

local zembed = require("@zembed")
local fs = zune.fs
local process = zune.process
local os = zune.platform.os
local zune_path = _G.ZUNE_EMBEDDED

local assetsaver = require("@assetsaver")

export type KinemiumPlaceFile = {
	ToExe: (string) -> (),
}

local buildNames = {
	["windows"] = "windows_x86-64",
	["macos"] = "macos_x86-64",
	["linux"] = "debian_x86-64",
	["freebsd"] = "freebsd_x86-64",
}

local serde = zune.serde

local runtimeNames = {
	windows = { source = "KinemiumRuntime.exe", extension = ".exe" },
	macos = { source = "KinemiumRuntime.app", extension = ".app" },
	linux = { source = "KinemiumRuntime", extension = "" },
	freebsd = { source = "KinemiumRuntime", extension = "" },
}

local EMBEDDED_GAME_PATH = "./.temp/embedded-game.kine"
local EMBEDDED_GAME_MODULE_PATH = "./.temp/embedded-game-data.luau"

local function buildEngine(embeddedGamePath: string?)
	local args = { "run", "build" }
	if embeddedGamePath then
		table.insert(args, "--embed-game")
		table.insert(args, embeddedGamePath)
	end

	local res = process.run(zune_path or fs.getExePath(), args)
	return res
end

local function restoreAssetProperties(oldProperties)
	for object, properties in pairs(oldProperties or {}) do
		for property, value in pairs(properties) do
			object[property] = value
		end
	end
end

local function safeExportName(name)
	local result = tostring(name or "KinemiumGame"):gsub("[^%w_%- ]", "_"):gsub("%s+", "_")
	return result ~= "" and result or "KinemiumGame"
end

local function copyRuntimePackage(buildFolder, outputDirectory, executableName)
	local runtime = runtimeNames[zune.platform.os]
	if not runtime then
		error(`Executable export is not supported on {tostring(zune.platform.os)}`)
	end
	fs.makeDir(outputDirectory, true)

	local sourceExecutable = buildFolder .. "/" .. runtime.source
	local destinationExecutable = outputDirectory .. "/" .. executableName .. runtime.extension
	fs.copy(sourceExecutable, destinationExecutable, true)

	for _, entry in ipairs(fs.entries(buildFolder)) do
		if entry.kind == "file" and entry.name ~= runtime.source then
			local extension = fs.path.extension(entry.name)
			if extension == ".dll" or extension == ".so" or extension == ".dylib" or entry.name == "zune.exe" then
				fs.copy(buildFolder .. "/" .. entry.name, outputDirectory .. "/" .. entry.name, true)
			end
		end
	end

	local assetsPath = buildFolder .. "/assets"
	local assetsOk, assetsStat = pcall(fs.stat, assetsPath)
	if assetsOk and assetsStat and assetsStat.kind == "directory" then
		fs.copy(assetsPath, outputDirectory .. "/assets", true)
	end
	return destinationExecutable
end

local function loop(path)
	local dlls = {}

	for _, folder in pairs(fs.entries(path)) do
		if folder.kind == "directory" then
			local result = loop(path .. "/" .. folder.name)
			if result then
				for i, v in pairs(result) do
					table.insert(dlls, v)
				end
			end
		else
			local extension = fs.path.extension(folder.name)
			local main = ".dll"
			if os == "linux" then
				main = ".so"
			elseif os == "macos" then
				main = ".dylib"
			end
			if extension == main then
				table.insert(dlls, path .. "/" .. folder.name)
			end
		end
	end

	return dlls
end

KineFileService.InitRenderer = function(renderer, renderer_signal, datamodel)
	local function exportForRole(role, gameName, outputDirectory, options)
		if type(outputDirectory) == "table" then
			options = outputDirectory
			outputDirectory = options.OutputDirectory or options.outputDirectory
		end
		options = options or {}

		local assets, old_props = assetsaver:GetGameAssets(datamodel)
		local success, result = pcall(function()
			fs.makeDir("./.temp", true)
			pcall(fs.deleteFile, EMBEDDED_GAME_PATH)
			pcall(fs.deleteFile, EMBEDDED_GAME_MODULE_PATH)
			local serialized = KineFileService.ExportGameAsFile("./.temp", "embedded-game")
			if not serialized then
				error(`Failed to serialize {tostring(gameName)} for {role} export`)
			end

			local res = buildEngine(EMBEDDED_GAME_PATH)
			if not res.ok then
				error(`Got error code {res.code} while building Engine: {tostring(res.stderr)}`)
			end

			local platform = buildNames[zune.platform.os]
			local buildFolder = `./build/{platform}`
			local safeName = safeExportName(gameName)
			local destination = outputDirectory or `{buildFolder}/exports/{safeName}-{role}`
			local gameAssets = buildFolder .. "/assets/game"

			if assets then
				fs.makeDir(gameAssets, true)
				for assetPath, buff in pairs(assets) do
					fs.writeFile(gameAssets .. "/" .. fs.path.basename(assetPath), buff)
				end
			end

			local executableName = safeName .. (role == "server" and "Server" or "Client")
			local executablePath = copyRuntimePackage(buildFolder, destination, executableName)
			local flags = { role }
			if role == "server" and options.Headless ~= false then
				table.insert(flags, "headless")
			end
			for _, flag in ipairs(options.Flags or {}) do
				table.insert(flags, flag)
			end
			fs.makeDir(destination .. "/exported", true)
			fs.writeFile(destination .. "/exported/flags.toml", serde.toml.encode({ default = flags }))
			return {
				Role = role,
				Directory = destination,
				Executable = executablePath,
			}
		end)

		restoreAssetProperties(old_props)
		pcall(fs.deleteFile, EMBEDDED_GAME_PATH)
		pcall(fs.deleteFile, EMBEDDED_GAME_MODULE_PATH)
		if not success then
			error(result, 2)
		end
		return result
	end

	KineFileService:SetProperties({
		BuildRuntime = function()
			if zembed.IsEmbedded() then
				return
			end

			local SerializationService = datamodel:GetService("SerializationService")
			local serialized = SerializationService.SerializeInstancesAsync({ datamodel })

			if serialized then
				local wrapper = {}

				fs.makeDir("./build")

				local dlls = loop("./")
				for _, dll in dlls do
					pcall(function()
						fs.copy(dll, "./build/" .. fs.path.basename(dll))
						print(`Cloned {dll}`)
					end)
				end

				buildEngine()

				return wrapper
			end

			return
		end,

		Save = function(pathName)
			local SerializationService = datamodel:GetService("SerializationService")
			local serialized = SerializationService.SerializeInstancesAsync({ datamodel })
			if serialized then
				local wrapper = {}

				fs.makeDir("./build")

				local dlls = loop("./")
				for _, dll in dlls do
					pcall(function()
						fs.copy(dll, "./build/" .. fs.path.basename(dll))
						print(`Cloned {dll}`)
					end)
				end

				fs.createFile("./build/" .. pathName)
				fs.writeFile("./build/" .. pathName, serialized)

				function wrapper:ToExe()
					buildEngine()
				end

				return wrapper
			end
			return
		end,

		ExportObject = function(instances, path, name)
			local serialized = kine.serialize(instances, datamodel)
			if serialized then
				fs.writeFile(path .. "/" .. name .. ".kine", serialized)
			end
			return serialized, true
		end,

		ExportDatamodel = function(path, name)
			local saved = {}

			for _, service in ipairs(datamodel:GetChildren()) do
				if service.Name == "Players" then
					continue
				end

				local children = service:GetChildren()
				if service.Name == "Workspace" or children[1] ~= nil then
					table.insert(saved, service)
				else
					print("Skipped " .. service.Name)
				end
			end

			return saved
		end,

		ExportGameAsFile = function(path, gameName: string)
			local savedObjects = KineFileService.ExportDatamodel(path, gameName)
			local serialized = KineFileService.ExportObject(savedObjects, path, gameName)
			return serialized
		end,

		DecodeFile = function(filePath)
			local read = fs.readFile(filePath, true)
			if read then
				local deserialized = kine.deserialize(read, datamodel)
				if deserialized then
					if #deserialized == 1 then
						return deserialized[1]
					end
					return deserialized
				end
			end
			return false
		end,

		ExportAsClient = function(gameName, outputDirectory, options, colonOptions)
			if gameName == KineFileService then
				gameName, outputDirectory, options = outputDirectory, options, colonOptions
			end
			return exportForRole("client", gameName, outputDirectory, options)
		end,

		ExportAsServer = function(gameName, outputDirectory, options, colonOptions)
			if gameName == KineFileService then
				gameName, outputDirectory, options = outputDirectory, options, colonOptions
			end
			return exportForRole("server", gameName, outputDirectory, options)
		end,

		ExportGameAsExecutable = function(gameName, outputDirectory, options, colonOptions)
			if gameName == KineFileService then
				gameName, outputDirectory, options = outputDirectory, options, colonOptions
			end
			return exportForRole("client", gameName, outputDirectory, options)
		end,
	})
end

return KineFileService
