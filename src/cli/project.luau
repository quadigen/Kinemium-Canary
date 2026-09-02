local fs = zune.fs
local path = fs.path
local toml = zune.serde.toml
local json = zune.serde.json

local Project = {}

Project.RequiredDirectories = { "assets", "server", "client", "gui", "objects", "scenes" }

local function kind(filePath)
	local ok, stat = pcall(fs.stat, filePath)
	return if ok and stat then stat.kind else "none"
end

local function absolute(filePath)
	local ok, resolved = pcall(fs.realPath, filePath)
	return if ok and resolved and resolved ~= "" then resolved else filePath
end

local function readToml(filePath)
	local okRead, body = pcall(fs.readFile, filePath)
	if not okRead then
		return nil, tostring(body)
	end
	local okDecode, decoded = pcall(toml.decode, body)
	if not okDecode or type(decoded) ~= "table" then
		return nil, tostring(decoded)
	end
	return decoded
end

function Project.defaultConfig(name)
	return {
		info = {
			name = name,
			icon = "",
			desc = "A Kinemium project.",
			dimension = "3D",
		},
		pointers = {
			assets = "game.ReplicatedStorage",
			server = "game.ServerScriptService",
			client = "game.StarterPlayer.StarterPlayerScripts",
			gui = "game.StarterGui",
			objects = "game.Workspace",
		},
		plugins = {},
		sync = {
			live = false,
			debounce = 0.35,
			ignore = { ".git", ".vscode", "autosave", "backups" },
		},
		backups = { interval = 300 },
		scripting = { polyglot = true, ncg = true },
	}
end

function Project.manifestPath(projectPath)
	local standard = path.join(projectPath, "kproj.toml")
	if kind(standard) == "file" then
		return standard
	end
	local legacy = path.join(projectPath, "project.kproj")
	if kind(legacy) == "file" then
		return legacy
	end
	return standard
end

function Project.readManifest(projectPath)
	local manifestPath = Project.manifestPath(projectPath)
	if kind(manifestPath) ~= "file" then
		return nil, `Missing project manifest: {manifestPath}`
	end
	return readToml(manifestPath)
end

function Project.readRegistry(registryPath)
	if kind(registryPath) ~= "file" then
		return { projects = {} }
	end
	local decoded, err = readToml(registryPath)
	if not decoded then
		return nil, err
	end
	decoded.projects = type(decoded.projects) == "table" and decoded.projects or {}
	return decoded
end

function Project.writeRegistry(registryPath, registry)
	local parent = path.dirname(registryPath)
	if parent and parent ~= "" then
		fs.makeDir(parent, true)
	end
	fs.writeFile(registryPath, toml.encode(registry))
end

function Project.writeEditorSettings(projectPath, definitionFile)
	local vscodePath = path.join(projectPath, ".vscode")
	fs.makeDir(vscodePath, true)
	fs.writeFile(
		path.join(vscodePath, "settings.json"),
		json.encode({
			["luau-lsp.types.definitionFiles"] = {
				kinemium = definitionFile or "k.d.luau",
			},
		}, { pretty_indent = 1 })
	)
end

function Project.create(parentPath, name, options)
	options = options or {}
	assert(type(name) == "string" and name ~= "", "Project name is required")
	local projectPath = path.join(parentPath, name)
	if kind(projectPath) ~= "none" then
		error(`Path already exists: {projectPath}`)
	end

	fs.makeDir(projectPath, true)
	for _, directory in ipairs(Project.RequiredDirectories) do
		fs.makeDir(path.join(projectPath, directory), true)
	end

	local config = Project.defaultConfig(name)
	if options.description then
		config.info.desc = options.description
	end
	if options.dimension then
		config.info.dimension = options.dimension
	end
	if options.icon then
		config.info.icon = options.icon
	end

	fs.writeFile(path.join(projectPath, "kproj.toml"), toml.encode(config))
	Project.writeEditorSettings(projectPath, options.definitionFile)
	return absolute(projectPath), config
end

