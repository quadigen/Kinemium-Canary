local ffi = zune.ffi
local enet = require("@enet_ffi")
local state = require("@GNS/state")
local Serializer = require("@GNS/Serializer")
local task = zune.task

local Client = {}
Client.__index = Client

local MAX_EVENTS_PER_POLL = 128

local function stringToPtr(value)
	return ffi.dupe(buffer.fromstring(value .. "\0"))
end

local function pointerToBuffer(ptr, size)
	local result = buffer.create(size)
	for i = 0, size - 1 do
		buffer.writeu8(result, i, ptr:readu8(i))
	end
	return result
end

local function sendSerialized(peer, data, reliable)
	local ok, serialized = pcall(Serializer.Serialize, data)
	if not ok then
		warn("[ENet][Client] Failed to serialize:", serialized)
		return false
	end

	local size = buffer.len(serialized)
	local payload = ffi.alloc(size)
	payload:write(0, serialized, 0, size)
	local sent = enet.lib.Kine_ENet_Peer_Send(peer, reliable and 0 or 1, payload, size, reliable and 1 or 0)
	ffi.free(payload)
	return sent ~= 0, size
end

function Client.new()
	return setmetatable({
		Socket = nil,
		Host = nil,
		hConn = nil,
		_event = nil,
		ServerAddress = nil,
		ServerPort = nil,
		AuthToken = nil,
		IsAuthenticated = false,
		SessionId = nil,
		OnRecieveCallbacks = {},
		_OnShutdown = nil,
		ConnectArguments = nil,
		_connectAttemptId = 0,
		GnsConnected = false,
		EnetConnected = false,
		Stats = { bytesSent = 0, bytesReceived = 0, packetsSent = 0, packetsReceived = 0, malformedPackets = 0 },
	}, Client)
end

local function destroyTransport(self)
	state.UnregisterClient(self)
	if self._event then
		enet.lib.Kine_ENet_Event_Destroy(self._event)
		self._event = nil
	end
	if self.Host then
		enet.lib.Kine_ENet_Host_Destroy(self.Host)
		self.Host = nil
	end
	self.Socket = nil
	self.hConn = nil
	self.GnsConnected = false
	self.EnetConnected = false
end

local function openConnection(self)
	destroyTransport(self)

	local host = enet.lib.Kine_ENet_Host_Create(nil, 0, 1, 2, 0, 0)
	if not host or host == ffi.null then
		warn("[ENet][Client] Failed to create client host")
		return false
	end

	local address = stringToPtr(self.ServerAddress)
	local peer = enet.lib.Kine_ENet_Host_Connect(host, address, self.ServerPort, 2, 0)
	ffi.free(address)
	if not peer or peer == ffi.null then
		enet.lib.Kine_ENet_Host_Destroy(host)
		warn(`[ENet][Client] Connect failed for {self.ServerAddress}:{self.ServerPort}`)
		return false
	end

	self.Host = host
	self.Socket = host
	self.hConn = peer
	self._event = enet.lib.Kine_ENet_Event_Create()
	state.RegisterClient(self)
	return true
end

function Client:Init(serverAddress, serverPort, authToken)
	self.ServerAddress = serverAddress or "127.0.0.1"
	self.ServerPort = serverPort or 1234
	self.AuthToken = authToken or "default_enet_token"
	self.IsAuthenticated = false
	openConnection(self)
end

function Client:Listen() end

function Client:Connect(arguments)
	self.ConnectArguments = arguments
	if self.EnetConnected then
		self:Send({ type = "CONNECT", authToken = self.AuthToken, arguments = arguments }, true)
	end

	self._connectAttemptId += 1
	local attemptId = self._connectAttemptId
	task.spawn(function()
		for attempt = 1, 5 do
			task.wait(2)
			if attemptId ~= self._connectAttemptId or self.IsAuthenticated then
				return
			end
			if not self.EnetConnected then
				warn(`[ENet][Client] Connect retry {attempt} for {self.ServerAddress}:{self.ServerPort}`)
				openConnection(self)
			elseif self.ConnectArguments then
				self:Send({
					type = "CONNECT",
					authToken = self.AuthToken,
					arguments = self.ConnectArguments,
				}, true)
			end
		end
		if attemptId == self._connectAttemptId and not self.IsAuthenticated then
			warn("[ENet][Client] Failed to authenticate after repeated retries")
		end
	end)
