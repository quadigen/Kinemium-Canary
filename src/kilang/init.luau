-- kilang.lua
-- Runtime execution module for the Kinemium/Zune engine

local kilang = {}

local preprocessor = require("./kilang/Transpiler")
local luau = zune.luau

--  State

kilang.renderer = nil
kilang.env = {}
kilang.threads = {}

--  Internal: bytecode compile + load + exec

local function run_code(code, env, chunk, native_code_gen)
	local bytecode, compile_err = luau.compile(code, {
		optimization_level = 2,
	})
	if not bytecode then
		return nil, false, compile_err
	end

	local thread = luau.load(bytecode, {
		env = env,
		chunk_name = chunk,
		native_code_gen = native_code_gen,
	})

	setfenv(thread, setmetatable(env, { __index = getfenv(1) }))

	local ok, result = pcall(thread)
	return (ok and result or nil), ok, result
end

--  kilang:init

--- Initialise the runtime against a camera and renderer.
--- Returns the C-side environment handle.
---@param cam any
---@return any CEnv
function kilang:init(cam, Kinemium_env)
	local luaEnv, CEnv = Kinemium_env(self.renderer, cam)
	self.env = luaEnv
	return CEnv
end

--  kilang:execute

--- Transpile and execute a kilang script in an isolated environment.
---
---@param code      string   Source code to run
---@param opts      table?   Options: superset, SecurityCapabilities, StackId
---@param env_other table?   Additional environment bindings to inject
---@return string?  id       Stack ID for the spawned thread (nil on failure)
---@return boolean  success  Whether execution succeeded
---@return any      result   Return value or error message
---@return thread?  thread   The coroutine handle (if spawned)
function kilang:registerThread(id, thread)
	if type(thread) == "thread" then
		self.threads[tostring(id)] = thread
	end
end

function kilang:getThreads()
	local active = {}
	for id, thread in pairs(self.threads) do
		local status = "unavailable"
		if type(thread) == "thread" then
			local ok, s = pcall(coroutine.status, thread)
			status = ok and s or "unavailable"
		end
		active[id] = { thread = thread, status = status }
	end
	return active
end

function kilang:execute(code, opts, env_other)
	opts = opts or {}

	local superset = opts.superset or "kilang"
	local SecurityCapabilities = opts.SecurityCapabilities

	-- bandaid fix, is a large number so different stacks don't clash
	local id = opts.StackId or ("stack" .. math.random(0, 9999999))

	-- Don't allow duplicate stacks for the same ID unless the previous thread is dead
	if self.threads[id] and pcall(coroutine.status, self.threads[id]) and coroutine.status(self.threads[id]) ~= "dead" then
		return id, false, "Stack ID already running"
	end

	-- Build sandboxed environment: base env → caller overrides
	local environment = {}
	for k, v in pairs(self.env) do
		environment[k] = v
	end
	if env_other then
		for k, v in pairs(env_other) do
			environment[k] = v
		end
	end
	environment.SecurityCapabilities = SecurityCapabilities
	-- Engine classes/services execute with the Internals capability and need the
	-- native runtime for FFI-backed systems such as Box2D. User scripts retain
	-- the deliberately restricted `zune = 0` value supplied by environment/get.
	if SecurityCapabilities == 2 then
		environment.zune = zune
	end

	local taskCount = 0
	local baseTask = environment.task or zune.task
	if baseTask then
		environment.task = {
			cancel = baseTask.cancel or zune.task.cancel,
			wait = baseTask.wait or zune.task.wait,
			spawn = function(fn, ...)
				local th = baseTask.spawn(fn, ...)
				if type(th) == "thread" and pcall(coroutine.status, th) and coroutine.status(th) ~= "dead" then
					taskCount += 1
					self.threads[`{id} (task.spawn #{taskCount})`] = th
				end
				return th
			end,
			defer = function(fn, ...)
				local th = baseTask.defer(fn, ...)
				if type(th) == "thread" and pcall(coroutine.status, th) and coroutine.status(th) ~= "dead" then
					taskCount += 1
					self.threads[`{id} (task.defer #{taskCount})`] = th
				end
				return th
			end,
			delay = function(dt, fn, ...)
				local th = baseTask.delay(dt, fn, ...)
				if type(th) == "thread" and pcall(coroutine.status, th) and coroutine.status(th) ~= "dead" then
					taskCount += 1
					self.threads[`{id} (task.delay #{taskCount})`] = th
				end
				return th
			end,
			desynchronize = baseTask.desynchronize,
			synchronize = baseTask.synchronize,
		}
	end

	-- Execute on a task thread; capture success/result via upvalue
	local success, result
	local isFinished = false
	local thread = task.spawn(function()
		local _, s, r = run_code(code, environment, id, true)
		success = s
		result = r
		isFinished = true
		if not s and r ~= nil then
			print(`[Kilang Error] {id}: {tostring(r)}`)
		end
	end)

	-- Always register the thread so it can be cleaned up
	self.threads[id] = thread

	local function getResult()
		while not isFinished do
			task.wait()
		end
		return success, result
	end

	return id, success, result, thread, getResult
end

--  kilang:remove

--- Remove a tracked stack thread by ID.
---@param id string
function kilang:remove(id)
	self.threads[id] = nil
end

return kilang
