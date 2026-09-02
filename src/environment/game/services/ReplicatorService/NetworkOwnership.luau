local NetworkOwnership = {}
NetworkOwnership.__index = NetworkOwnership
local signal = require("@Kinemium.signal")

local ownershipChanged = signal.new()

function NetworkOwnership.new()
	return setmetatable({ records = {}, nextVersion = 1 }, NetworkOwnership)
end

function NetworkOwnership:SetOwner(id, playerId, tick)
	local version = self.nextVersion
	self.nextVersion += 1
	self.records[id] = { owner = playerId, version = version, tick = tick or 0 }
	return self.records[id]
end

function NetworkOwnership:Revoke(id, tick)
	return self:SetOwner(id, nil, tick)
end

function NetworkOwnership:Get(id)
	return self.records[id]
end

function NetworkOwnership:IsOwner(id, playerId, version)
	local record = self.records[id]
	return record ~= nil and record.owner == playerId and (version == nil or record.version == version)
end

function NetworkOwnership:RevokePlayer(playerId, tick)
	local changed = {}
	for id, record in pairs(self.records) do
		if record.owner == playerId then
			changed[id] = self:Revoke(id, tick)
		end
	end
	return changed
end

function NetworkOwnership.GetConstraintParts(constraint)
	local part0 = constraint.Part0
		or (constraint.Attachment0 and constraint.Attachment0.Parent)
	local part1 = constraint.Part1
		or (constraint.Attachment1 and constraint.Attachment1.Parent)
	return part0, part1
end

local function ownerContextForPart(part, datamodel)
	local replicatorService = datamodel and datamodel:GetService("ReplicatorService")
	local replicator = replicatorService
		and replicatorService.GetActiveReplicator
		and replicatorService:GetActiveReplicator()
	local world = replicator and replicator.world
	local id = world and world:GetId(part)
	local record = id and world.ownership:Get(id)
	if record then
		return record.owner, true
	end

	local current = part
	while current do
		local owner = current.NetworkOwner
		if owner then
			return owner.UserId, replicator ~= nil
		end
		current = current.Parent
	end
	return nil, replicator ~= nil
end

function NetworkOwnership.ShouldSimulatePartForMachine(part, datamodel)
	if not part or part.Anchored == true then
		return false
	end

	local ownerId, networked = ownerContextForPart(part, datamodel)
	-- A local/non-networked game owns its entire physics world regardless of
	-- whether it is using the client renderer.
	if not networked then
		return true
	end
	if ownerId == nil then
		return IsServer == true
	end

	local players = datamodel and datamodel:GetService("Players")
	local localPlayer = players and players.LocalPlayer
	return IsServer ~= true and localPlayer ~= nil and localPlayer.UserId == ownerId
end

function NetworkOwnership.ShouldSimulateConstraintForMachine(constraint, datamodel)
	local part0, part1 = NetworkOwnership.GetConstraintParts(constraint)
	if not part0 or not part1 then
		return false
	end

	local selectedOwner = nil
	local selected = false
	local selectedNetworked = false
	for _, part in ipairs({ part0, part1 }) do
		if part.Anchored ~= true then
			local owner, networked = ownerContextForPart(part, datamodel)
			if selected and owner ~= selectedOwner then
				-- A constraint must never be solved by two machines. Dynamic bodies in
				-- one constrained island need the same owner.
				return false
			end
			selectedOwner = owner
			selectedNetworked = selectedNetworked or networked
			selected = true
		end
	end

	if selectedOwner == nil then
		return not selectedNetworked or IsServer == true
	end
	local players = datamodel and datamodel:GetService("Players")
	local localPlayer = players and players.LocalPlayer
	return IsServer ~= true and localPlayer and localPlayer.UserId == selectedOwner
end

function NetworkOwnership.NotifyOwnershipChanged(part)
	ownershipChanged:Fire(part)
end

function NetworkOwnership.ObserveConstraint(constraint, callback)
	return ownershipChanged:Connect(function(changedPart)
		local part0, part1 = NetworkOwnership.GetConstraintParts(constraint)
		if changedPart == part0 or changedPart == part1 then
			task.defer(callback)
		end
	end)
end

return NetworkOwnership
