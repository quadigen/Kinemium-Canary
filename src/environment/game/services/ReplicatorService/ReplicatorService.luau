local Instance = require("@Instance")
local signal = require("@Kinemium.signal")
local NetworkEmulator = require("@ReplicationNetworkEmulator")
local ReplicationSchema = require("@ReplicationSchema")

local ReplicatorService = Instance.new("ReplicatorService")
ReplicatorService.ExplorerHidden = true
ReplicatorService.SnapshotRate = 20
ReplicatorService.InterpolationDelayTicks = 2
ReplicatorService.BandwidthBudget = 48 * 1024
ReplicatorService.RelevancyDistance = 1024
ReplicatorService.TeleportThreshold = 12
ReplicatorService.EventReceived = signal.new()

local active = nil
local datamodel = nil
local renderer = nil
local pendingEvents = {}

local function options()
	return {
		snapshotRate = ReplicatorService.SnapshotRate,
		interpolationDelayTicks = ReplicatorService.InterpolationDelayTicks,
		bandwidthBudget = ReplicatorService.BandwidthBudget,
		relevancyDistance = ReplicatorService.RelevancyDistance,
		teleportThreshold = ReplicatorService.TeleportThreshold,
	}
end

function ReplicatorService:_SetActive(nextActive)
	active = nextActive
	for name, callbacks in pairs(pendingEvents) do
		for _, callback in ipairs(callbacks) do
			active:OnEvent(name, callback)
		end
	end
	table.clear(pendingEvents)
	return active
end

function ReplicatorService:GetActiveReplicator()
	return active
end
function ReplicatorService:GetStats()
	if not active then
		return { connected = false, replicatedEntities = 0 }
	end
	local stats = active.GetStats and active:GetStats() or active.world:GetStats()
	stats.connected = active.connected ~= false
	return stats
end

function ReplicatorService:OnEvent(name, callback)
	if active then
		active:OnEvent(name, callback)
	else
		pendingEvents[name] = pendingEvents[name] or {}
		table.insert(pendingEvents[name], callback)
	end
end

function ReplicatorService:SendEvent(name, data, reliable)
	if not active then
		return false
	end
	return active:SendEvent(name, data, reliable)
end

function ReplicatorService:SendEventTo(player, name, data, reliable)
	if not active or not active.SendEventTo then
		return false
	end
	return active:SendEventTo(player, name, data, reliable)
end

function ReplicatorService:Register(instance)
	if not active or not active.world then
		return nil
	end
	if active.RegisterEntity then
		return active:RegisterEntity(instance)
	end
	return active.world:Register(instance)
end

function ReplicatorService:Unregister(instance)
	if not active or not active.world then
		return false
	end
	if active.UnregisterEntity then
		return active:UnregisterEntity(instance)
	end
	return active.world:Unregister(instance) ~= nil
end

function ReplicatorService:RegisterSchema(className, properties)
	return ReplicationSchema.RegisterClass(className, properties)
end

function ReplicatorService:AssignOwnership(instance, player)
	return active and active.AssignOwnership and active:AssignOwnership(instance, player) or nil
end

function ReplicatorService:CreateNetworkEmulator(config)
	return NetworkEmulator.new(config)
end

function ReplicatorService:StartServer(address, port)
	assert(datamodel, "ReplicatorService is not initialized")
	local gns = require("@gns")
	local ServerReplicator = require("@ServerReplicator")
	return self:_SetActive(ServerReplicator.new(gns.Server, datamodel, renderer, options()):Start(address, port))
end

function ReplicatorService:ConnectClient(address, port, arguments)
	assert(datamodel, "ReplicatorService is not initialized")
	local gns = require("@gns")
	local ClientReplicator = require("@ClientReplicator")
	return self:_SetActive(
		ClientReplicator.new(gns.Client, datamodel, renderer, options()):Start(address, port, arguments)
	)
end

function ReplicatorService:Stop()
	if active and active.Stop then
		active:Stop()
	end
	active = nil
end

ReplicatorService.InitRenderer = function(nextRenderer, _, game)
	renderer, datamodel = nextRenderer, game
	return ReplicatorService
end

return ReplicatorService
