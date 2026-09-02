local gns = require("@gns")
local ServerReplicator = require("../ReplicatorService/ServerReplicator")

local KinemiumStudioServer = {}
local active = nil

function KinemiumStudioServer:Init(address, port, datamodel, renderer, session)
	if active then
		return active
	end
	session = session or {}
	assert(type(session.token) == "string" and #session.token >= 16, "Studio collaboration requires an invite token")
	local service = datamodel:GetService("ReplicatorService")
	active = ServerReplicator.new(gns.Server, datamodel, renderer, {
		snapshotRate = service.SnapshotRate,
		interpolationDelayTicks = service.InterpolationDelayTicks,
		bandwidthBudget = service.BandwidthBudget,
		relevancyDistance = service.RelevancyDistance,
		teleportThreshold = service.TeleportThreshold,
		studioToken = session.token,
		readOnlyStudio = session.readOnly == true,
		studioHostName = session.name or "Host",
	}):Start(address or "0.0.0.0", port or 1234)
	service:_SetActive(active)
	return active
end

function KinemiumStudioServer:GetActive()
	return active
end

function KinemiumStudioServer:Shutdown()
	if active then
		active:Stop()
		active = nil
	end
end

return KinemiumStudioServer
