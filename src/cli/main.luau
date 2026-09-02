local fs = zune.fs
local path = fs.path
local process = zune.process
local Project = require("./project")

local CLI_VERSION = "1.0.0"
local ENGINE_VERSION = "1.10.7"

local cli = {}
local args = process.args

local function optionValue(name)
	local full = "--" .. name
	for index, value in ipairs(args) do
		if value == full then
			return args[index + 1]
		end
		local inline = value:match("^" .. full:gsub("%-", "%%-") .. "=(.*)$")
		if inline ~= nil then
			return inline
		end
	end
	return nil
end

local function hasOption(name)
	local full = "--" .. name
	for _, value in ipairs(args) do
		if value == full or value:match("^" .. full:gsub("%-", "%%-") .. "=") then
			return true
		end
	end
	return false
end

local function trailingArgs()
	for index, value in ipairs(args) do
		if value == "--" then
			local result = {}
			for i = index + 1, #args do
				table.insert(result, args[i])
			end
			return result
		end
	end
	return {}
end

local function isEngineRoot(candidate)
	return Project.kind(path.join(candidate, "src", "main.luau")) == "file"
		and Project.kind(path.join(candidate, "zune.toml")) == "file"
end

local function walkForEngineRoot(start)
	local current = start
	for _ = 1, 12 do
		if isEngineRoot(current) then
			return Project.absolute(current)
		end
		local parent = path.dirname(current)
		if not parent or parent == "" or parent == current then
			break
		end
		current = parent
	end
	return nil
end

local function findEngineRoot()
	local explicit = optionValue("engine-root") or process.env.KINEMIUM_ROOT
	if explicit then
		if isEngineRoot(explicit) then
			return Project.absolute(explicit)
		end
		return nil, `Engine root is invalid: {explicit}`
	end

	local roots = {
		process.cwd(),
		path.dirname(fs.getExePath()),
	}
	for _, start in ipairs(roots) do
		local found = walkForEngineRoot(start)
		if found then
			return found
		end
	end
	return nil, "Could not locate the Kinemium engine root; pass --engine-root PATH or set KINEMIUM_ROOT"
end

local function registryPath(engineRoot)
	if engineRoot and Project.kind(path.join(engineRoot, "src")) == "directory" then
		return path.join(engineRoot, "src", "projects.toml")
	end
	return path.join(engineRoot or process.cwd(), "projects.toml")
end

local function commandAndIndex()
	local commands = {
		help = true,
		version = true,
		create = true,
		init = true,
		add = true,
		list = true,
		remove = true,
		info = true,
		project = true,
		doctor = true,
		run = true,
	}
	for index, value in ipairs(args) do
		if commands[value] then
			if value == "project" then
				return args[index + 1] or "help", index + 1
			end
			return value, index
		end
	end
	return "help", 0
end

local function printHelp()
	print(`Kinemium CLI {CLI_VERSION}`)
	print([[

Usage:
  kinemium create NAME [--path DIRECTORY] [--no-register]
  kinemium init [NAME] [--path DIRECTORY]
  kinemium add PROJECT_PATH [--name NAME]
  kinemium list
  kinemium info PROJECT
  kinemium remove PROJECT
  kinemium doctor [PROJECT] [--fix]
  kinemium run PROJECT [--username NAME] [--watch] [-- ARGS...]

The project commands are also available as `kinemium project <command>`.
`remove` only removes the registry entry; it never deletes project files.

Engine discovery:
  --engine-root PATH       Engine source checkout
  --engine PATH            Runtime executable or src/main.luau
  KINEMIUM_ROOT            Default engine source checkout
  KINEMIUM_ENGINE          Default runtime executable
]])
end

local function fail(message, code)
	print("error: " .. tostring(message) .. "\n")
	return code or 1
end

local function resolveContext(requireEngine)
	local engineRoot, rootErr = findEngineRoot()
	if requireEngine and not engineRoot then
		return nil, nil, rootErr
	end
	local registry = registryPath(engineRoot or process.cwd())
	return engineRoot, registry
