local Enum = require("@Enum")
local NetIdAllocator = require("./NetIdAllocator")
local SnapshotHistory = require("./SnapshotHistory")
local InterpolationBuffer = require("./InterpolationBuffer")
local ReplicationSchema = require("./ReplicationSchema")
local NetworkOwnership = require("./NetworkOwnership")
local Sequence = require("./Sequence")

local ReplicationWorld = {}
ReplicationWorld.__index = ReplicationWorld

local DEFAULTS = {
	snapshotRate = 20,
	interpolationDelayTicks = 2,
	snapshotHistory = 64,
	bandwidthBudget = 48 * 1024,
	relevancyDistance = 1024,
	teleportThreshold = 12,
	maxExtrapolationTicks = 3,
	maxOwnedSpeed = 256,
	maxOwnedError = 12,
}

local function merge(defaults, options)
	local result = {}
	for key, value in pairs(defaults) do
		result[key] = value
	end
	for key, value in pairs(options or {}) do
		result[key] = value
	end
	return result
end

local function getPosition(instance)
	local cframe = instance and instance.CFrame
	if cframe and cframe.Position then
		return cframe.Position
	end
	local primary = instance and (instance.RootPart or instance.PrimaryPart)
	return primary and primary.CFrame and primary.CFrame.Position or nil
end

local function validTick(tick)
	return type(tick) == "number" and tick == tick and tick % 1 == 0 and tick >= 0 and tick < 2 ^ 32
end

local function setNetworkId(instance, id)
	local props = rawget(instance, "_props")
	if not props then
		return
	end
	props.NetworkId = id
	rawset(instance, "NetworkId", id)
end

function ReplicationWorld.new(role, datamodel, renderer, options)
	local self = setmetatable({}, ReplicationWorld)
	self.role, self.datamodel, self.renderer = role, datamodel, renderer
	self.config = merge(DEFAULTS, options)
	self.allocator = NetIdAllocator.new()
	self.ownership = NetworkOwnership.new()
	self.history = SnapshotHistory.new(self.config.snapshotHistory)
	self.byId, self.byInstance, self.entities, self.peers = {}, {}, {}, {}
	self.interpolation, self.pendingSpawns = {}, {}
	self.tick, self.revision, self.applying = 0, 0, false
	self.localCharacterId = nil
	self.stats = {
		replicatedEntities = 0,
		entitiesSent = 0,
		bytesEstimated = 0,
		snapshotsSent = 0,
		fullSnapshotsSent = 0,
		fullSnapshotsReceived = 0,
		staleSnapshotAcks = 0,
		outdatedSnapshots = 0,
		resyncs = 0,
		physicsCorrections = 0,
		physicsSnaps = 0,
		malformedPackets = 0,
	}
	return self
end

function ReplicationWorld:GetId(instance)
	return self.byInstance[instance]
end
function ReplicationWorld:GetInstance(id)
	return self.byId[id]
end

function ReplicationWorld:IsInScope(instance)
	if not instance or instance.CanReplicate == false then
		return false
	end
	local root = instance
	while root.Parent and root.Parent ~= self.datamodel do
		root = root.Parent
	end
	return root == self.datamodel.Workspace
		or root == self.datamodel.ReplicatedStorage
		or root == self.datamodel.Players
end

function ReplicationWorld:Register(instance, forcedId)
	if self.byInstance[instance] then
		return self.byInstance[instance]
	end
	if not self:IsInScope(instance) then
		return nil
	end
	if instance.Parent and instance.Parent ~= self.datamodel and not self.byInstance[instance.Parent] then
		self:Register(instance.Parent)
	end
	local id = forcedId or self.allocator:Allocate()
	setNetworkId(instance, id)
	self.byInstance[instance], self.byId[id] = id, instance
	self.revision += 1
	local entity = {
		id = id,
		instance = instance,
		revision = self.revision,
		propertyRevisions = {},
		createdTick = self.tick,
		lastSentTick = 0,
	}
	for _, property in ipairs(ReplicationSchema.GetProperties(instance)) do
		local propertyId = ReplicationSchema.Properties[property]
		if propertyId then
			entity.propertyRevisions[propertyId] = self.revision
		end
	end
	self.entities[id] = entity
	self.stats.replicatedEntities += 1
	return id
