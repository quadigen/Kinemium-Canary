-- description: "Buffers character jump requests and resolves grounded or coyote-time jumps."
local signal = require("@Kinemium.signal")

return {
	class = "JumpController",
	callback = function(instance)
		instance:SetProperties({
			Name = "JumpController",
			Enabled = true,
			UseJumpPower = true,
			JumpPower = 50,
			JumpHeight = 7.2,
			BufferTime = 0.1,
			CoyoteTime = 0.1,
		})
		instance.JumpConsumed = signal.new()

		local requestedAt = nil
		local lastGroundedAt = nil

		function instance:Request(now)
			if not self.Enabled then
				return false
			end
			requestedAt = tonumber(now) or os.clock()
			return true
		end

		function instance:Clear()
			requestedAt = nil
		end

		function instance:UpdateGrounded(isGrounded, now)
			if isGrounded == true then
				lastGroundedAt = tonumber(now) or os.clock()
			end
		end

		function instance:Resolve(verticalVelocity, gravityMagnitude, isGrounded, now)
			now = tonumber(now) or os.clock()
			verticalVelocity = tonumber(verticalVelocity) or 0
			gravityMagnitude = math.abs(tonumber(gravityMagnitude) or 0)
			self:UpdateGrounded(isGrounded, now)

			local bufferTime = math.max(tonumber(self.BufferTime) or 0, 0)
			if requestedAt and now - requestedAt > bufferTime then
				requestedAt = nil
			end

			local coyoteTime = math.max(tonumber(self.CoyoteTime) or 0, 0)
			local canJump = isGrounded == true or (lastGroundedAt ~= nil and now - lastGroundedAt <= coyoteTime)
			if self.Enabled and requestedAt and canJump then
				requestedAt = nil
				lastGroundedAt = nil
				local jumpVelocity = if self.UseJumpPower
					then math.max(tonumber(self.JumpPower) or 0, 0)
					else math.sqrt(2 * gravityMagnitude * math.max(tonumber(self.JumpHeight) or 0, 0))
				self.JumpConsumed:Fire(jumpVelocity)
				return jumpVelocity, true
			end

			if isGrounded == true and verticalVelocity < 0 then
				verticalVelocity = 0
			end
			return verticalVelocity, false
		end

		return instance
	end,
}
