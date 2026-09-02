-- description: "Optional player-specific input source for a CharacterController."
local Vector3 = require("@Vector3")

return {
	class = "CharacterInput",
	callback = function(instance)
		instance:SetProperties({
			Name = "CharacterInput",
			Enabled = true,
			Controller = nil,
			MoveVector = Vector3.new(0, 0, 0),
			Sprinting = false,
		})

		function instance:Apply()
			if not self.Enabled or not self.Controller then
				return
			end
			self.Controller:Move(self.MoveVector)
			self.Controller:SetSprinting(self.Sprinting)
		end

		function instance:RequestJump()
			if self.Enabled and self.Controller then
				self.Controller:Jump()
			end
		end

		return instance
	end,
}
