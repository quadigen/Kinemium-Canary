-- description: "Turns a character root toward its requested facing direction."
local Vector3 = require("@Vector3")
local CFrame = require("@CFrame")

return {
	class = "RotationController",
	callback = function(instance)
		instance:SetProperties({
			Name = "RotationController",
			Enabled = true,
			AutoRotate = true,
			TurnSpeed = 18,
			FacingDirection = nil,
		})

		function instance:Face(direction)
			if direction and direction.X ~= nil then
				local flat = Vector3.new(direction.X, 0, direction.Z)
				self.FacingDirection = flat:Magnitude() > 0.0001 and flat:Unit() or nil
			end
		end

		function instance:ClearFacingDirection()
			self.FacingDirection = nil
		end

		function instance:Step(rootPart, movementDirection, dt)
			if not self.Enabled or not rootPart or not rootPart.CFrame then
				return
			end
			local direction = self.FacingDirection
			if not direction and self.AutoRotate and movementDirection and movementDirection:Magnitude() > 0.0001 then
				direction = movementDirection:Unit()
			end
			if not direction then
				return
			end

			local target = CFrame.lookAt(rootPart.CFrame.Position, rootPart.CFrame.Position + direction)
			local alpha = 1 - math.exp(-(tonumber(self.TurnSpeed) or 18) * math.max(dt or 0, 0))
			rootPart.CFrame = rootPart.CFrame:Lerp(target, math.clamp(alpha, 0, 1))
		end

		return instance
	end,
}
