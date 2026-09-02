-- description: "Enables asynchronous communication between the client and server."
local signal = require("@Kinemium.signal")
local RemoteBridge = require("@RemoteBridge")

return {
	class = "RemoteEvent",
	callback = function(instance, renderer, datamodel)
		local OnClientEvent = signal.new()
		local OnServerEvent = signal.new()

		instance:SetProperties({
			OnClientEvent = OnClientEvent,
			OnServerEvent = OnServerEvent,
		})
		RemoteBridge.BindEvent(instance, datamodel, true)

		return instance
	end,
}
