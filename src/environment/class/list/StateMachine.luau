-- description: "Tracks character locomotion state and state transitions."
local signal = require("@Kinemium.signal")

return {
	class = "StateMachine",
	callback = function(instance)
		instance:SetProperties({ Name = "StateMachine", CurrentState = "Freefall", Enabled = true })
		instance.StateChanged = signal.new()

		function instance:ChangeState(nextState)
			if not self.Enabled or nextState == nil or nextState == self.CurrentState then
				return false
			end
			local previous = self.CurrentState
			self.CurrentState = nextState
			self.StateChanged:Fire(nextState, previous)
			return true
		end

		function instance:GetState()
			return self.CurrentState
		end

		return instance
	end,
}
