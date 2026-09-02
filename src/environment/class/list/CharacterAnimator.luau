-- description: "Bridges character locomotion state to an Animator."
local CFrame = require("@CFrame")

local RIG_OFFSETS = {
	Torso = CFrame.new(0, 0, 0),
	Neck = CFrame.new(0, 1.32, 0),
	Head = CFrame.new(0, 2.02, 0),
	["Left Shoulder"] = CFrame.new(-1.2, 0.67, 0),
	["Left Arm"] = CFrame.new(-1.2, -0.14, 0),
	["Left Hand"] = CFrame.new(-1.2, -0.88, 0),
	["Right Shoulder"] = CFrame.new(1.2, 0.67, 0),
	["Right Arm"] = CFrame.new(1.2, -0.14, 0),
	["Right Hand"] = CFrame.new(1.2, -0.88, 0),
	["Left Hip"] = CFrame.new(-0.43, -1.5, 0),
	["Left Leg"] = CFrame.new(-0.43, -2.43, 0),
	["Left Foot"] = CFrame.new(-0.43, -3.28, -0.14),
	["Right Hip"] = CFrame.new(0.43, -1.5, 0),
	["Right Leg"] = CFrame.new(0.43, -2.43, 0),
	["Right Foot"] = CFrame.new(0.43, -3.28, -0.14),
}

local function animatedOffset(partName, angle)
	if string.find(partName, "Left ") == 1 and (string.find(partName, "Shoulder") or string.find(partName, "Arm") or string.find(partName, "Hand")) then
		local offset = RIG_OFFSETS[partName]
		return CFrame.new(-1.2, 1.03, 0) * CFrame.Angles(angle, 0, 0) * CFrame.new(0, offset.Position.Y - 1.03, offset.Position.Z)
	elseif string.find(partName, "Right ") == 1 and (string.find(partName, "Shoulder") or string.find(partName, "Arm") or string.find(partName, "Hand")) then
		local offset = RIG_OFFSETS[partName]
		return CFrame.new(1.2, 1.03, 0) * CFrame.Angles(angle, 0, 0) * CFrame.new(0, offset.Position.Y - 1.03, offset.Position.Z)
	elseif string.find(partName, "Left ") == 1 and (string.find(partName, "Hip") or string.find(partName, "Leg") or string.find(partName, "Foot")) then
		local offset = RIG_OFFSETS[partName]
		return CFrame.new(-0.43, -1.15, 0) * CFrame.Angles(angle, 0, 0) * CFrame.new(0, offset.Position.Y + 1.15, offset.Position.Z)
	elseif string.find(partName, "Right ") == 1 and (string.find(partName, "Hip") or string.find(partName, "Leg") or string.find(partName, "Foot")) then
		local offset = RIG_OFFSETS[partName]
		return CFrame.new(0.43, -1.15, 0) * CFrame.Angles(angle, 0, 0) * CFrame.new(0, offset.Position.Y + 1.15, offset.Position.Z)
	end
	return RIG_OFFSETS[partName]
end

return {
	class = "CharacterAnimator",
	callback = function(instance)
		instance:SetProperties({ Name = "CharacterAnimator", Enabled = true, Animator = nil, Controller = nil })
		local function applyDefaultRigPose(target, context)
			local controller = instance.Controller
			local root = controller and controller.RootPart
			if not target or not root or not root.CFrame then
				return
			end
			local moving = context.state == "Running"
			local swing = moving and math.sin((context.clock or 0) * 9) * 0.45 or 0

			for partName in pairs(RIG_OFFSETS) do
				local part = target:FindFirstChild(partName)
				if part then
					local isLeftArm = string.find(partName, "Left ") == 1
						and (string.find(partName, "Shoulder") or string.find(partName, "Arm") or string.find(partName, "Hand"))
					local isRightLeg = string.find(partName, "Right ") == 1
						and (string.find(partName, "Hip") or string.find(partName, "Leg") or string.find(partName, "Foot"))
					local direction = (isLeftArm or isRightLeg) and -1 or 1
					part.CFrame = root.CFrame * animatedOffset(partName, swing * direction)
				end
			end
		end

		function instance:Step(dt)
			if not self.Enabled or not self.Animator or not self.Animator.StepAnimation then
				return nil
			end
			local context = {
				dt = dt or 0,
				state = self.Controller and self.Controller:GetState() or "Idle",
				moveDirection = self.Controller and self.Controller.MoveDirection or nil,
			}
			local pose = self.Animator:StepAnimation(self.Parent, context)
			applyDefaultRigPose(self.Parent, context)
			return pose
		end

		return instance
	end,
}
