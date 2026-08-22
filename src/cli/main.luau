_G.ArgumentExists = function(flag)
	local args = zune.process.args
	for _, v in pairs(args) do
		if v == flag then
			return true
		end
	end
	return false
end

_G.GetArg = function(flag, index)
	local args = zune.process.args

	for i, v in ipairs(args) do
		if v == flag or v == "--" .. flag then
			return args[i + index]
		end
	end

	return nil
end

local packager = require("./Packager")
local cli = {}
local fs = zune.fs
local toml = zune.serde.toml

local function buildProjectConfig(name, iconPath, description, dimension)
	local plugins_built = {}

	return {
		info = {
			name = name,
			icon = iconPath,
			desc = description,
			dimension = dimension,
		},
		pointers = {
			assets = "game.ReplicatedStorage",
			server = "game.ServerScriptService",
			client = "game.StarterPlayer",
			gui = "game.StarterGui",
			objects = "game.Workspace",
		},
		plugins = plugins_built,

		sync = {
			live = false,
			debounce = 0.35,
			ignore = { git = ".git", vscode = ".vscode" },
		},
		backups = {
			interval = 300,
		},
		scripting = {
			polyglot = true,
			ncg = true,
		},
	}
end

function cli:create_project(path, name)
	local dir = path or zune.process.cwd()

	if not name then
		return
	end
	if not dir then
		return
	end

	zune.fs.makeDir(dir .. "/" .. name)
	dir = dir .. "/" .. name

	local kprojFile = dir .. "/project.kproj"

	local encoded = toml.encode(buildProjectConfig(name, "", "a Kinemium project.", "3D"))

	fs.writeFile(kprojFile, encoded)

	local success, result = pcall(function()
		fs.makeDir(dir .. "/assets", true)
		fs.makeDir(dir .. "/server", true)
		fs.makeDir(dir .. "/client", true)
		fs.makeDir(dir .. "/gui", true)
		fs.makeDir(dir .. "/objects", true)
		fs.makeDir(dir .. "/.vscode", true)
		fs.makeDir(dir .. "/scenes", true)

		fs.writeFile(
			dir .. "/.vscode/settings.json",
			zune.serde.json.encode(settings, {
				pretty_indent = 1,
			})
		)
	end)

	if not success then
		print(result)
	end

	return encoded
end

if ArgumentExists("create") then
	local name = GetArg("create", 1)
	if type(name) == "string" then
		cli:create_project(zune.process.cwd(), name)
	end
elseif ArgumentExists("install") then
	local branch = GetArg("install", 1)
	local repo = "https://github.com/quadigen/Kinemium-Engine"
	if branch == "canary" then
		repo = "github.com/quadigen/Kinemium-Canary"
	end

	packager.download(repo, parentFolder)
else
	print("Kinemium Engine CLI\n  create GAMENAME")
end

return cli
