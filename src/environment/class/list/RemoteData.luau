-- description: "Has a Data table property that can be changed by the client or the server, and replicate."
local signal = require("@Kinemium.signal")
local RemoteBridge = require("@RemoteBridge")

return {
	class = "RemoteData",
	callback = function(instance, _, datamodel)
		local dataChanged = signal.new()

		instance:SetProperties({
			Data = nil,
			DataChanged = dataChanged,
			LastWriter = nil,
		})

		instance:GetPropertyChangedSignal("Data"):Connect(function(value)
			dataChanged:Fire(value)
		end)
		RemoteBridge.BindData(instance, datamodel)

		return instance
	end,
}