end

function cli:createProject(name, parent, registerProject)
	local engineRoot, registry, rootErr = resolveContext(registerProject)
	if registerProject and not engineRoot then
		error(rootErr)
	end
	local projectPath = Project.create(parent, name, {
		description = optionValue("description"),
		dimension = optionValue("dimension"),
		icon = optionValue("icon"),
		definitionFile = engineRoot and path.join(engineRoot, "k.d.luau") or "k.d.luau",
	})
	if registerProject then
		Project.register(registry, projectPath, name, ENGINE_VERSION)
	end
	return projectPath
end

local function doCreate(commandIndex, initializeCurrent)
	local requestedName = args[commandIndex + 1]
	local parent = optionValue("path") or process.cwd()
	if initializeCurrent then
		local target = optionValue("path") or process.cwd()
		requestedName = requestedName or path.basename(target)
		parent = path.dirname(Project.absolute(target))
		if Project.kind(target) ~= "none" then
			if Project.kind(Project.manifestPath(target)) == "file" then
				return fail(`Project already initialized: {target}`)
			end
			-- Project.create expects to own the final directory. Initialize through a temporary
			-- config path only when the directory is empty enough to preserve user files.
			for _, directory in ipairs(Project.RequiredDirectories) do
				fs.makeDir(path.join(target, directory), true)
			end
			fs.writeFile(path.join(target, "kproj.toml"), zune.serde.toml.encode(Project.defaultConfig(requestedName)))
			local engineRoot, registry = resolveContext(false)
			Project.writeEditorSettings(target, engineRoot and path.join(engineRoot, "k.d.luau") or "k.d.luau")
			if not hasOption("no-register") and engineRoot then
				Project.register(registry, target, requestedName, ENGINE_VERSION)
			end
			print(`Initialized project '{requestedName}' at {Project.absolute(target)}`)
			return 0
		end
	end
	if not requestedName or requestedName:sub(1, 2) == "--" then
		return fail("Project name is required")
	end
	local ok, result = pcall(cli.createProject, cli, requestedName, parent, not hasOption("no-register"))
	if not ok then
		return fail(result)
	end
	print(`Created project '{requestedName}' at {result}`)
	return 0
end

local function doAdd(commandIndex)
	local projectValue = args[commandIndex + 1]
	if not projectValue or projectValue:sub(1, 2) == "--" then
		return fail("Project path is required")
	end
	local engineRoot, registry, err = resolveContext(true)
	if not engineRoot then
		return fail(err)
	end
	local projectPath = Project.absolute(path.join(process.cwd(), projectValue))
	if Project.kind(projectValue) == "directory" then
		projectPath = Project.absolute(projectValue)
	end
	local ok, entry = pcall(Project.register, registry, projectPath, optionValue("name"), ENGINE_VERSION)
	if not ok then
		return fail(entry)
	end
	print(`Registered '{entry.name}' at {entry.path}`)
	return 0
end

local function doList()
	local engineRoot, registry, err = resolveContext(true)
	if not engineRoot then
		return fail(err)
	end
	local projects, listErr = Project.list(registry)
	if not projects then
		return fail(listErr)
	end
	if #projects == 0 then
		print("No registered projects.")
		return 0
	end
	for _, project in ipairs(projects) do
		print(`{project.valid and "ok" or "missing"}\t{project.name}\t{project.path}`)
	end
	return 0
end

local function resolveProjectArgument(commandIndex)
	local value = args[commandIndex + 1]
	if not value or value:sub(1, 2) == "--" then
		return nil, nil, nil, "Project name or path is required"
	end
	local engineRoot, registry, rootErr = resolveContext(true)
	if not engineRoot then
		return nil, nil, nil, rootErr
	end
	local projectPath, entryOrErr = Project.resolve(registry, value, engineRoot)
	if not projectPath then
		return nil, nil, nil, entryOrErr
	end
	return projectPath, engineRoot, registry