end

function ReplicationWorld:Unregister(instance)
	local id = self.byInstance[instance]
	if not id then
		return nil
	end
	self.byInstance[instance], self.byId[id], self.entities[id] = nil, nil, nil
	self.interpolation[id] = nil
	if self.role == "server" then
		self.allocator:Release(id)
	end
	self.stats.replicatedEntities = math.max(0, self.stats.replicatedEntities - 1)
	return id
end

function ReplicationWorld:MarkDirty(instance, property)
	if self.applying or not ReplicationSchema.IsReplicated(instance, property) then
		return
	end
	local id = self.byInstance[instance] or (self.role == "server" and self:Register(instance))
	local entity = id and self.entities[id]
	if not entity then
		return
	end
	self.revision += 1
	entity.revision = self.revision
	entity.propertyRevisions[ReplicationSchema.Properties[property]] = self.revision
end

function ReplicationWorld:BuildSpawn(instance)
	local id = self.byInstance[instance]
	if not id or instance.Destroyed or type(instance.ClassName) ~= "string" or type(instance.Name) ~= "string" then
		return nil
	end
	local parent = instance.Parent
	local parentId = parent == self.datamodel and 0 or self.byInstance[parent]
	if parent ~= self.datamodel and not parentId then
		return nil
	end
	return {
		id = id,
		class = instance.ClassName,
		name = instance.Name,
		parent = parentId,
		service = parent == self.datamodel and instance.Name or nil,
		state = ReplicationSchema.Capture(instance, self),
		ownership = self.ownership:Get(id),
	}
end

function ReplicationWorld:CaptureVersions()
	local versions = {}
	for id, entity in pairs(self.entities) do
		versions[id] = table.clone(entity.propertyRevisions)
	end
	return versions
end

function ReplicationWorld:AdvanceTick()
	self.tick = (self.tick + 1) % (2 ^ 32)
	self.history:Push(self.tick, { versions = self:CaptureVersions() })
	return self.tick
end

function ReplicationWorld:AddPeer(peerKey, player, send)
	self.peers[peerKey] = {
		key = peerKey,
		player = player,
		send = send,
		baselineTick = nil,
		known = {},
		lastInputSequence = 0,
		lastSnapshotTick = 0,
		awaitingFullAck = false,
		ackVersions = {},
		sentVersions = {},
		sentOrder = {},
	}
	return self.peers[peerKey]
end

function ReplicationWorld:RemovePeer(peerKey)
	local peer = self.peers[peerKey]
	self.peers[peerKey] = nil
	if peer and peer.player then
		self.ownership:RevokePlayer(peer.player.UserId, self.tick)
	end
	return peer
end

