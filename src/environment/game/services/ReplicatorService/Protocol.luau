local Protocol = {
	Name = "KRP",
	Version = 3,
	Kinds = {
		Handshake = 1,
		HandshakeAccepted = 2,
		HandshakeRejected = 3,
		FullSnapshot = 4,
		Snapshot = 5,
		SnapshotAck = 6,
		Spawn = 7,
		Despawn = 8,
		InputCommand = 9,
		OwnershipChanged = 10,
		OwnedPhysicsState = 11,
		Event = 12,
		Ping = 13,
		Pong = 14,
		ResyncRequest = 15,
		StudioEdit = 16,
		StudioEditResult = 17,
		StudioPresence = 18,
		StudioCamera = 19,
	},
	Reliability = {},
}

for _, name in ipairs({
	"Handshake",
	"HandshakeAccepted",
	"HandshakeRejected",
	"FullSnapshot",
	"Spawn",
	"Despawn",
	"OwnershipChanged",
	"Event",
	"ResyncRequest",
	"StudioEdit",
	"StudioEditResult",
	"StudioPresence",
}) do
	Protocol.Reliability[Protocol.Kinds[name]] = true
end

function Protocol.Packet(kind, payload)
	return {
		type = Protocol.Name,
		version = Protocol.Version,
		kind = kind,
		payload = payload or {},
	}
end

function Protocol.Validate(packet)
	if type(packet) ~= "table" or packet.type ~= Protocol.Name then
		return false, "not a replication packet"
	end
	if packet.version ~= Protocol.Version then
		return false, "protocol version mismatch"
	end
	if type(packet.kind) ~= "number" or packet.kind % 1 ~= 0 or packet.kind < 1 or packet.kind > 19 then
		return false, "invalid message kind"
	end
	if type(packet.payload) ~= "table" then
		return false, "invalid payload"
	end
	return true
end

function Protocol.IsReliable(kind)
	return Protocol.Reliability[kind] == true
end

return table.freeze(Protocol)