end

local function doInfo(commandIndex)
	local projectPath, _, _, err = resolveProjectArgument(commandIndex)
	if not projectPath then
		return fail(err)
	end
	local manifest, manifestErr = Project.readManifest(projectPath)
	if not manifest then
		return fail(manifestErr)
	end
	local info = manifest.info or {}
	print(`Name:        {info.name or path.basename(projectPath)}`)
	print(`Path:        {projectPath}`)
	print(`Dimension:   {info.dimension or "3D"}`)
	print(`Description: {info.desc or ""}`)
	print(`Live sync:   {manifest.sync and manifest.sync.live == true and "yes" or "no"}`)
	return 0
end

local function doRemove(commandIndex)
	local name = args[commandIndex + 1]
	if not name or name:sub(1, 2) == "--" then
		return fail("Registered project name is required")
	end
	local engineRoot, registry, err = resolveContext(true)
	if not engineRoot then
		return fail(err)
	end
	local ok, removed = pcall(Project.unregister, registry, name)
	if not ok then
		return fail(removed)
	end
	if not removed then
		return fail(`Project '{name}' is not registered`)
	end
	print(`Removed '{name}' from the registry. Project files were not deleted.`)
	return 0
end

local function diagnostic(label, ok, detail)
	print(`{ok and "PASS" or "FAIL"}  {label}{detail and " - " .. detail or ""}`)
	return ok
end

local function doDoctor(commandIndex)
	local failures = 0
	local engineRoot, registry, rootErr = resolveContext(false)
	if not diagnostic("engine root", engineRoot ~= nil, engineRoot or rootErr) then
		failures += 1
	end
	if engineRoot then
		if not diagnostic("engine entry", Project.kind(path.join(engineRoot, "src", "main.luau")) == "file") then
			failures += 1
		end
		if not diagnostic("zune config", Project.kind(path.join(engineRoot, "zune.toml")) == "file") then
			failures += 1
		end
		local suffix = zune.ffi.suffix
		local nativePath = path.join(engineRoot, "vendor", "KinemiumLibs." .. suffix)
		if not diagnostic("native runtime", Project.kind(nativePath) == "file", nativePath) then
			failures += 1
		end
		local _, registryErr = Project.readRegistry(registry)
		if not diagnostic("project registry", registryErr == nil, registryErr or registry) then
			failures += 1
		end
	end

	local projectValue = args[commandIndex + 1]
	if projectValue and projectValue:sub(1, 2) ~= "--" and engineRoot then
		local projectPath, resolveErr = Project.resolve(registry, projectValue, engineRoot)
		if not projectPath and hasOption("fix") and Project.kind(projectValue) == "directory" then
			projectPath = Project.absolute(projectValue)
		end
		if not projectPath then
			diagnostic("project", false, resolveErr)
			failures += 1
		else
			if hasOption("fix") then
				local repaired = Project.repair(projectPath, path.join(engineRoot, "k.d.luau"))
				for _, repairedPath in ipairs(repaired) do
					print(`FIXED {repairedPath}`)
				end
			end
			local manifest, manifestErr = Project.readManifest(projectPath)
			if
				not diagnostic("project manifest", manifest ~= nil, manifestErr or Project.manifestPath(projectPath))
			then
				failures += 1
			end
			for _, directory in ipairs(Project.RequiredDirectories) do
				local directoryPath = path.join(projectPath, directory)
				if not diagnostic(`project/{directory}`, Project.kind(directoryPath) == "directory") then
					failures += 1
				end
			end
			if manifest then
				local pointers = manifest.pointers or {}
				for _, required in ipairs({ "assets", "server", "client", "gui", "objects" }) do
					if
						not diagnostic(
							`pointer/{required}`,
							type(pointers[required]) == "string",
							tostring(pointers[required])
						)
					then
						failures += 1
					end
				end
			end
		end
	end

	print(failures == 0 and "Doctor found no problems." or `Doctor found {failures} problem(s).`)
	return failures == 0 and 0 or 1