function ReplicationWorld:BuildFullSnapshot(peer)
	self.history:Push(self.tick, { versions = self:CaptureVersions() })
	local spawns = {}
	local stale = {}
	for id, entity in pairs(self.entities) do
		local record = self:BuildSpawn(entity.instance)
		if record then
			spawns[#spawns + 1] = record
			peer.known[id] = true
		else
			stale[#stale + 1] = entity.instance
		end
	end
	for _, instance in ipairs(stale) do
		self:Unregister(instance)
	end
	table.sort(spawns, function(a, b)
		local ai = self.byId[a.id]
		local bi = self.byId[b.id]
		return (ai and ai:GetDepth() or 0) < (bi and bi:GetDepth() or 0)
	end)
	peer.baselineTick = self.tick
	peer.awaitingFullAck = true
	peer.ackVersions = self:CaptureVersions()
	peer.sentVersions[self.tick] = peer.ackVersions
	peer.sentOrder = { self.tick }
	self.stats.fullSnapshotsSent += 1
	return { serverTick = self.tick, spawns = spawns }
end

local function estimateUpdate(update)
	local size = 12
	for _ in pairs(update.state) do
		size += 24
	end
	return size
end

function ReplicationWorld:BuildSnapshot(peer)
	if peer.awaitingFullAck then
		return nil, "awaiting full acknowledgement"
	end
	if peer.baselineTick == nil or not peer.ackVersions then
		return nil, "baseline unavailable"
	end
	local candidates = {}
	local focus = peer.player and peer.player.Character and getPosition(peer.player.Character)
	for id, entity in pairs(self.entities) do
		if peer.known[id] and not entity.instance.Destroyed then
			local baselineProperties = peer.ackVersions[id] or {}
			local state = {}
			for propertyId, revision in pairs(entity.propertyRevisions) do
				if revision > (baselineProperties[propertyId] or -1) then
					local propertyName = ReplicationSchema.Names[propertyId]
					local value = entity.instance[propertyName]
					if value ~= nil and ReplicationSchema.IsSafeValue(value) then
						state[propertyId] = ReplicationSchema.EncodeValue(value, self)
					end
				end
			end
			if next(state) then
				local position = getPosition(entity.instance)
				local distance = focus and position and (focus - position):Magnitude() or 0
				if distance <= self.config.relevancyDistance or entity.instance.ClassName == "Humanoid" then
					local age = self.tick - entity.lastSentTick
					local importance = entity.instance.ClassName == "CharacterController" and 1000
						or (entity.instance:IsA("BasePart") and 500 or 100)
					table.insert(candidates, { id = id, state = state, priority = importance + age - distance * 0.1 })
				end
			end
		end
	end
	table.sort(candidates, function(a, b)
		return a.priority > b.priority
	end)
	local updates, budget = {}, self.config.bandwidthBudget
	local deliveredVersions = {}
	for id, properties in pairs(peer.ackVersions) do deliveredVersions[id] = table.clone(properties) end
	for _, update in ipairs(candidates) do
		local size = estimateUpdate(update)
		if size <= budget then
			updates[#updates + 1] = { id = update.id, state = update.state }
			budget -= size
			self.entities[update.id].lastSentTick = self.tick
			deliveredVersions[update.id] = deliveredVersions[update.id] or {}
			for propertyId in pairs(update.state) do
				deliveredVersions[update.id][propertyId] = self.entities[update.id].propertyRevisions[propertyId]
			end
			self.stats.entitiesSent += 1
			self.stats.bytesEstimated += size
		end
	end
	self.stats.snapshotsSent += 1
	peer.lastSnapshotTick = self.tick
	peer.sentVersions[self.tick] = deliveredVersions
	table.insert(peer.sentOrder, self.tick)
	while #peer.sentOrder > self.config.snapshotHistory do
		peer.sentVersions[table.remove(peer.sentOrder, 1)] = nil
	end
	return { serverTick = self.tick, baselineTick = peer.baselineTick, updates = updates }
end

function ReplicationWorld:Acknowledge(peer, tick)
	if not validTick(tick) then
		return false
	end
	local versions = peer.sentVersions[tick]
	if versions then
		local acknowledgesFull = peer.awaitingFullAck and tick == peer.baselineTick
		local advancesBaseline = peer.baselineTick == nil or Sequence.IsNewer(tick, peer.baselineTick)
		if acknowledgesFull or advancesBaseline then
			peer.baselineTick = tick
			peer.ackVersions = versions
			peer.awaitingFullAck = false
		end
		return true
	end
	return false
end

function ReplicationWorld:ApplySpawn(record)
	if type(record) ~= "table"
		or type(record.id) ~= "number" or record.id % 1 ~= 0 or record.id <= 0
		or type(record.class) ~= "string" or #record.class < 1 or #record.class > 64
		or type(record.name) ~= "string" or #record.name > 255
		or type(record.parent) ~= "number" or record.parent % 1 ~= 0
		or type(record.state) ~= "table" or not ReplicationSchema.IsSafeValue(record.state)
	then
		return nil, "invalid spawn"
	end
	local instance = self.byId[record.id]
	local wasKnown = instance ~= nil
	if instance and instance.ClassName ~= record.class then
		return nil, "network ID class mismatch"
	end
	if record.service then
		instance = self.datamodel:GetService(record.service)
	end
	local parent = record.parent == 0 and self.datamodel or self.byId[record.parent]
	if not instance and not parent then
		return nil, "parent unavailable"
	end
	local previousReplicationState = rawget(self.datamodel, "_ApplyingReplicationHierarchy")
	rawset(self.datamodel, "_ApplyingReplicationHierarchy", true)
	if not instance and parent then
		local candidate = parent:FindFirstChild(record.name)
		if candidate and candidate.ClassName == record.class and candidate.NetworkId == nil then
			instance = candidate
		end
	end
	if not instance then
		local Registry = require("@InstanceRegistry")
		local ok, created = pcall(Registry.new, record.class, self.renderer, self.datamodel, true)
		if not ok then
			rawset(self.datamodel, "_ApplyingReplicationHierarchy", previousReplicationState)
			return nil, "class creation failed"
		end
		instance = created
	end
	setNetworkId(instance, record.id)
	self.byId[record.id], self.byInstance[instance] = instance, record.id
	self.entities[record.id] = self.entities[record.id]
		or { id = record.id, instance = instance, propertyRevisions = {} }
	self.applying = true
	local applied = ReplicationSchema.Apply(instance, record.state, self, Enum)
	if parent and instance.Parent ~= parent then
		instance.Parent = parent
	end
	rawset(self.datamodel, "_ApplyingReplicationHierarchy", previousReplicationState)
	self.applying = false
	if not applied then
		self.stats.malformedPackets += 1
	end
	if record.ownership then
		self.ownership.records[record.id] = record.ownership
	end
	if not wasKnown then
		self.stats.replicatedEntities = self.stats.replicatedEntities + 1
	end
	return instance
end

function ReplicationWorld:ApplyFullSnapshot(payload)
	if type(payload) ~= "table" or not validTick(payload.serverTick)
		or type(payload.spawns) ~= "table" or #payload.spawns > 100000
	then
		return false
	end
	self.tick = payload.serverTick
	local pending = table.clone(payload.spawns)
	local lastReason = nil
	for _ = 1, #pending + 1 do
		local progressed = false
		for index = #pending, 1, -1 do
			local instance, reason = self:ApplySpawn(pending[index])
			if instance then
				table.remove(pending, index)
				progressed = true
			else
				lastReason = reason
			end
		end
		if not progressed then
			break
		end
	end
	if #pending ~= 0 then
		local record = pending[1]
		return false, `{#pending} spawn(s) pending; {record and record.class or "?"} "{record and record.name or "?"}": {lastReason or "unknown error"}`
	end
	-- References can point to deeper objects (for example a constraint under a
	-- model referencing attachments under sibling parts). Apply state again once
	-- every network ID exists so late-join snapshots restore those links.
	self.applying = true
	for _, record in ipairs(payload.spawns) do
		local instance = self.byId[record.id]
		if instance then
			ReplicationSchema.Apply(instance, record.state, self, Enum)
		end
	end
	self.applying = false
	local incoming = {}
	for _, record in ipairs(payload.spawns) do
		incoming[record.id] = true
	end
	local stale = {}
	for id, instance in pairs(self.byId) do
		if not incoming[id] then
			table.insert(stale, instance)
		end
	end
	for _, instance in ipairs(stale) do
		self:Unregister(instance)
		if instance.Parent ~= self.datamodel then
			instance:Destroy()
		end
	end
	return true
end

function ReplicationWorld:ApplySnapshot(payload)
	if type(payload) ~= "table" or not validTick(payload.serverTick)
		or not validTick(payload.baselineTick) or type(payload.updates) ~= "table" or #payload.updates > 100000
	then
		return false
	end
	if not Sequence.IsNewer(payload.serverTick, self.tick) then
		self.stats.outdatedSnapshots += 1
		return false
	end
	self.tick = payload.serverTick
	for _, update in ipairs(payload.updates) do
		if type(update) ~= "table" or type(update.id) ~= "number"
			or type(update.state) ~= "table" or not ReplicationSchema.IsSafeValue(update.state)
		then
			self.stats.malformedPackets += 1
			continue
		end
		local instance = self.byId[update.id]
		if instance then
			local state = table.clone(update.state)
			local cframeId = ReplicationSchema.Properties.CFrame
			local cframe = state[cframeId]
			if self.onAuthoritativeState and self.onAuthoritativeState(update.id, state, payload) == true then
				cframe = nil
				state[cframeId] = nil
			end
			local localRoot = self.localCharacterId and self.byId[self.localCharacterId]
			local localCharacter = localRoot and localRoot.Parent
			if cframe and localCharacter and instance ~= localRoot and instance:IsDescendantOf(localCharacter) then
				cframe = nil
				state[cframeId] = nil
			end
			if cframe and update.id ~= self.localCharacterId then
				local decoded = ReplicationSchema.DecodeValue(cframe, self, Enum)
				local bufferObject = self.interpolation[update.id]
				if not bufferObject then
					bufferObject =
						InterpolationBuffer.new({ maxExtrapolationTicks = self.config.maxExtrapolationTicks })
					self.interpolation[update.id] = bufferObject
				end
				local reset = instance.CFrame
					and (instance.CFrame.Position - decoded.Position):Magnitude() >= self.config.teleportThreshold
				bufferObject:Push(payload.serverTick, { CFrame = decoded }, reset)
				state[cframeId] = nil
			end
			self.applying = true
			local applied = ReplicationSchema.Apply(instance, state, self, Enum)
			self.applying = false
			if not applied then
				self.stats.malformedPackets += 1
			end
		end
	end
	return true
end

function ReplicationWorld:RenderInterpolated()
	local renderTick = self.tick - self.config.interpolationDelayTicks
	local total = 0
	local writes = 0
	local unchanged = 0
	for id, bufferObject in pairs(self.interpolation) do
		local instance = self.byId[id]
		local state = instance and bufferObject:Sample(renderTick)
		if state and state.CFrame then
			local current = instance.CFrame
			if not current or not current:IsSameTransform(state.CFrame, 1e-4) then
				instance.CFrame = state.CFrame
				writes += 1
			else
				-- Interpolation buffers retain their last sample. Do not feed that same
				-- transform back through Instance.Changed and the remote Jolt proxy on
				-- every render frame after an object has stopped moving.
				unchanged += 1
			end
		end
		total += bufferObject:Size()
	end
	self.stats.interpolationBufferSize = total
	local perfStats = self.renderer and self.renderer.PerfStats
	if perfStats then
		perfStats.replication_interpolation_writes = writes
		perfStats.replication_interpolation_unchanged = unchanged
		perfStats.replication_interpolation_samples = total
	end
end

function ReplicationWorld:AssignOwnership(instance, playerId, player)
	local id = self.byInstance[instance]
	if not id then
		return nil
	end
	local record = self.ownership:SetOwner(id, playerId, self.tick)
	instance.NetworkOwnerType = playerId and 1 or 0
	instance.NetworkOwner = player
	NetworkOwnership.NotifyOwnershipChanged(instance)
	return record
end

function ReplicationWorld:ApplyOwnedPhysics(peer, payload)
	local entity = type(payload) == "table" and self.entities[payload.id]
	local playerId = peer.player and peer.player.UserId
	if not entity or not self.ownership:IsOwner(payload.id, playerId, payload.ownershipVersion) then
		return false
	end
	local state = payload.state
	if type(state) ~= "table" or not ReplicationSchema.IsSafeValue(state) then
		return false
	end
	local cframe = ReplicationSchema.DecodeValue(state[ReplicationSchema.Properties.CFrame], self, Enum)
	local velocity =
		ReplicationSchema.DecodeValue(state[ReplicationSchema.Properties.AssemblyLinearVelocity], self, Enum)
	local angularVelocity =
		ReplicationSchema.DecodeValue(state[ReplicationSchema.Properties.AssemblyAngularVelocity], self, Enum)
	if
		not cframe
		or not velocity
		or not angularVelocity
		or velocity:Magnitude() > self.config.maxOwnedSpeed
		or angularVelocity:Magnitude() > self.config.maxOwnedSpeed
	then
		return false
	end
	local current = getPosition(entity.instance)
	if current and (current - cframe.Position):Magnitude() > self.config.maxOwnedError then
		return false
	end
	self.applying = true
	entity.instance.CFrame = cframe
	entity.instance.AssemblyLinearVelocity = velocity
	entity.instance.AssemblyAngularVelocity = angularVelocity
	self.applying = false
	self:MarkDirty(entity.instance, "CFrame")
	self:MarkDirty(entity.instance, "AssemblyLinearVelocity")
	self:MarkDirty(entity.instance, "AssemblyAngularVelocity")
	return true
end

function ReplicationWorld:GetStats()
	local result = table.clone(self.stats)
	result.serverTick = self.tick
	return result
end

return ReplicationWorld
