local Protocol = require("./Protocol")
local ReplicationWorld = require("./ReplicationWorld")
local ReplicationSchema = require("./ReplicationSchema")
local CharacterReplicator = require("./CharacterReplicator")
local CollaboratorCameraGizmos = require("./CollaboratorCameraGizmos")
local CFrame = require("@CFrame")

local ClientReplicator = {}
ClientReplicator.__index = ClientReplicator

function ClientReplicator.new(transport, datamodel, renderer, options)
	local self = setmetatable({}, ClientReplicator)
	self.transport, self.datamodel, self.renderer = transport, datamodel, renderer
	self.world = ReplicationWorld.new("client", datamodel, renderer, options)
	self.character = CharacterReplicator.new({
		role = "client",
		tick = function()
			return self.datamodel:GetService("RunService"):GetSimulationTick()
		end,
		send = function(command)
			return self:Send(Protocol.Kinds.InputCommand, command)
		end,
	})
	self.events, self.connections, self.pendingSpawns = {}, {}, {}
	self.options = options or {}
	self.studioRequestId, self.studioRequests, self.collaborators = 0, {}, {}
	self.cameraGizmos = if self.options.studio then CollaboratorCameraGizmos.new(renderer) else nil
	self.running, self.connected, self.playerId = false, false, nil
	self.rtt, self.jitter, self.lastPing = 0, 0, 0
	self.ownedPhysicsCache = {}
	self.ownedPhysicsPacketsSent, self.ownedPhysicsPacketsSkipped = 0, 0
	self.lastResyncRequest = -math.huge
	self.boundCharacter = nil
	return self
end

function ClientReplicator:SendStudioEdit(edit, callback)
	if not self.options.studio or not self.connected then
		return false, "not connected to a studio collaboration session"
	end
	self.studioRequestId += 1
	edit.requestId = self.studioRequestId
	if callback then
		self.studioRequests[edit.requestId] = callback
	end
	return self:Send(Protocol.Kinds.StudioEdit, edit, true)
end

function ClientReplicator:SetStudioProperty(instance, property, value)
	local id = self.world:GetId(instance)
	if not id or not ReplicationSchema.IsReplicated(instance, property) then
		return false, "instance or property is not replicated"
	end
	return self:SendStudioEdit({
		op = "set",
		id = id,
		property = property,
		value = ReplicationSchema.EncodeValue(value, self.world),
	})
end

function ClientReplicator:CreateStudioInstance(className, parent, state, callback)
	local parentId = self.world:GetId(parent)
	if not parentId then
		return false, "parent is not replicated"
	end
	return self:SendStudioEdit({ op = "create", class = className, parent = parentId, state = state or {} }, callback)
end

function ClientReplicator:DeleteStudioInstance(instance, callback)
	local id = self.world:GetId(instance)
	if not id then
		return false, "instance is not replicated"
	end
	return self:SendStudioEdit({ op = "delete", id = id }, callback)
end

function ClientReplicator:ReparentStudioInstance(instance, parent, callback)
	local id, parentId = self.world:GetId(instance), self.world:GetId(parent)
	if not id or not parentId then
		return false, "instance or parent is not replicated"
	end
	return self:SendStudioEdit({ op = "reparent", id = id, parent = parentId }, callback)
end

function ClientReplicator:EnableStudioCollaboration()
	if not self.options.studio or self.studioEditingEnabled then
		return
	end
	self.studioEditingEnabled = true

	local function applying()
		return self.world.applying or rawget(self.datamodel, "_ApplyingReplicationHierarchy") == true
	end
	local function canReplicate(instance)
		local current = instance
		while current and current ~= self.datamodel do
			if current.CanReplicate == false then
				return false
			end
			current = current.Parent
		end
		return true
	end

	table.insert(self.connections, self.datamodel.DescendantChanged:Connect(function(instance, property)
		if not self.connected or applying() or not canReplicate(instance) then
			return
		end
		local id = self.world:GetId(instance)
		if id and ReplicationSchema.IsReplicated(instance, property) then
			self:SendStudioEdit({
				op = "set",
				id = id,
				property = property,
				value = ReplicationSchema.EncodeValue(instance[property], self.world),
			})
		end
	end))

	table.insert(self.connections, self.datamodel.DescendantAdded:Connect(function(instance)
		if not self.connected or applying() or not canReplicate(instance) then
			return
		end
		local parent = instance.Parent
		local parentId = parent and self.world:GetId(parent)
		if not parentId then
			return
		end
		local id = self.world:GetId(instance)
		if id then
			self:ReparentStudioInstance(instance, parent)
			return
		end
		self:CreateStudioInstance(instance.ClassName, parent, ReplicationSchema.Capture(instance, self.world), function(result)
			if not result.ok and instance.Parent then
				instance:Destroy()
			end
		end)
	end))
