local gns = require("@gns")
local ClientReplicator = require("../ReplicatorService/ClientReplicator")

local KinemiumClient = {}
local active = nil

local function getMods(datamodel)
	local service = datamodel:GetService("KinemiumModService")
	local result = {}
	if not service or not service.GetEnabledMods then
		return result
	end
	for _, modData in pairs(service:GetEnabledMods()) do
		local manifest = modData.manifest
		if manifest then
			result[`{manifest.author}.{manifest.name}`] = manifest.version
		end
	end
	return result
end

function KinemiumClient:Init(address, port, datamodel, renderer)
	if active then
		return active
	end
	local service = datamodel:GetService("ReplicatorService")
	active = ClientReplicator.new(gns.Client, datamodel, renderer, {
		snapshotRate = service.SnapshotRate,
		interpolationDelayTicks = service.InterpolationDelayTicks,
		bandwidthBudget = service.BandwidthBudget,
		relevancyDistance = service.RelevancyDistance,
		teleportThreshold = service.TeleportThreshold,
	}):Start(address, port, {
		name = GetFlagValue("username") or "User",
		engine_version = ENGINE_VERSION,
		protocol_version = require("../ReplicatorService/Protocol").Version,
		mods = getMods(datamodel),
	})
	service:_SetActive(active)
	return active
end

function KinemiumClient:GetActive()
	return active
end
function KinemiumClient:Shutdown()
	if active then
		active:Stop()
		active = nil
	end
end

return KinemiumClient
