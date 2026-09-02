-- description: "Resolves workspace gravity and terminal velocity for a character."
local Vector3 = require("@Vector3")

return {
	class = "GravityController",
	callback = function(instance)
		instance:SetProperties({
			Name = "GravityController",
			Enabled = true,
			GravityScale = 1,
			DefaultGravity = 196.2,
			TerminalVelocity = 500,
		})

		function instance:GetMagnitude(workspaceGravity)
			if not self.Enabled then
				return 0
			end
			local gravity = math.abs(tonumber(workspaceGravity) or (tonumber(self.DefaultGravity) or 196.2))
			return gravity * math.max(tonumber(self.GravityScale) or 0, 0)
		end

		function instance:GetAcceleration(workspaceGravity)
			return Vector3.new(0, -self:GetMagnitude(workspaceGravity), 0)
		end

		function instance:ClampVerticalVelocity(verticalVelocity)
			local terminalVelocity = math.max(tonumber(self.TerminalVelocity) or math.huge, 0)
			return math.clamp(tonumber(verticalVelocity) or 0, -terminalVelocity, terminalVelocity)
		end

		return instance
	end,
}