end

function ClientReplicator:Send(kind, payload, reliableOverride)
	local reliable = reliableOverride
	if reliable == nil then
		reliable = Protocol.IsReliable(kind)
	end
	return self.transport:Send(Protocol.Packet(kind, payload), reliable)
end

local function assignPlayerCharacter(player, character)
	if not player or player.Character == character then
		return
	end
	local previous = player.Character
	if previous and player.CharacterRemoving then
		player.CharacterRemoving:Fire(previous)
	end
	player.Character = character
	if character and player.CharacterAdded then
		player.CharacterAdded:Fire(character)
	end
end

local RIG_PART_NAMES = {
	HumanoidRootPart = true,
	Torso = true,
	Neck = true,
	Head = true,
	["Left Shoulder"] = true,
	["Left Arm"] = true,
	["Left Hand"] = true,
	["Right Shoulder"] = true,
	["Right Arm"] = true,
	["Right Hand"] = true,
	["Left Hip"] = true,
	["Left Leg"] = true,
	["Left Foot"] = true,
	["Right Hip"] = true,
	["Right Leg"] = true,
	["Right Foot"] = true,
}

local RIG_OFFSETS = {
	Torso = CFrame.new(0, 0, 0),
	Neck = CFrame.new(0, 1.32, 0),
	Head = CFrame.new(0, 2.02, 0),
}

local function removeUntrackedRigDuplicates(character, world)
	local authoritative = {}
	for _, child in ipairs(character:GetChildren()) do
		if RIG_PART_NAMES[child.Name] and child.BaseClass == "BasePart" and world:GetId(child) then
			authoritative[child.Name] = child
		end
	end
	for _, child in ipairs(character:GetChildren()) do
		if RIG_PART_NAMES[child.Name]
			and child.BaseClass == "BasePart"
			and authoritative[child.Name]
			and child ~= authoritative[child.Name]
			and not world:GetId(child)
		then
			child:Destroy()
		end
	end
end