end

local function runtimeCommand(engineRoot)
	local explicit = optionValue("engine") or process.env.KINEMIUM_ENGINE
	if explicit then
		explicit = Project.absolute(explicit)
		if Project.kind(explicit) ~= "file" then
			return nil, nil, nil, `Engine executable or script does not exist: {explicit}`
		end
		if explicit:match("%.luau$") or explicit:match("%.lua$") then
			return fs.getExePath(), { "run", explicit }, engineRoot
		end
		return explicit, {}, path.dirname(explicit)
	end

	local runtimeName = if zune.platform.os == "windows" then "KinemiumRuntime.exe" else "KinemiumRuntime"
	local siblingRuntime = path.join(path.dirname(fs.getExePath()), runtimeName)
	if Project.kind(siblingRuntime) == "file" and not isEngineRoot(engineRoot) then
		return siblingRuntime, {}, path.dirname(siblingRuntime)
	end

	local zuneExecutable = path.join(engineRoot, if zune.platform.os == "windows" then "zune.exe" else "zune")
	if Project.kind(zuneExecutable) ~= "file" then
		zuneExecutable = fs.getExePath()
	end
	return zuneExecutable, { "run", path.join(engineRoot, "src", "main.luau") }, engineRoot
end

local function doRun(commandIndex)
	local projectPath, engineRoot, _, err = resolveProjectArgument(commandIndex)
	if not projectPath then
		return fail(err)
	end
	local executable, engineArgs, cwd, runtimeErr = runtimeCommand(engineRoot)
	if not executable then
		return fail(runtimeErr)
	end
	table.insert(engineArgs, "--client")
	table.insert(engineArgs, "--offline")
	table.insert(engineArgs, "--project")
	table.insert(engineArgs, projectPath)
	table.insert(engineArgs, "--project-readonly")
	local username = optionValue("username") or process.env.USERNAME or process.env.USER or "Player"
	table.insert(engineArgs, "--username")
	table.insert(engineArgs, username)
	if hasOption("watch") then
		table.insert(engineArgs, "--project-watch")
	end
	for _, flag in ipairs({ "wgi", "max3dpixels", "min3dscale" }) do
		local value = optionValue(flag)
		if value then
			table.insert(engineArgs, "--" .. flag)
			table.insert(engineArgs, value)
		end
	end
	if hasOption("perfoverlay") then
		table.insert(engineArgs, "--perfoverlay")
	end
	table.insert(engineArgs, "--igs")
	for _, value in ipairs(trailingArgs()) do
		table.insert(engineArgs, value)
	end

	print(`Running local client playtest for {projectPath}`)
	local child = process.create(executable, engineArgs, {
		cwd = cwd,
		stdin = "inherit",
		stdout = "inherit",
		stderr = "inherit",
	})
	process.onSignal("INT", function()
		pcall(function()
			child:kill()
		end)
	end)
	local result = child:wait()
	return result.code or (result.ok and 0 or 1)
end

local command, commandIndex = commandAndIndex()
local exitCode = 0
if command == "help" then
	printHelp()
elseif command == "version" then
	print(`Kinemium CLI {CLI_VERSION}`)
elseif command == "create" then
	exitCode = doCreate(commandIndex, false)
elseif command == "init" then
	exitCode = doCreate(commandIndex, true)
elseif command == "add" then
	exitCode = doAdd(commandIndex)
elseif command == "list" then
	exitCode = doList()
elseif command == "info" then
	exitCode = doInfo(commandIndex)
elseif command == "remove" then
	exitCode = doRemove(commandIndex)
elseif command == "doctor" then
	exitCode = doDoctor(commandIndex)
elseif command == "run" then
	exitCode = doRun(commandIndex)
else
	printHelp()
	exitCode = 1
end

if exitCode ~= 0 then
	process.exit(exitCode)
end

return cli
