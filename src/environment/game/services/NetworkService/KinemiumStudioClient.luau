local gns = require("@gns")
local ClientReplicator = require("../ReplicatorService/ClientReplicator")
local Protocol = require("../ReplicatorService/Protocol")

local KinemiumStudioClient = {}
local active = nil

function KinemiumStudioClient:Init(address, port, datamodel, renderer, session)
	if active then
		return active
	end
	session = session or {}
	assert(type(session.token) == "string" and #session.token >= 16, "A valid studio invitation is required")
	local service = datamodel:GetService("ReplicatorService")
	active = ClientReplicator.new(gns.Client, datamodel, renderer, {
		snapshotRate = service.SnapshotRate,
		interpolationDelayTicks = service.InterpolationDelayTicks,
		bandwidthBudget = service.BandwidthBudget,
		relevancyDistance = service.RelevancyDistance,
		teleportThreshold = service.TeleportThreshold,
		studio = true,
	}):Start(address or "127.0.0.1", port or 1234, {
		name = session.name or "Collaborator",
		engine_version = ENGINE_VERSION,
		protocol_version = Protocol.Version,
		mods = {},
		studio = true,
		studioToken = session.token,
	})
	service:_SetActive(active)
	return active
end

function KinemiumStudioClient:GetActive()
	return active
end

function KinemiumStudioClient:Shutdown()
	if active then
		active:Stop()
		active = nil
	end
end

return KinemiumStudioClient