end

function Client:Poll()
	if not self.Host or not self._event then
		return
	end

	for _ = 1, MAX_EVENTS_PER_POLL do
		local serviced = enet.lib.Kine_ENet_Host_Service(self.Host, self._event, 0)
		if serviced <= 0 then
			break
		end

		local eventType = enet.lib.Kine_ENet_Event_GetType(self._event)
		local peer = enet.lib.Kine_ENet_Event_GetPeer(self._event)
		if eventType == enet.Event.Connect and peer == self.hConn then
			self.GnsConnected = true
			self.EnetConnected = true
			if self.ConnectArguments then
				self:Send({
					type = "CONNECT",
					authToken = self.AuthToken,
					arguments = self.ConnectArguments,
				}, true)
			end
		elseif eventType == enet.Event.Receive and peer == self.hConn then
			local payload = enet.lib.Kine_ENet_Event_GetPayload(self._event)
			local size = enet.lib.Kine_ENet_Event_GetPayloadSize(self._event)
			local rawPayload = pointerToBuffer(payload, size)
			self.Stats.bytesReceived += size
			self.Stats.packetsReceived += 1
			local ok, decoded = pcall(Serializer.Deserialize, rawPayload)
			if ok and decoded then
				self:HandlePacket(decoded)
			else
				self.Stats.malformedPackets += 1
				warn("[ENet][Client] Failed to deserialize message from server")
			end
		elseif eventType == enet.Event.Disconnect and peer == self.hConn then
			enet.lib.Kine_ENet_Event_Release(self._event)
			self:_CloseConnection(false, false)
			return
		end
		enet.lib.Kine_ENet_Event_Release(self._event)
	end
end

function Client:HandlePacket(msg)
	if msg.type == "AUTH_SUCCESS" then
		self.IsAuthenticated = true
		self.SessionId = msg.sessionId
		self._connectAttemptId += 1
	elseif msg.type == "AUTH_FAILED" or msg.type == "DISCONNECT" or msg.type == "SHUTDOWN" then
		self:Disconnect()
		return
	end

	for _, callback in ipairs(self.OnRecieveCallbacks) do
		task.spawn(callback, { address = self.ServerAddress, port = self.ServerPort }, msg)
	end
end

function Client:Send(data, reliable)
	if not self.hConn or not self.EnetConnected then
		return false
	end
	local sent, size = sendSerialized(self.hConn, data, reliable == true)
	if sent then
		self.Stats.bytesSent += size or 0
		self.Stats.packetsSent += 1
	end
	return sent
end

function Client:GetStats()
	return table.clone(self.Stats)
end

function Client:OnRecieve(callback)
	table.insert(self.OnRecieveCallbacks, callback)
end

function Client:OnShutdown(callback)
	self._OnShutdown = callback
end

function Client:StartHeartbeat() end

function Client:_CloseConnection(graceful, suppressShutdown)
	if graceful and self.hConn and self.Host then
		enet.lib.Kine_ENet_Peer_Disconnect(self.hConn, 0)
		enet.lib.Kine_ENet_Host_Flush(self.Host)
	elseif self.hConn then
		enet.lib.Kine_ENet_Peer_Reset(self.hConn)
	end

	destroyTransport(self)
	self.IsAuthenticated = false
	self.SessionId = nil
	if not suppressShutdown and self._OnShutdown then
		task.spawn(self._OnShutdown)
	end
end

function Client:Disconnect()
	self._connectAttemptId += 1
	if self.EnetConnected then
		self:Send({ type = "DISCONNECT" }, true)
		if self.Host then
			enet.lib.Kine_ENet_Host_Flush(self.Host)
		end
	end
	self:_CloseConnection(true, false)
end

return Client
