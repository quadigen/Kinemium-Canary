local Instance = require("@Instance")
local Enum = require("@EnumMap")

local KineFileService = Instance.new("KineFileService")
KineFileService.ExplorerHidden = true
KineFileService._Intents = Enum.PluginIntents.Filesystem

local kine = require("./src/environment/game/services/KineFileService/filetypes/kine")

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

local defaultFlags = {
	["default"] = {
		"client",
		"offline",
		"no_multiplayer",
	},
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

		ExportGameAsExecutable = function(gameName)
			local assets, old_props = assetsaver:GetGameAssets(datamodel)
			local success, result = pcall(function()
				fs.makeDir("./.temp", true)
				pcall(fs.deleteFile, EMBEDDED_GAME_PATH)
				pcall(fs.deleteFile, EMBEDDED_GAME_MODULE_PATH)
				local serialized = KineFileService.ExportGameAsFile("./.temp", "embedded-game")
				if not serialized then
					error(`Failed to serialize {tostring(gameName)} for executable export`)
				end

				local res = buildEngine(EMBEDDED_GAME_PATH)
				pcall(fs.deleteFile, EMBEDDED_GAME_PATH)
				if not res.ok then
					error(`Got error code {res.code} while building Engine: {tostring(res.stderr)}`)
				end

				local platform = buildNames[zune.platform.os]
				local buildFolder = `./build/{platform}`
				local exportedFolder = buildFolder .. "/exported"
				local game_folder_assets = buildFolder .. "/assets/game"

				fs.makeDir(exportedFolder, true)

				-- Runtime flags and game assets remain beside the executable. The datamodel
				-- itself is bundled into the executable by build.luau.
				fs.writeFile(exportedFolder .. "/flags.toml", serde.toml.encode(defaultFlags))

				if assets then
					fs.makeDir(game_folder_assets, true)

					for path, buff in pairs(assets) do
						local basename = zune.fs.path.basename(path)
						fs.writeFile(game_folder_assets .. "/" .. basename, buff)
					end
				end
			end)

			restoreAssetProperties(old_props)
			pcall(fs.deleteFile, EMBEDDED_GAME_PATH)
			pcall(fs.deleteFile, EMBEDDED_GAME_MODULE_PATH)

			if not success then
				error(result)
			end

			return true
		end,
	})
end

return KineFileService
