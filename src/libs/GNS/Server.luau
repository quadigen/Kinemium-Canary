local ffi = zune.ffi
local enet = require("@enet_ffi")
local state = require("@GNS/state")
local Serializer = require("@GNS/Serializer")
local task = zune.task

local Server = {}
Server.__index = Server

local MAX_EVENTS_PER_POLL = 128

local function stringToPtr(value)
	return ffi.dupe(buffer.fromstring(value .. "\0"))
end

local function peerKey(peer)
	return tostring(peer)
end

local function clientKey(client)
	return peerKey(client.hConn)
end

local function pointerToBuffer(ptr, size)
	local result = buffer.create(size)
	for i = 0, size - 1 do
		buffer.writeu8(result, i, ptr:readu8(i))
	end
	return result
end

local function readCString(ptr)
	local bytes = {}
	for i = 0, 255 do
		local byte = ptr:readu8(i)
		if byte == 0 then
			break
		end
		bytes[#bytes + 1] = string.char(byte)
	end
	return table.concat(bytes)
end

local function getPeerAddress(peer)
	local address = ffi.alloc(256)
	local port = ffi.alloc(2)
	local ok = enet.lib.Kine_ENet_Peer_GetAddress(peer, address, 256, port)
	local resultAddress = if ok ~= 0 then readCString(address) else "unknown"
	local resultPort = port:readu16(0)
	ffi.free(address)
	ffi.free(port)
	return resultAddress, resultPort
end

local function sendSerialized(peer, data, reliable)
	local ok, serialized = pcall(Serializer.Serialize, data)
	if not ok then
		warn("[ENet][Server] Failed to serialize:", serialized)
		return false
	end

	local size = buffer.len(serialized)
	local payload = ffi.alloc(size)
	payload:write(0, serialized, 0, size)
	local sent = enet.lib.Kine_ENet_Peer_Send(peer, reliable and 0 or 1, payload, size, reliable and 1 or 0)
	ffi.free(payload)
	return sent ~= 0, size
end

function Server.new()
	return setmetatable({
		Socket = nil,
		Host = nil,
		_event = nil,
		Address = nil,
		Port = nil,
		ConnectedClients = {},
		ConnectedClientsByConn = {},
		OnRecieveCallbacks = {},
		_onClientConnectionRequest = nil,
		_onClientRemoved = nil,
		_onPreAuthMessage = nil,
		Stats = { bytesSent = 0, bytesReceived = 0, packetsSent = 0, packetsReceived = 0, malformedPackets = 0 },
	}, Server)
end

function Server:Init(address, port, allowedTokens)
	self.Address = address or "0.0.0.0"
	self.Port = port or 1234

	local bindAddress = stringToPtr(self.Address)
	local host = enet.lib.Kine_ENet_Host_Create(
		bindAddress,
		self.Port,
		4095,
		2,
		0,
		0
	)
	ffi.free(bindAddress)
	assert(host and host ~= ffi.null, `[ENet][Server] Failed to bind {self.Address}:{self.Port}`)

	self.Host = host
	self.Socket = host
	self._event = enet.lib.Kine_ENet_Event_Create()
	state.RegisterServer(self)
end

function Server:Listen() end

function Server:AddClient(peer)
	local address, port = getPeerAddress(peer)
	local client = {
		address = address,
		port = port,
		hConn = peer,
		authenticated = false,
		sessionId = nil,
	}
	self.ConnectedClientsByConn[peerKey(peer)] = client
end

function Server:RemoveClient(peer, reason, alreadyDisconnected)
	local key = peerKey(peer)
	local client = self.ConnectedClientsByConn[key]
	if not client then
		return
	end

	self.ConnectedClientsByConn[key] = nil
	self.ConnectedClients[clientKey(client)] = nil
	if not alreadyDisconnected then
		enet.lib.Kine_ENet_Peer_Disconnect(peer, 0)
	end

	if client.authenticated and self._onClientRemoved then
		task.spawn(self._onClientRemoved, client)
	end
end

function Server:Poll()
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
		if eventType == enet.Event.Connect then
			self:AddClient(peer)
		elseif eventType == enet.Event.Receive then
			local payload = enet.lib.Kine_ENet_Event_GetPayload(self._event)
			local size = enet.lib.Kine_ENet_Event_GetPayloadSize(self._event)
			local rawPayload = pointerToBuffer(payload, size)
			self.Stats.bytesReceived += size
			self.Stats.packetsReceived += 1
			local ok, decoded = pcall(Serializer.Deserialize, rawPayload)
			if ok and decoded then
				self:HandlePacket(peer, decoded)
			else
				self.Stats.malformedPackets += 1
				warn(`[ENet][Server] Failed to deserialize message from {peerKey(peer)}`)
			end
		elseif eventType == enet.Event.Disconnect then
			self:RemoveClient(peer, "connection closed", true)
		end
		enet.lib.Kine_ENet_Event_Release(self._event)
	end
end

function Server:HandlePacket(peer, msg)
	local client = self.ConnectedClientsByConn[peerKey(peer)]
	if not client then
		return
	end

	if msg.type == "CONNECT" then
		client.authenticated = true
		client.sessionId = "enet_session_" .. peerKey(peer)
		self.ConnectedClients[clientKey(client)] = client
		self:Send(client, { type = "AUTH_SUCCESS", sessionId = client.sessionId }, true)
		if self._onClientConnectionRequest then
			task.spawn(self._onClientConnectionRequest, client, msg.arguments)
		end
		return
	elseif msg.type == "DISCONNECT" then
		self:RemoveClient(peer, "client requested disconnect", false)
		return
	elseif not client.authenticated then
		if self._onPreAuthMessage then
			task.spawn(self._onPreAuthMessage, client, msg)
		end
		return
	end

	for _, callback in ipairs(self.OnRecieveCallbacks) do
		task.spawn(callback, client, msg)
	end
end

function Server:Send(client, data, reliable)
	if not client or not client.hConn then
		return false
	end
	local sent, size = sendSerialized(client.hConn, data, reliable == true)
	if sent then
		self.Stats.bytesSent += size or 0
		self.Stats.packetsSent += 1
	end
	return sent
end

function Server:SendAll(data, reliable)
	for _, client in pairs(self.ConnectedClients) do
		if client.authenticated then
			self:Send(client, data, reliable)
		end
	end
	return true
end

function Server:SendFiltered(data, reliable, filterFn)
	for _, client in pairs(self.ConnectedClients) do
		if client.authenticated and (filterFn == nil or filterFn(client)) then
			self:Send(client, data, reliable)
		end
	end
	return true
end

function Server:OnClientConnectionRequest(callback)
	self._onClientConnectionRequest = callback
end

function Server:OnClientRemoved(callback)
	self._onClientRemoved = callback
end

function Server:OnRecieve(callback)
	table.insert(self.OnRecieveCallbacks, callback)
end

function Server:OnPreAuthMessage(callback)
	self._onPreAuthMessage = callback
end

function Server:IsClientConnected(client)
	return client ~= nil
		and client.hConn ~= nil
		and self.ConnectedClientsByConn[peerKey(client.hConn)] == client
		and client.authenticated == true
end

function Server:GetClientStats(client)
	if not client or not client.hConn then
		return { pendingReliable = 0, pendingReliableFragments = 0 }
	end
	return {
		pendingReliable = enet.lib.Kine_ENet_Peer_GetPendingReliableBytes(client.hConn),
		pendingReliableFragments = 0,
		bytesSent = self.Stats.bytesSent,
		bytesReceived = self.Stats.bytesReceived,
		packetsSent = self.Stats.packetsSent,
		packetsReceived = self.Stats.packetsReceived,
	}
end

function Server:GetStats()
	return table.clone(self.Stats)
end

function Server:Shutdown()
	state.UnregisterServer(self)
	local peers = {}
	for _, client in pairs(self.ConnectedClientsByConn) do
		peers[#peers + 1] = client.hConn
	end
	for _, peer in ipairs(peers) do
		self:RemoveClient(peer, "server shutdown", false)
	end
	if self.Host then
		enet.lib.Kine_ENet_Host_Flush(self.Host)
	end
	if self._event then
		enet.lib.Kine_ENet_Event_Destroy(self._event)
		self._event = nil
	end
	if self.Host then
		enet.lib.Kine_ENet_Host_Destroy(self.Host)
		self.Host = nil
	end
	self.Socket = nil
end

function Server:DisconnectClient(client, reason)
	if not client or not client.hConn then
		return false
	end
	self:RemoveClient(client.hConn, reason, false)
	return true
end

return Server
