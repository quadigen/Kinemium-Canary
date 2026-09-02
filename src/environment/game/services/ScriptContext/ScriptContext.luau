local Instance = require("@Instance")
local Enum = require("@EnumMap")
local kilang = require("@kilang")
local datatypes = require("@Kinemium.datatypes.get")
local Registry = require("@Kinemium.registry")

local Vector3 = require("@Vector3")
local CFrame = require("@CFrame")
local Color3 = require("@Color3")
local BrickColor = require("@BrickColor")
local UDim2 = require("@UDim2")
local UDim = require("@UDim")
local Ray = require("@Ray")
local RaycastParams = require("@RaycastParams")
local TweenInfo = require("@TweenInfo")

local ScriptContext = Instance.new("ScriptContext")
ScriptContext.ExplorerHidden = true
ScriptContext._Intents = Enum.PluginIntents.Threading

local activeThreads = {}

export type LanguageRuntime = {
	newthread: (Instance, DataModel) -> (),
	killthread: (thread) -> (),
}

local console_log = function(log)
	print(log)
end
local ishared = {}
local shared = {}

ScriptContext.InitRenderer = function(renderer, signal, datamodel)
	pcall(function()
		if datatypes and datatypes.Init then
			datatypes:Init(datamodel, renderer, datatypes)
		end
	end)

	local requiredCache = {}
	local REQUIRE_LOADING = {}
	local REQUIRE_NIL = {}

	local function getLogService()
		local ok, serv = pcall(function()
			return datamodel:GetService("LogService")
		end)
		return ok and serv or nil
	end

	local function buildScriptEnvironment(scriptObject, customRequire)
		local env = table.clone(datatypes)

		if kilang and kilang.env then
			for k, v in pairs(kilang.env) do
				env[k] = v
			end
		end

		env.Vector3 = env.Vector3 or Vector3
		env.CFrame = env.CFrame or CFrame
		env.Color3 = env.Color3 or Color3
		env.BrickColor = env.BrickColor or BrickColor
		env.UDim2 = env.UDim2 or UDim2
		env.UDim = env.UDim or UDim
		env.Ray = env.Ray or Ray
		env.RaycastParams = env.RaycastParams or RaycastParams
		env.TweenInfo = env.TweenInfo or TweenInfo

		env.Instance = {
			new = function(class, parent)
				local Object = Registry.new(class, renderer, datamodel)
				if parent and Object then
					Object.Parent = parent
				end
				return Object
			end,
			getClasses = Registry.getClasses,
			GetActiveInstances = Registry.GetActiveInstances,
		}

		env.game = datamodel
		env.workspace = datamodel:GetService("Workspace")
		env.Enum = Enum
		env.shared = shared
		env.ishared = ishared
		env.script = scriptObject
		env.require = customRequire

		local taskSubCount = 0
		local scriptName = scriptObject and (scriptObject.Name .. " (" .. tostring(scriptObject:GetFullName()) .. ")") or "SandboxedScript"

		env.task = {
			cancel = zune.task.cancel,
			wait = zune.task.wait,
			spawn = function(fn, ...)
				local th = zune.task.spawn(fn, ...)
				taskSubCount += 1
				if type(th) == "thread" and kilang and kilang.threads then
					kilang.threads[`{scriptName} (task.spawn #{taskSubCount})`] = th
				end
				return th
			end,
			defer = function(fn, ...)
				local th = zune.task.defer(fn, ...)
				taskSubCount += 1
				if type(th) == "thread" and kilang and kilang.threads then
					kilang.threads[`{scriptName} (task.defer #{taskSubCount})`] = th
				end
				return th
			end,
			delay = function(dt, fn, ...)
				local th = zune.task.delay(dt, fn, ...)
				taskSubCount += 1
				if type(th) == "thread" and kilang and kilang.threads then
					kilang.threads[`{scriptName} (task.delay #{taskSubCount})`] = th
				end
				return th
			end,
			desynchronize = function()
				local thread = coroutine.running()
				if thread then
					zune.task.defer(thread)
					coroutine.yield()
				end
			end,
			synchronize = function()
				local thread = coroutine.running()
				if thread then
					zune.task.defer(thread)
					coroutine.yield()
				end
			end,
		}
		env.wait = zune.task.wait
		env.tick = function()
			return os.clock()
		end

		env.typeof = function(v)
			if type(v) == "table" then
				if rawget(v, "BaseClass") == "Instance" then
					return "Instance"
				end
				local t = rawget(v, "type")
				if t then
					return t
				end
				local t2 = rawget(v, "__type")
				if t2 then
					return t2
				end
				return "table"
			else
				return type(v)
			end
		end

		env.print = function(...)
			local logServ = getLogService()
			if logServ and logServ.CreateLog then
				pcall(logServ.CreateLog, "print", ...)
			end
			print(...)
		end

		env.warn = function(...)
			local logServ = getLogService()
			if logServ and logServ.CreateLog then
				pcall(logServ.CreateLog, "warn", ...)
			end
			warn(...)
		end

		env.error = function(...)
			local logServ = getLogService()
			if logServ and logServ.CreateLog then
				pcall(logServ.CreateLog, "error", ...)
			end
			error(...)
		end

		env.buffer = {
			copy = buffer.copy,
			create = buffer.create,
			len = buffer.len,
			tostring = buffer.tostring,
			fromstring = buffer.fromstring,
			readi8 = buffer.readi8,
			readi16 = buffer.readi16,
			readi32 = buffer.readi32,
			readu8 = buffer.readu8,
			readu16 = buffer.readu16,
			readu32 = buffer.readu32,
			readf32 = buffer.readf32,
			readf64 = buffer.readf64,
			readstring = buffer.readstring,
			readbits = buffer.readbits,
			writei8 = buffer.writei8,
			writei16 = buffer.writei16,
			writei32 = buffer.writei32,
			writeu8 = buffer.writeu8,
			writeu16 = buffer.writeu16,
			writeu32 = buffer.writeu32,
			writef32 = buffer.writef32,
			writef64 = buffer.writef64,
			writestring = buffer.writestring,
			writebits = buffer.writebits,
			readi64 = function(b: buffer, offset: number): number
				local lo = buffer.readu32(b, offset)
				local hi = buffer.readi32(b, offset + 4)
				return hi * 2 ^ 32 + lo
			end,
			writei64 = function(b: buffer, offset: number, value: number)
				local lo = value % 2 ^ 32
				local hi = math.floor(value / 2 ^ 32)
				buffer.writeu32(b, offset, lo)
				buffer.writei32(b, offset + 4, hi)
			end,
			readu64 = function(b: buffer, offset: number): number
				local lo = buffer.readu32(b, offset)
				local hi = buffer.readu32(b, offset + 4)
				return hi * 2 ^ 32 + lo
			end,
			writeu64 = function(b: buffer, offset: number, value: number)
				local lo = value % 2 ^ 32
				local hi = math.floor(value / 2 ^ 32)
				buffer.writeu32(b, offset, lo)
				buffer.writeu32(b, offset + 4, hi)
			end,
			fill = function(b: buffer, value: number, offset: number?, length: number?)
				local start = offset or 0
				local stop = start + (length or buffer.len(b) - start)
				for i = start, stop - 1 do
					buffer.writeu8(b, i, value)
				end
			end,
			slice = function(b: buffer, offset: number, length: number): buffer
				local out = buffer.create(length)
				buffer.copy(out, 0, b, offset, length)
				return out
			end,
			concat = function(a: buffer, b: buffer): buffer
				local aLen = buffer.len(a)
				local bLen = buffer.len(b)
				local out = buffer.create(aLen + bLen)
				buffer.copy(out, 0, a, 0, aLen)
				buffer.copy(out, aLen, b, 0, bLen)
				return out
			end,
			equals = function(a: buffer, b: buffer): boolean
				local len = buffer.len(a)
				if len ~= buffer.len(b) then
					return false
				end
				for i = 0, len - 1 do
					if buffer.readu8(a, i) ~= buffer.readu8(b, i) then
						return false
					end
				end
				return true
			end,
		}

		return env
	end

	local function hasExplicitNilReturn(source)
		if type(source) ~= "string" then
			return false
		end

		local withoutTrailingWhitespace = source:gsub("%s+$", "")
		return withoutTrailingWhitespace:match("return%s+nil%s*$") ~= nil
			or withoutTrailingWhitespace:match("return%s+nil%s*::") ~= nil
	end

	local function hasReturnStatement(source)
		if type(source) ~= "string" then
			return false
		end

		return source:match("^%s*return[%s%(]") ~= nil or source:match("\n%s*return[%s%(]") ~= nil
	end

	local function tryResolveModuleScript(target)
		if type(target) ~= "table" then
			return nil
		end

		if target.ClassName == "ModuleScript" then
			return target
		end

		if target.FindFirstChild then
			local initModule = target:FindFirstChild("init") or target:FindFirstChild("Init")
			if initModule and initModule.ClassName == "ModuleScript" then
				return initModule
			end
		end

		return nil
	end

	local function getSourceLine(source, lineNumber, contextAfter, contextBefore)
		if not source or not lineNumber then
			return nil
		end

		contextAfter = contextAfter or 4
		contextBefore = contextBefore or 0

		local lines = {}
		local currentLine = 0
		for line in (source .. "\n"):gmatch("(.-)\n") do
			currentLine += 1
			lines[currentLine] = line
		end

		local startLine = math.max(1, lineNumber - contextBefore)
		local endLine = math.min(#lines, lineNumber + contextAfter)

		local result = {}
		for i = startLine, endLine do
			local marker = (i == lineNumber) and ">> " or "   "
			table.insert(result, string.format("%s%d: %s", marker, i, lines[i]))
		end

		return table.concat(result, "\n")
	end

	local function getModuleStackId(moduleScript)
		local fullName = moduleScript.Name
		if moduleScript.GetFullName then
			fullName = moduleScript:GetFullName()
		end
		return `{fullName}#{moduleScript.UniqueId}`
	end

	task.spawn(function()
		local function getserv(service)
			repeat
				task.wait()
			until datamodel.Loaded == true
			return datamodel:GetService(service)
		end

		local pluginLoader = getserv("PluginLoader")

		local runtimes = {
			Luau = {
				newthread = function(scriptObject: Instance, datamodel: DataModel)
					local customRequire
					customRequire = function(target)
						if type(target) == "string" then
							if target:match("^@kine/") then
								local name = string.sub(target, 7)
								local api = require(`@{name}`) or require("../src/environment/builtin/" .. name)
								if api then
									return api:init(renderer, datamodel)
								end
							end
							local api = pluginLoader.GetPluginApi(target)
							if api then
								return api
							end
							return require(target)
						end

						if type(target) ~= "table" then
							print("require: expected ModuleScript or string, got " .. type(target), 2)
							return
						end

						if target.ClassName == nil then
							print("DEBUG require target is plain table:", target)
							print(debug.traceback())
						end

						local moduleScript = tryResolveModuleScript(target)
						if not moduleScript then
							if type(target) == "table" and rawget(target, "Destroyed") then
								console_log(
									`require: target was Destroyed before require completed. `
										.. `UniqueId={rawget(target, "_props") and rawget(target, "_props").UniqueId or "?"}`,
									2
								)
							else
								print(
									`require: cannot require {target.ClassName} '{target.Name}'; expected ModuleScript`,
									2
								)
							end
							return
						end
						target = moduleScript

						local cached = requiredCache[target]
						if cached == REQUIRE_NIL then
							return nil
						end
						if cached == REQUIRE_LOADING then
							console_log(`require: circular dependency detected on '{target.Name}'`, 2)
							return
						end
						if cached ~= nil then
							return cached
						end

						requiredCache[target] = REQUIRE_LOADING

						local source = target.Source
						local success, result, id, thread, getResult
						if source and type(source) == "string" then
							local moduleEnv = buildScriptEnvironment(target, customRequire)
							moduleEnv.src = target
							moduleEnv.loader = scriptObject

							id, success, result, thread, getResult = kilang:execute(
								source,
								{ StackId = getModuleStackId(target) },
								moduleEnv
							)
						end

						if getResult then
							success, result = getResult()
							if id then
								kilang:remove(id)
							end
						end

						if thread then
							-- save thread
							if not activeThreads["Luau"] then
								activeThreads["Luau"] = {}
							end
							activeThreads["Luau"][target.UniqueId] = thread
						end

						if success == false then
							requiredCache[target] = nil

							local errMsg = tostring(result)
							local lineNumber = tonumber(errMsg:match(":(%d+):"))
							local sourceContext = getSourceLine(source, lineNumber)

							if sourceContext then
								console_log(
									`require: ModuleScript '{target.Name}' failed: {errMsg}\n{sourceContext}`,
									2
								)
							else
								console_log(`require: ModuleScript '{target.Name}' failed: {errMsg}`, 2)
							end

							return
						end

						if result == nil and not hasExplicitNilReturn(source) then
							requiredCache[target] = REQUIRE_NIL
							if not hasReturnStatement(source) then
								console_log(`require: ModuleScript '{target.Name}' did not return a value`, 2)
							end
							return nil
						elseif result == nil then
							requiredCache[target] = REQUIRE_NIL
							return nil
						end

						requiredCache[target] = result
						return result
					end

					local script_environment = buildScriptEnvironment(scriptObject, customRequire)
					local source = scriptObject.Source
					print("DEBUG Source length for", scriptObject.Name, ":", source and #source or "NIL SOURCE")
					if not activeThreads["Luau"] then
						activeThreads["Luau"] = {}
					end

					local id, success, result, thread = kilang:execute(
						source,
						{ StackId = `{scriptObject.Name} ({scriptObject:GetFullName()})` },
						script_environment
					)

					-- add to thread table
					activeThreads["Luau"][scriptObject.UniqueId] = thread

					return thread, id, success, result
				end,

				killthread = function(uniqueId)
					local thread = activeThreads["Luau"][uniqueId]
					if thread then
						task.cancel(thread)
						activeThreads["Luau"][uniqueId] = nil
					end
				end,
			},
		}

		local function runScriptOfClass(object, class)
			for _, descendant in pairs(object:GetDescendantsOfClass(class)) do
				if descendant.Enabled == false then
					return
				end
				task.spawn(function()
					ScriptContext.MakeThreadObject(descendant)
				end)
			end

			object.DescendantAdded:Connect(function(descendant)
				if descendant.ClassName == class then
					if descendant.Enabled == false then
						return
					end
					task.spawn(function()
						ScriptContext.MakeThreadObject(descendant)
					end)
				end
			end)

			object.DescendantRemoving:Connect(function(descendant)
				if descendant.ClassName == class then
					ScriptContext.KillThread(descendant.UniqueId, descendant.Language)
				end
			end)
		end

		ScriptContext:SetProperties({
			NewRuntime = function(api: LanguageRuntime)
				local name = api.name

				if not api.newthread then
					print("Runtime function newthread not found")
					return
				end

				if not api.killthread then
					print("Runtime function killthread not found")
					return
				end

				runtimes[name] = api

				Enum.newValue(name, math.random(1, 1000), Enum.Language)

				return Enum.Language[name]
			end,

			GetActiveThreads = function()
				return activeThreads
			end,

			GetRuntimeThreadsActive = function(language)
				return activeThreads[language.Name]
			end,

			KillThread = function(uniqueId: string, language: Enum.Language)
				local api = runtimes[language.Name]
				if api then
					api.killthread(uniqueId)
				end
			end,

			MakeThreadObject = function(scriptInstance: Script | LocalScript)
				local language = scriptInstance.Language.Name
				if language then
					if runtimes[language] then
						local api: LanguageRuntime? = runtimes[language]
						if api then
							print("Made thread")
							return api.newthread(scriptInstance, datamodel)
						end
					else
						print("No runtime found for language " .. language)
						return
					end
				end
				return
			end,

			RunSource = function(source: string, language: string, name: string?)
				language = language or "Luau"
				name = name or "AnonymousScript" .. tostring(math.random(1, 1e9))

				local fakeScript = {
					ClassName = "Script",
					Name = name,
					Source = source,
					Enabled = true,
					UniqueId = name .. "_" .. tostring(math.random(1, 1e9)),
					Language = Enum.Language[language],
					GetFullName = function()
						return name
					end,
				}

				local api = runtimes[language]
				if not api then
					print("No runtime found for language " .. language)
					return nil
				end

				return api.newthread(fakeScript, datamodel)
			end,

			RunClientScripts = function()
				local StarterPlayer, Players, CoreGui, InternalStorage =
					getserv("StarterPlayer"),
					getserv("Players"),
					getserv("CoreGui"),
					getserv("InternalStorage")

				runScriptOfClass(StarterPlayer, "LocalScript")
				runScriptOfClass(Players, "LocalScript")
				runScriptOfClass(CoreGui, "LocalScript")
				runScriptOfClass(InternalStorage, "LocalScript")

				return true
			end,

			RunServerScripts = function()
				local ServerScriptService, ServerStorage, Workspace, StarterGui =
					getserv("ServerScriptService"),
					getserv("ServerStorage"),
					getserv("Workspace"),
					getserv("StarterGui")

				runScriptOfClass(ServerScriptService, "Script")
				runScriptOfClass(ServerStorage, "Script")
				runScriptOfClass(Workspace, "Script")
				runScriptOfClass(StarterGui, "Script")

				return true
			end,
		})
	end)
end

return ScriptContext
