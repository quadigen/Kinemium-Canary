-- description: "Allows clients and the server to invoke functions across the network and receive a response."
local RemoteBridge = require("@RemoteBridge")

return {
	class = "RemoteFunction",
	callback = function(instance, _, datamodel)
		instance:SetProperties({
			OnClientInvoke = nil,
			OnServerInvoke = nil,
			InvokeTimeout = 10,
		})
		RemoteBridge.BindFunction(instance, datamodel)

		return instance
	end,
}