function ClientReplicator:ConfigureCharacters()
	local workspace = self.datamodel:GetService("Workspace")
	local players = self.datamodel:GetService("Players")
	local localRoot = self.world.localCharacterId and self.world:GetInstance(self.world.localCharacterId)
	local localCharacter = localRoot and localRoot.Parent
	local charactersByName = {}
	local configurations = {}

	for _, candidate in ipairs(workspace:GetChildren()) do
		if candidate.ClassName ~= "Model" then
			continue
		end
		local humanoid = candidate:FindFirstChildOfClass("Humanoid")
		local root = candidate:FindFirstChild("HumanoidRootPart") or candidate.PrimaryPart
		if not humanoid or not root then
			continue
		end
		removeUntrackedRigDuplicates(candidate, self.world)

		if candidate.PrimaryPart ~= root then candidate.PrimaryPart = root end
		if humanoid.Character ~= candidate then humanoid.Character = candidate end
		if humanoid.RootPart ~= root then humanoid.RootPart = root end
		charactersByName[candidate.Name] = candidate
		configurations[#configurations + 1] = { character = candidate, root = root }
	end
	self.characterConfigurations = configurations

	local localPlayer = players.LocalPlayer
	if not localCharacter and localPlayer then
		local current = localPlayer.Character
		if not current or current.Parent ~= workspace then
			current = charactersByName[localPlayer.Name]
		end
		localCharacter = current
		localRoot = current and (current:FindFirstChild("HumanoidRootPart") or current.PrimaryPart)
		local rootId = localRoot and self.world:GetId(localRoot)
		if rootId then
			self.world.localCharacterId = rootId
		end
	end

	for _, configuration in ipairs(configurations) do
		local candidate, root = configuration.character, configuration.root
		local controller = candidate:FindFirstChildOfClass("CharacterController")
		if controller then
			if controller.Character ~= candidate then controller.Character = candidate end
			if controller.RootPart ~= root then controller.RootPart = root end
			local shouldSimulate = candidate == localCharacter
			if controller.Enabled ~= shouldSimulate then controller.Enabled = shouldSimulate end
			local motor = controller:GetMotor()
			if motor then
				if motor.RootPart ~= root then motor.RootPart = root end
				if motor.Enabled ~= shouldSimulate then motor.Enabled = shouldSimulate end
			end
		end
	end

	for _, player in ipairs(players:GetChildren()) do
		if player.ClassName == "Player" then
			local current = player.Character
			if not current or current.Parent ~= workspace then
				current = charactersByName[player.Name]
			end
			assignPlayerCharacter(player, current)
		end
	end
	if localPlayer then
		local localUserId = self.playerId or localPlayer.UserId
		if localPlayer.UserId ~= localUserId then localPlayer.UserId = localUserId end
		assignPlayerCharacter(localPlayer, localCharacter or charactersByName[localPlayer.Name])
	end
	return localCharacter ~= nil
end

function ClientReplicator:PoseRemoteCharacters()
	for _, configuration in ipairs(self.characterConfigurations or {}) do
		local character, root = configuration.character, configuration.root
		if character ~= self.boundCharacter and character.Parent and root and root.CFrame then
			-- The server snapshots animate remote limbs. Torso and head are rigid,
			-- so derive them from the interpolated root to keep facing perfectly in
			-- sync instead of waiting for separate part snapshots.
			for _, partName in ipairs({ "Torso", "Neck", "Head" }) do
				local offset = RIG_OFFSETS[partName]
				local part = character:FindFirstChild(partName)
				if part and part.CFrame then
					local posedCFrame = root.CFrame * offset
					if not part.CFrame:IsSameTransform(posedCFrame, 1e-4) then
						part.CFrame = posedCFrame
					end
				end
			end
		end
	end
end

function ClientReplicator:BindLocalCharacter()
	self:ConfigureCharacters()
	local root = self.world.localCharacterId and self.world:GetInstance(self.world.localCharacterId)
	local character = root and root.Parent
	local controller = character and character:FindFirstChildOfClass("CharacterController")
	if not controller then
		return false
	end
	self.character:BindLocalController(controller)
	local players = self.datamodel:GetService("Players")
	if players.LocalPlayer then
		players.LocalPlayer.UserId = self.playerId
		players.LocalPlayer.Character = character
	end
	if self.boundCharacter ~= character then
		self.boundCharacter = character
		print(`[CharacterReplication][Client] Bound local character "{character.Name}" (root {self.world.localCharacterId})`)
	end
	return true
end

function ClientReplicator:RequestResync(reason)
	local now = os.clock()
	if now - self.lastResyncRequest < 1 then
		return false
	end
	self.lastResyncRequest = now
	self.world.stats.resyncs += 1
	return self:Send(Protocol.Kinds.ResyncRequest, { reason = reason })
end

function ClientReplicator:ApplyPendingSpawns()
	for _ = 1, #self.pendingSpawns + 1 do
		local progressed = false
		for index = #self.pendingSpawns, 1, -1 do
			if self.world:ApplySpawn(self.pendingSpawns[index]) then
				table.remove(self.pendingSpawns, index)
				progressed = true
			end
		end
		if not progressed then
			break
		end
	end
	if #self.pendingSpawns > 0 then
		self:RequestResync("spawn parent missing")
	end
	self:ConfigureCharacters()
end

function ClientReplicator:HandleAuthoritativeState(id, state, snapshot)
	local ownership = self.world.ownership:Get(id)
	if ownership and ownership.owner == self.playerId and id ~= self.world.localCharacterId then
		-- The server echoes validated owner state to every peer. Applying that
		-- delayed echo back to the owning client fights its live Jolt body every
		-- render frame, causing jitter and a large Changed/proxy-sync feedback
		-- loop. Other clients still interpolate the same authoritative state.
		state[ReplicationSchema.Properties.CFrame] = nil
		state[ReplicationSchema.Properties.AssemblyLinearVelocity] = nil
		state[ReplicationSchema.Properties.AssemblyAngularVelocity] = nil
		return true
	end
	if id ~= self.world.localCharacterId then
		return false
	end
	local encoded = state[ReplicationSchema.Properties.CFrame]
	if not encoded then
		return false
	end
	local cframe = ReplicationSchema.DecodeValue(encoded, self.world)
	local velocity =
		ReplicationSchema.DecodeValue(state[ReplicationSchema.Properties.AssemblyLinearVelocity], self.world)
	local runService = self.datamodel:GetService("RunService")
	self.character:Reconcile(cframe, velocity, snapshot.lastProcessedInputSequence or 0, runService:GetSimulationDT())
	return true
end

function ClientReplicator:OnMessage(_, packet)
	local valid = Protocol.Validate(packet)
	if not valid then
		self.world.stats.malformedPackets += 1
		return
	end
	local kind, payload = packet.kind, packet.payload
	if kind == Protocol.Kinds.HandshakeAccepted then
		self.connected, self.playerId = true, payload.playerId
		self.world.localCharacterId = payload.characterId
		self.world.tick = payload.serverTick or 0
		print(`[Replication][Client] Handshake accepted as {tostring(payload.playerName)} at tick {self.world.tick}`)
	elseif kind == Protocol.Kinds.HandshakeRejected then
		warn("[Replication] Connection rejected: " .. tostring(payload.reason))
		self.connected = false
	elseif kind == Protocol.Kinds.FullSnapshot then
		local applied, reason = self.world:ApplyFullSnapshot(payload)
		if applied then
			self.world.stats.fullSnapshotsReceived += 1
			self:BindLocalCharacter()
			self:Send(Protocol.Kinds.SnapshotAck, { serverTick = payload.serverTick })
			print(`[Replication][Client] Applied full snapshot with {#payload.spawns} entities`)
		else
			warn("[Replication][Client] Full snapshot rejected: " .. tostring(reason))
			self:RequestResync("full snapshot incomplete")
		end
	elseif kind == Protocol.Kinds.Spawn then
		local spawned, reason = self.world:ApplySpawn(payload)
		if not spawned then
			warn(`[Replication][Client] Queued spawn {tostring(payload.class)} "{tostring(payload.name)}": {tostring(reason)}`)
			table.insert(self.pendingSpawns, payload)
		end
		self:ApplyPendingSpawns()
		self:BindLocalCharacter()
	elseif kind == Protocol.Kinds.Despawn then
		local instance = self.world:GetInstance(payload.id)
		if instance then
			self.world:Unregister(instance)
			if instance.Parent ~= self.datamodel then
				instance:Destroy()
			end
		end
		self:ConfigureCharacters()
	elseif kind == Protocol.Kinds.Snapshot then
		if self.world:ApplySnapshot(payload) then
			self:ConfigureCharacters()
			self:Send(Protocol.Kinds.SnapshotAck, { serverTick = payload.serverTick })
		end
	elseif kind == Protocol.Kinds.OwnershipChanged then
		if type(payload.id) == "number" and type(payload.record) == "table" then
			self.world.ownership.records[payload.id] = payload.record
			local instance = self.world:GetInstance(payload.id)
			if instance then
				local owner = nil
				if payload.record.owner ~= nil then
					local players = self.datamodel:GetService("Players")
					for _, player in ipairs(players and players:GetPlayers() or {}) do
						if player.UserId == payload.record.owner then
							owner = player
							break
						end
					end
				end
				instance.NetworkOwner = owner
				instance.NetworkOwnerType = payload.record.owner and 1 or 0
				if payload.record.owner == self.playerId then
					-- Discard snapshots queued before the ownership grant. Otherwise
					-- RenderInterpolated can keep rewinding the newly dynamic body.
					self.world.interpolation[payload.id] = nil
				end
				self.world.ownership.NotifyOwnershipChanged(instance)
			end
		end
	elseif kind == Protocol.Kinds.Pong then
		local sample = math.max(0, os.clock() - (payload.clientTime or os.clock()))
		self.jitter = self.jitter * 0.8 + math.abs(sample - self.rtt) * 0.2
		self.rtt = self.rtt * 0.8 + sample * 0.2
	elseif kind == Protocol.Kinds.StudioEditResult then
		local callback = self.studioRequests[payload.requestId]
		self.studioRequests[payload.requestId] = nil
		if callback then
			task.spawn(callback, payload)
		end
	elseif kind == Protocol.Kinds.StudioPresence and type(payload.collaborators) == "table" then
		self.collaborators = payload.collaborators
	elseif kind == Protocol.Kinds.StudioCamera and type(payload.id) == "string" then
		local decoded, cframe = pcall(ReplicationSchema.DecodeValue, payload.cframe, self.world)
		if decoded and self.cameraGizmos then
			self.cameraGizmos:Update(payload.id, tostring(payload.name or "Collaborator"), cframe)
		end
	elseif kind == Protocol.Kinds.Event and type(payload.name) == "string" then
		local callbacks = self.events[payload.name]
		if callbacks then
			for _, callback in ipairs(callbacks) do
				task.spawn(callback, payload.data)
			end
		end
	end
end

function ClientReplicator:SendOwnedPhysics()
	local now = os.clock()
	for id, record in pairs(self.world.ownership.records) do
		if record.owner == self.playerId then
			local instance = self.world:GetInstance(id)
			if instance and instance:IsA("BasePart") then
				local cframe = instance.CFrame
				local linear = instance.AssemblyLinearVelocity
				local angular = instance.AssemblyAngularVelocity
				local previous = self.ownedPhysicsCache[id]
				local changed = not previous
					or previous.version ~= record.version
					or not cframe:IsSameTransform(previous.cframe, 1e-3)
					or linear:DistanceSquared(previous.linear) > 1e-4
					or angular:DistanceSquared(previous.angular) > 1e-4
					or now - previous.sentAt >= 1
				if not changed then
					self.ownedPhysicsPacketsSkipped += 1
					continue
				end

				local sent = self:Send(Protocol.Kinds.OwnedPhysicsState, {
					id = id,
					ownershipVersion = record.version,
					state = {
						[ReplicationSchema.Properties.CFrame] = ReplicationSchema.EncodeValue(
							cframe,
							self.world
						),
						[ReplicationSchema.Properties.AssemblyLinearVelocity] = ReplicationSchema.EncodeValue(
							linear,
							self.world
						),
						[ReplicationSchema.Properties.AssemblyAngularVelocity] = ReplicationSchema.EncodeValue(
							angular,
							self.world
						),
					},
				})
				if sent ~= false then
					self.ownedPhysicsCache[id] = {
						cframe = cframe,
						linear = linear,
						angular = angular,
						version = record.version,
						sentAt = now,
					}
					self.ownedPhysicsPacketsSent += 1
				end
			end
		end
	end
end

function ClientReplicator:Start(address, port, arguments)
	if self.running then
		return self
	end
	self.running = true
	self.world.onAuthoritativeState = function(id, state, snapshot)
		return self:HandleAuthoritativeState(id, state, snapshot)
	end
	self.transport:Init(address, tonumber(port) or 1234)
	self.transport:OnRecieve(function(remote, packet)
		self:OnMessage(remote, packet)
	end)
	self.transport:Connect(arguments)
	self:EnableStudioCollaboration()
	local runService = self.datamodel:GetService("RunService")
	table.insert(
		self.connections,
		runService.RenderStepped:Connect(function()
			self.world:RenderInterpolated()
			self:PoseRemoteCharacters()
		end)
	)
	task.spawn(function()
		local lastCamera
		local interval = 1 / 30
		while self.running do
			task.wait(interval)
			if self.connected then
				self.character:SendInput()
				self:SendOwnedPhysics()
				if self.options.studio then
					local workspace = self.datamodel:GetService("Workspace")
					local camera = workspace
						and (workspace.CurrentCamera or workspace:FindFirstChildOfClass("Camera"))
					local cframe = camera and camera.CFrame
					if cframe and (not lastCamera or not cframe:IsSameTransform(lastCamera, 1e-3)) then
						self:Send(Protocol.Kinds.StudioCamera, {
							cframe = ReplicationSchema.EncodeValue(cframe, self.world),
						}, false)
						lastCamera = cframe
					end
				end
			end
		end
	end)
	task.spawn(function()
		while self.running do
			task.wait(1)
			if self.connected then
				self.lastPing += 1
				self:Send(Protocol.Kinds.Ping, { nonce = self.lastPing, clientTime = os.clock() }, false)
			end
		end
	end)
	return self
end

function ClientReplicator:OnEvent(name, callback)
	self.events[name] = self.events[name] or {}
	table.insert(self.events[name], callback)
end

function ClientReplicator:SendEvent(name, data, reliable)
	return self:Send(Protocol.Kinds.Event, { name = name, data = data }, reliable ~= false)
end

function ClientReplicator:GetStats()
	local stats = self.world:GetStats()
	stats.rtt, stats.jitter = self.rtt, self.jitter
	for key, value in pairs(self.character:GetStats()) do
		stats[key] = value
	end
	stats.ownedPhysicsPacketsSent = self.ownedPhysicsPacketsSent
	stats.ownedPhysicsPacketsSkipped = self.ownedPhysicsPacketsSkipped
	if self.transport.GetStats then
		for key, value in pairs(self.transport:GetStats()) do stats[key] = value end
	end
	return stats
end

function ClientReplicator:GetCollaborators()
	return table.clone(self.collaborators)
end

function ClientReplicator:Stop()
	self.running, self.connected = false, false
	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	table.clear(self.connections)
	if self.cameraGizmos then
		self.cameraGizmos:Destroy()
		self.cameraGizmos = nil
	end
	self.transport:Disconnect()
end

return ClientReplicator