function Project.register(registryPath, projectPath, name, engineVersion)
	projectPath = absolute(projectPath)
	local manifest, err = Project.readManifest(projectPath)
	if not manifest then
		error(err)
	end
	name = name or (manifest.info and manifest.info.name) or path.basename(projectPath)
	local registry, registryErr = Project.readRegistry(registryPath)
	if not registry then
		error(`Could not read project registry: {registryErr}`)
	end
	registry.projects[name] = {
		name = name,
		path = projectPath,
		engine_version = engineVersion or "unknown",
		last_opened = os.time(),
		dimension = manifest.info and manifest.info.dimension or "3D",
		icon = manifest.info and manifest.info.icon or "",
	}
	Project.writeRegistry(registryPath, registry)
	return registry.projects[name]
end

function Project.unregister(registryPath, name)
	local registry, err = Project.readRegistry(registryPath)
	if not registry then
		error(`Could not read project registry: {err}`)
	end
	local key
	for candidate in pairs(registry.projects) do
		if string.lower(candidate) == string.lower(name) then
			key = candidate
			break
		end
	end
	if not key then
		return false
	end
	registry.projects[key] = nil
	Project.writeRegistry(registryPath, registry)
	return true
end

function Project.resolve(registryPath, value, engineRoot)
	if not value or value == "" then
		return nil, "Project name or path is required"
	end

	local candidates = { value, path.join(zune.process.cwd(), value) }
	if engineRoot then
		table.insert(candidates, path.join(engineRoot, "src", "projects", value))
		table.insert(candidates, path.join(engineRoot, "projects", value))
	end
	for _, candidate in ipairs(candidates) do
		if kind(candidate) == "directory" and kind(Project.manifestPath(candidate)) == "file" then
			return absolute(candidate)
		end
	end

	local registry, err = Project.readRegistry(registryPath)
	if not registry then
		return nil, `Could not read project registry: {err}`
	end
	for name, entry in pairs(registry.projects) do
		if string.lower(name) == string.lower(value) and type(entry.path) == "string" then
			if kind(entry.path) == "directory" and kind(Project.manifestPath(entry.path)) == "file" then
				return absolute(entry.path), entry
			end
			return nil, `Registered project path is missing or invalid: {entry.path}`
		end
	end
	return nil, `Project '{value}' was not found`
end

function Project.list(registryPath)
	local registry, err = Project.readRegistry(registryPath)
	if not registry then
		return nil, err
	end
	local projects = {}
	for name, entry in pairs(registry.projects) do
		table.insert(projects, {
			name = name,
			path = entry.path,
			valid = type(entry.path) == "string" and kind(entry.path) == "directory" and kind(
				Project.manifestPath(entry.path)
			) == "file",
			entry = entry,
		})
	end
	table.sort(projects, function(a, b)
		return string.lower(a.name) < string.lower(b.name)
	end)
	return projects
end

function Project.repair(projectPath, definitionFile)
	local repaired = {}
	for _, directory in ipairs(Project.RequiredDirectories) do
		local directoryPath = path.join(projectPath, directory)
		if kind(directoryPath) ~= "directory" then
			fs.makeDir(directoryPath, true)
			table.insert(repaired, directoryPath)
		end
	end
	local manifestPath = path.join(projectPath, "kproj.toml")
	if kind(manifestPath) ~= "file" then
		local legacyPath = path.join(projectPath, "project.kproj")
		if kind(legacyPath) == "file" then
			fs.copy(legacyPath, manifestPath, true)
		else
			fs.writeFile(manifestPath, toml.encode(Project.defaultConfig(path.basename(projectPath))))
		end
		table.insert(repaired, manifestPath)
	end
	local settingsPath = path.join(projectPath, ".vscode", "settings.json")
	if kind(settingsPath) ~= "file" then
		Project.writeEditorSettings(projectPath, definitionFile)
		table.insert(repaired, settingsPath)
	end
	return repaired
end

Project.kind = kind
Project.absolute = absolute

return Project
