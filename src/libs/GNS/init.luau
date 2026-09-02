local Server = require("@GNS/Server")
local Client = require("@GNS/Client")
local Serializer = require("@GNS/Serializer")
local SerializerAdapters = require("@GNS/SerializerAdapters")

-- Both endpoints must register custom datatypes in the same deterministic order
-- before their first packet is encoded or decoded.
SerializerAdapters.EnsureRegistered()

local ServerInstance = Server.new()
local ClientInstance = Client.new()

return {
	Server = ServerInstance,
	Client = ClientInstance,
	Serializer = Serializer,
	SerializerAdapters = SerializerAdapters,
}
