-- description: "Stores and publishes the character motor's ground contact."
local signal = require("@Kinemium.signal")

return {
	class = "GroundDetector",
	callback = function(instance)
		instance:SetProperties({ Name = "GroundDetector", IsGrounded = false, GroundInstance = nil, Enabled = true })
		instance.GroundedChanged = signal.new()

		function instance:Update(isGrounded, groundInstance)
			isGrounded = self.Enabled and isGrounded == true
			local changed = isGrounded ~= self.IsGrounded
			self.IsGrounded = isGrounded
			self.GroundInstance = isGrounded and groundInstance or nil
			if changed then
				self.GroundedChanged:Fire(isGrounded, self.GroundInstance)
			end
		end

		return instance
	end,
}
