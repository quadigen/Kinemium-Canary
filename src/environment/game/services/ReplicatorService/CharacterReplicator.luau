local Sequence = require("./Sequence")
local Vector3 = require("@Vector3")

local CharacterReplicator = {}
CharacterReplicator.__index = CharacterReplicator

local function validDirection(direction)
	return type(direction) == "table"
		and type(direction.moveX) == "number" and type(direction.moveZ) == "number"
		and direction.moveX == direction.moveX and direction.moveZ == direction.moveZ
		and math.abs(direction.moveX) <= 1.05 and math.abs(direction.moveZ) <= 1.05
end

function CharacterReplicator.new(options)
	options = options or {}
	return setmetatable({
		role = options.role, send = options.send, tick = options.tick,
		history = {}, nextSequence = 0, lastReceived = {}, lastProcessed = {},
		maxHistory = options.maxHistory or 128, correctionThreshold = options.correctionThreshold or 0.75,
		correctionFactor = options.correctionFactor or 0.15,
		teleportThreshold = options.teleportThreshold or 8, correctionCount = 0, correctionDistance = 0,
		pendingDirection = Vector3.new(0, 0, 0), pendingJump = false, pendingSprint = false,
		connections = {}, controller = nil, replaying = false, inputsSent = 0, inputsReceived = 0,
	}, CharacterReplicator)
end

function CharacterReplicator:BindLocalController(controller)
	for _, connection in ipairs(self.connections) do connection:Disconnect() end
	table.clear(self.connections)
	self.controller = controller
	if not controller then return end
	if controller.MovementRequested then
		table.insert(self.connections, controller.MovementRequested:Connect(function(direction)
			if not self.replaying then self.pendingDirection = direction end
		end))
	end
	if controller.JumpRequested then
		table.insert(self.connections, controller.JumpRequested:Connect(function()
			if not self.replaying then self.pendingJump = true end
		end))
	end
	if controller.SprintingChanged then
		table.insert(self.connections, controller.SprintingChanged:Connect(function(sprinting)
			if not self.replaying then self.pendingSprint = sprinting == true end
		end))
	end
end

function CharacterReplicator:BuildInput()
	self.nextSequence = Sequence.Next(self.nextSequence)
	local root = self.controller and self.controller.RootPart
	local command = {
		sequence = self.nextSequence, tick = self.tick(), moveX = self.pendingDirection.X,
		moveZ = self.pendingDirection.Z, jump = self.pendingJump, sprint = self.pendingSprint,
	}
	self.pendingJump = false
	self.history[#self.history + 1] = {
		command = command,
		position = root and root.CFrame and root.CFrame.Position or nil,
	}
	while #self.history > self.maxHistory do table.remove(self.history, 1) end
	return command
end

function CharacterReplicator:SendInput()
	if not self.controller or not self.send then return false end
	local sent = self.send(self:BuildInput())
	if sent then self.inputsSent += 1 end
	return sent
end

function CharacterReplicator:ProcessServerInput(peerId, command, controller)
	if type(command) ~= "table"
		or type(command.sequence) ~= "number"
		or command.sequence ~= command.sequence
		or command.sequence % 1 ~= 0
		or command.sequence < 0
		or command.sequence >= 2 ^ 32
		or (command.tick ~= nil and (type(command.tick) ~= "number" or command.tick ~= command.tick))
		or (command.sprint ~= nil and type(command.sprint) ~= "boolean")
		or not validDirection(command)
	then
		return false, "invalid input"
	end
	local previous = self.lastReceived[peerId]
	if previous ~= nil and not Sequence.IsNewer(command.sequence, previous) then
		return false, "duplicate or stale input"
	end
	self.lastReceived[peerId] = Sequence.Normalize(command.sequence)
	self.inputsReceived += 1
	local direction = Vector3.new(command.moveX, 0, command.moveZ)
	if direction:Magnitude() > 1 then direction = direction:Unit() end
	controller:Move(direction)
	controller:SetSprinting(command.sprint == true)
	if command.jump == true then controller:Jump() end
	self.lastProcessed[peerId] = Sequence.Normalize(command.sequence)
	return true
end

function CharacterReplicator:GetLastProcessed(peerId)
	return self.lastProcessed[peerId] or 0
end

function CharacterReplicator:RemovePeer(peerId)
	if peerId == nil then
		return false
	end
	local existed = self.lastProcessed[peerId] ~= nil or self.lastReceived[peerId] ~= nil
	self.lastProcessed[peerId] = nil
	self.lastReceived[peerId] = nil
	return existed
end

function CharacterReplicator:Reconcile(authoritativeCFrame, velocity, acknowledgedSequence, _simulationDt)
	local controller = self.controller
	local root = controller and controller.RootPart
	if not root or not authoritativeCFrame then return false end
	local acknowledgedPrediction = nil
	for _, entry in ipairs(self.history) do
		if Sequence.IsNewerOrEqual(acknowledgedSequence, entry.command.sequence) and entry.position then
			-- History is chronological, so the last matching entry is the prediction
			-- made for the exact newest input represented by this server snapshot.
			acknowledgedPrediction = entry.position
		end
	end
	for index = #self.history, 1, -1 do
		if Sequence.IsNewerOrEqual(acknowledgedSequence, self.history[index].command.sequence) then
			table.remove(self.history, index)
		end
	end
	-- A repeated/late snapshot may acknowledge history we already discarded.
	-- Comparing that old server position with the current prediction is precisely
	-- what causes the visible one-frame rubber-band.
	if not acknowledgedPrediction then return false end
	local positionError = authoritativeCFrame.Position - acknowledgedPrediction
	local errorDistance = positionError:Magnitude()
	if errorDistance <= self.correctionThreshold then return false end
	self.correctionCount += 1
	self.correctionDistance += errorDistance
	local correctionScale = if errorDistance >= self.teleportThreshold then 1 else self.correctionFactor
	local correctedCFrame = root.CFrame:WithPosition(root.CFrame.Position + positionError * correctionScale)
	local motor = controller:GetMotor()
	if motor and motor.Reset then
		-- Reset translates every body part by the correction delta. Assigning the
		-- root first would lose that delta and leave the limbs behind.
		motor:Reset(correctedCFrame.Position)
		root.CFrame = correctedCFrame
	else
		local offset = correctedCFrame.Position - root.CFrame.Position
		root.CFrame = correctedCFrame
		local character = root.Parent
		if character and offset:Magnitude() > 0 then
			for _, descendant in ipairs(character:GetDescendants()) do
				if descendant ~= root and descendant.BaseClass == "BasePart" and descendant.CFrame then
					descendant.CFrame = descendant.CFrame:WithPosition(descendant.CFrame.Position + offset)
				end
			end
		end
	end
	if motor and velocity then motor.Velocity = velocity end
	return true, errorDistance
end

function CharacterReplicator:GetStats()
	return {
		pendingInputs = #self.history, reconciliations = self.correctionCount,
		correctionDistance = self.correctionDistance, inputsSent = self.inputsSent,
		inputsReceived = self.inputsReceived,
	}
end

return CharacterReplicator
