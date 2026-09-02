-- description: "Optional player-specific camera binding for a character."
return {
	class = "CharacterCamera",
	callback = function(instance)
		instance:SetProperties({ Name = "CharacterCamera", Enabled = true, Camera = nil, Controller = nil })

		function instance:Bind(camera, controller)
			self.Camera = camera
			self.Controller = controller
			if self.Enabled and camera then
				camera.CameraSubject = controller or (controller and controller.Parent)
			end
		end

		function instance:Unbind()
			if self.Camera and self.Camera.CameraSubject == self.Controller then
				self.Camera.CameraSubject = nil
			end
			self.Camera = nil
			self.Controller = nil
		end

		return instance
	end,
}
