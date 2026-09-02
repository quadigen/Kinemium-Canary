-- description: "A remote event that sends data without guaranteeing delivery."
local signal = require("@Kinemium.signal")
local RemoteBridge = require("@RemoteBridge")

return {
	class = "UnreliableRemoteEvent",
	callback = function(instance, properties, datamodel)
		local clientEvent = signal.new()
		local serverEvent = signal.new()

		instance:SetProperties({
			OnClientEvent = clientEvent,
			OnServerEvent = serverEvent,
		})
		RemoteBridge.BindEvent(instance, datamodel, false)

		return instance
	end,
}
