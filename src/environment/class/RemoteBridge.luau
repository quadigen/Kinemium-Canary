local signal = require("@Kinemium.signal")
local ReplicationSchema = require("@ReplicationSchema")
local Enum = require("@EnumMap")

local RemoteBridge = {}

local EVENT_CHANNEL = "__kinemium_remote_event"
local FUNCTION_CHANNEL = "__kinemium_remote_function"
local DATA_CHANNEL = "__kinemium_remote_data"
local nextRequestId = 0

local function getWorld(service)
	local active = service and service.GetActiveReplicator and service:GetActiveReplicator()
	return active and active.world or nil
end

local function validateReferences(value, world, seen)
	if type(value) ~= "table" then
		return
	end
	if value.ClassName then
		if not world then
			error("remote Instance arguments require an active replicator", 5)
		end
		if not world:GetId(value) then
			error("remote Instance argument is not replicated", 5)
		end
		return
	end
	if value.__type == "EnumItem"
		or value.__type == "Vector3"
		or value.__type == "CFrame"
		or value.__type == "Color3"
	then
		return
	end
	seen = seen or {}
	if seen[value] then
		error("cannot send a circular remote table", 5)
	end
	seen[value] = true
	for key, child in pairs(value) do
		validateReferences(key, world, seen)
		validateReferences(child, world, seen)
	end
	seen[value] = nil
end

local function encodeValue(value, service)
	if not ReplicationSchema.IsSafeValue(value) then
		error(`unsupported or unsafe remote value ({type(value)})`, 4)
	end
	local world = getWorld(service)
	validateReferences(value, world)
	local encoded = ReplicationSchema.EncodeValue(value, world)
	return encoded
end

local function decodeValue(value, service)
	return ReplicationSchema.DecodeValue(value, getWorld(service), Enum)
end

local function packArguments(service, ...)
	local arguments = { n = select("#", ...) }
	for index = 1, arguments.n do
		arguments[index] = encodeValue(select(index, ...), service)
	end
	return arguments
end

local function unpackArguments(arguments, service)
	arguments = type(arguments) == "table" and arguments or {}
	local count = tonumber(arguments.n) or #arguments
	local decoded = { n = count }
	for index = 1, count do
		decoded[index] = decodeValue(arguments[index], service)
	end
	return table.unpack(decoded, 1, count)
end

local function getService(datamodel)
	return datamodel and datamodel:GetService("ReplicatorService") or nil
end

local function getRemoteId(instance)
	local id = instance and instance.NetworkId
	if type(id) ~= "number" then
		error(`{instance and instance.ClassName or "Remote"} must be parented under ReplicatedStorage before use`, 3)
	end
	return id
end

local function matches(instance, payload)
	return type(payload) == "table" and payload.remoteId == instance.NetworkId
end

function RemoteBridge.BindEvent(instance, datamodel, reliable)
	local service = getService(datamodel)
	if service then
		if IsServer == true then
			service:OnEvent(EVENT_CHANNEL, function(player, payload)
				if matches(instance, payload) then
					instance.OnServerEvent:Fire(player, unpackArguments(payload.arguments, service))
				end
			end)
		else
			service:OnEvent(EVENT_CHANNEL, function(payload)
				if matches(instance, payload) then
					instance.OnClientEvent:Fire(unpackArguments(payload.arguments, service))
				end
			end)
		end
	end

	function instance:FireServer(...)
		if IsServer == true then
			error("FireServer can only be called from a client", 2)
		end
		return service and service:SendEvent(EVENT_CHANNEL, {
			remoteId = getRemoteId(self),
			arguments = packArguments(service, ...),
		}, reliable) or false
	end

	function instance:FireClient(player, ...)
		if IsServer ~= true then
			error("FireClient can only be called from the server", 2)
		end
		return service and service:SendEventTo(player, EVENT_CHANNEL, {
			remoteId = getRemoteId(self),
			arguments = packArguments(service, ...),
		}, reliable) or false
	end

	function instance:FireAllClients(...)
		if IsServer ~= true then
			error("FireAllClients can only be called from the server", 2)
		end
		return service and service:SendEvent(EVENT_CHANNEL, {
			remoteId = getRemoteId(self),
			arguments = packArguments(service, ...),
		}, reliable) or false
	end

	-- Compatibility with older Kinemium scripts.
	instance.Fire = instance.FireClient
