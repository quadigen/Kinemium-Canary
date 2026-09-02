local gns = require("@gns")
local ServerReplicator = require("../ReplicatorService/ServerReplicator")

local KinemiumServer = { KickForMissingMods = true, KickForWrongEngineVer = true }
local active = nil

function KinemiumServer:Init(address, port, datamodel, renderer)
	if active then
		return active
	end
	local service = datamodel:GetService("ReplicatorService")
	active = ServerReplicator.new(gns.Server, datamodel, renderer, {
		snapshotRate = service.SnapshotRate,
		interpolationDelayTicks = service.InterpolationDelayTicks,
		bandwidthBudget = service.BandwidthBudget,
		relevancyDistance = service.RelevancyDistance,
		teleportThreshold = service.TeleportThreshold,
	}):Start(address, port)
	service:_SetActive(active)
	return active
end

function KinemiumServer:GetActive()
	return active
end
function KinemiumServer:Shutdown()
	if active then
		active:Stop()
		active = nil
	end
end

return KinemiumServer
