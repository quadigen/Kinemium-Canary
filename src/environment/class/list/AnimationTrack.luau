-- description: "Controls playback of an imported skeletal animation clip."
local signal = require("@Kinemium.signal")

local propTable = {
	Name = "AnimationTrack",
	Animation = nil,
	AnimationId = "",
	IsPlaying = false,
	Looped = true,
	Speed = 1,
	TimePosition = 0,
	Length = 0,
	WeightCurrent = 1,
	WeightTarget = 1,
}

local function animationRoot(animator)
	local root = animator and animator.Parent
	if root and root.ClassName == "Humanoid" then
		root = root.Parent
	end
	return root
end

local function meshTargets(root)
	local targets = root:GetDescendants()
	if root.ClassName == "MeshPart" then
		table.insert(targets, root)
	end
	local meshes = {}
	for _, object in ipairs(targets) do
		if object.ClassName == "MeshPart" and object.GetBones and #object:GetBones() > 0 then
			meshes[#meshes + 1] = object
		end
	end
	return meshes
end

local function applyCustomPose(targets, animation, time)
	local pose = animation:Sample(time)
	for _, target in ipairs(targets) do
		for boneName, transform in pairs(pose) do
			local bone = target:GetBoneByName(boneName)
			if bone then
				bone.Transform = transform
			end
		end
	end
end

return {
	class = "AnimationTrack",
	callback = function(instance, renderer)
		instance:SetProperties(propTable)
		instance.Stopped = signal.new()
		instance.Ended = signal.new()
		instance.DidLoop = signal.new()
		instance.KeyframeReached = signal.new()
		instance._targets = {}
		instance._customAnimation = nil

		local function animationId()
			local animation = instance.Animation
			if animation and type(animation.AnimationId) == "string" then
				return animation.AnimationId
			end
			return instance.AnimationId
		end

		function instance:Play(_fadeTime: number?, weight: number?, speed: number?)
			local animator = instance._animator or instance.Parent
			local root = animationRoot(animator)
			if not root then
				return false
			end
			local animation = instance.Animation
			local custom = animation
				and animation.Sample
				and type(animation.Keyframes) == "table"
				and #animation:GetKeyframes() > 0
			local id = animationId()
			if not custom and (type(id) ~= "string" or id == "") then
				return false
			end
			local targets = {}
			local length = 0
			if custom then
				targets = meshTargets(root)
				length = math.max(0, animation.Length or 0)
				instance._customAnimation = animation
				for _, target in ipairs(targets) do
					target:StopAnimation()
				end
				applyCustomPose(targets, animation, 0)
			else
				instance._customAnimation = nil
				for _, object in ipairs(meshTargets(root)) do
					if object.PlayAnimation and object:PlayAnimation(id, instance.Looped, speed or instance.Speed) then
						table.insert(targets, object)
						for _, clip in ipairs(object:GetAnimationClips()) do
							local current = string.lower(object.CurrentAnimation or "")
							if string.lower(clip.Name or "") == current then
								length = math.max(length, clip.Length or 0)
							end
						end
					end
				end
			end
			instance._targets = targets
			instance.TimePosition = 0
			instance.Length = length
			instance.Speed = type(speed) == "number" and speed or instance.Speed
			instance.WeightCurrent = type(weight) == "number" and weight or 1
			instance.WeightTarget = instance.WeightCurrent
			instance.IsPlaying = #targets > 0
			return instance.IsPlaying
		end

		function instance:Stop(_fadeTime: number?)
			if not instance.IsPlaying then
				return
			end
			instance.IsPlaying = false
			for _, target in ipairs(instance._targets) do
				if target and target.StopAnimation then
					target:StopAnimation()
				end
			end
			table.clear(instance._targets)
			instance._customAnimation = nil
			instance.Stopped:Fire()
		end

		function instance:AdjustSpeed(speed: number)
			instance.Speed = speed
			for _, target in ipairs(instance._targets) do
				target.AnimationSpeed = speed
			end
		end

		function instance:AdjustWeight(weight: number, _fadeTime: number?)
			instance.WeightTarget = weight
			instance.WeightCurrent = weight
		end

		local destroyed = false
		if renderer and renderer.Hook and renderer.Hook.new then
			renderer.Hook.new("Renderstep", function(dt)
				if destroyed or not instance.IsPlaying then
					return
				end
				local previous = instance.TimePosition
				local current = previous + (dt or 0) * instance.Speed
				local length = instance.Length or 0
				if length > 0 and current >= length then
					if instance.Looped then
						current %= length
						instance.DidLoop:Fire()
					else
						instance.TimePosition = length
						if instance._customAnimation then
							applyCustomPose(instance._targets, instance._customAnimation, length)
						end
						instance:Stop()
						instance.Ended:Fire()
						return
					end
				end
				instance.TimePosition = current
				if instance._customAnimation then
					applyCustomPose(instance._targets, instance._customAnimation, current)
				end
			end)
		end

		instance.Destroying:Connect(function()
			destroyed = true
			instance:Stop()
		end)

		return instance
	end,
	inherit = function(tble)
		for prop, val in pairs(propTable) do
			tble[prop] = val
		end
	end,
}