end

function RemoteBridge.BindFunction(instance, datamodel)
	local service = getService(datamodel)
	local pending = {}

	local function resolve(payload)
		local waiter = pending[payload.requestId]
		if waiter then
			pending[payload.requestId] = nil
			waiter:Fire(payload.ok == true, payload.results, payload.error)
		end
	end

	local function execute(callback, player, payload)
		if type(callback) ~= "function" then
			return false, nil, "remote invoke callback is not assigned"
		end
		local returned
		local ok, err = xpcall(function()
			returned = if player ~= nil
				then packArguments(service, callback(player, unpackArguments(payload.arguments, service)))
				else packArguments(service, callback(unpackArguments(payload.arguments, service)))
		end, debug.traceback)
		return ok, returned, ok and nil or tostring(err)
	end

	if service then
		if IsServer == true then
			service:OnEvent(FUNCTION_CHANNEL, function(player, payload)
				if not matches(instance, payload) then return end
				if payload.operation == "response" then
					resolve(payload)
				elseif payload.operation == "invoke" then
					local ok, results, invokeError = execute(instance.OnServerInvoke, player, payload)
					service:SendEventTo(player, FUNCTION_CHANNEL, {
						remoteId = instance.NetworkId,
						operation = "response",
						requestId = payload.requestId,
						ok = ok,
						results = results,
						error = invokeError,
					}, true)
				end
			end)
		else
			service:OnEvent(FUNCTION_CHANNEL, function(payload)
				if not matches(instance, payload) then return end
				if payload.operation == "response" then
					resolve(payload)
				elseif payload.operation == "invoke" then
					local ok, results, invokeError = execute(instance.OnClientInvoke, nil, payload)
					service:SendEvent(FUNCTION_CHANNEL, {
						remoteId = instance.NetworkId,
						operation = "response",
						requestId = payload.requestId,
						ok = ok,
						results = results,
						error = invokeError,
					}, true)
				end
			end)
		end
	end

	local function invoke(self, player, ...)
		nextRequestId += 1
		local requestId = nextRequestId
		local waiter = signal.new()
		pending[requestId] = waiter
		local payload = {
			remoteId = getRemoteId(self),
			operation = "invoke",
			requestId = requestId,
			arguments = packArguments(service, ...),
		}
		local sent = if player ~= nil
			then service and service:SendEventTo(player, FUNCTION_CHANNEL, payload, true)
			else service and service:SendEvent(FUNCTION_CHANNEL, payload, true)
		if not sent then
			pending[requestId] = nil
			error("remote invoke could not be sent", 3)
		end
		local resumed, ok, results, invokeError = waiter:Wait(math.max(tonumber(self.InvokeTimeout) or 10, 0.01))
		pending[requestId] = nil
		if not resumed then
			error(`remote invoke timed out after {tostring(self.InvokeTimeout)} seconds`, 3)
		end
		if not ok then
			error(invokeError or "remote invoke failed", 3)
		end
		return unpackArguments(results, service)
	end

	function instance:InvokeServer(...)
		if IsServer == true then error("InvokeServer can only be called from a client", 2) end
		return invoke(self, nil, ...)
	end

	function instance:InvokeClient(player, ...)
		if IsServer ~= true then error("InvokeClient can only be called from the server", 2) end
		if not player then error("InvokeClient requires a Player", 2) end
		return invoke(self, player, ...)
	end
end

function RemoteBridge.BindData(instance, datamodel)
	local service = getService(datamodel)
	if service then
		if IsServer == true then
			service:OnEvent(DATA_CHANNEL, function(player, payload)
				if matches(instance, payload) then
					local value = decodeValue(payload.data, service)
					instance.Data = value
					instance.LastWriter = player
					service:SendEvent(DATA_CHANNEL, {
						remoteId = instance.NetworkId,
						data = encodeValue(value, service),
					}, true)
				end
			end)
		else
			service:OnEvent(DATA_CHANNEL, function(payload)
				if matches(instance, payload) then
					instance.Data = decodeValue(payload.data, service)
				end
			end)
		end
	end

	function instance:SetData(value)
		self.Data = value
		local payload = { remoteId = getRemoteId(self), data = encodeValue(value, service) }
		return service and service:SendEvent(DATA_CHANNEL, payload, true) or false
	end

	function instance:GetData()
		return self.Data
	end
end

return RemoteBridge
