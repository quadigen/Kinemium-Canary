-- description: "Converts character movement requests into target velocities."
local Vector3 = require("@Vector3")

local ZERO = Vector3.new(0, 0, 0)

return {
	class = "MovementController",
	callback = function(instance)
		instance:SetProperties({
			Name = "MovementController",
			MoveDirection = ZERO,
			WalkSpeed = 16,
			SprintMultiplier = 1.5,
			Sprinting = false,
			Enabled = true,
		})

		function instance:SetMoveDirection(direction)
			if type(direction) ~= "table" or direction.X == nil then
				direction = ZERO
			end
			local horizontal = Vector3.new(direction.X, 0, direction.Z)
			if horizontal:Magnitude() > 1 then
				horizontal = horizontal:Unit()
			end
			self.MoveDirection = horizontal
		end

		function instance:GetTargetVelocity(verticalVelocity)
			if not self.Enabled then
				return Vector3.new(0, verticalVelocity or 0, 0)
			end
			local speed = (tonumber(self.WalkSpeed) or 0)
				* (self.Sprinting and (tonumber(self.SprintMultiplier) or 1) or 1)
			local horizontal = self.MoveDirection * speed
			return Vector3.new(horizontal.X, verticalVelocity or 0, horizontal.Z)
		end

		return instance
	end,
}
