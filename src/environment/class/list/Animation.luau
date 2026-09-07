-- description: "Represents an Animation object that can be loaded and played by the Animator Instance (mainly used by Humanoids)."
local propTable = {
	AnimationId = "",
	Length = 1,
	Looped = true,
	Keyframes = {},
}

local function copyPose(pose)
	local result = {}
	for boneName, transform in pairs(pose or {}) do
		result[boneName] = transform
	end
	return result
end

local function sortedKeyframes(keyframes)
	local result = {}
	for _, keyframe in pairs(keyframes or {}) do
		if type(keyframe) == "table" and type(keyframe.Time) == "number" then
			result[#result + 1] = {
				Time = math.max(0, keyframe.Time),
				Poses = copyPose(keyframe.Poses),
			}
		end
	end
	table.sort(result, function(a, b)
		return a.Time < b.Time
	end)
	return result
end

local function findKeyframeIndex(keyframes, time, tolerance)
	local nearestIndex = nil
	local nearestDistance = math.huge
	for index, keyframe in ipairs(keyframes) do
		local distance = math.abs(keyframe.Time - time)
		if distance < nearestDistance then
			nearestDistance = distance
			nearestIndex = index
		end
	end
	if nearestIndex and nearestDistance <= tolerance then
		return nearestIndex
	end
	return nil
end

local function poseIsEmpty(pose)
	return type(pose) ~= "table" or next(pose) == nil
end

return {
	class = "Animation",
	callback = function(instance)
		instance:SetProperties(propTable)
		-- Keyframes must not be shared by Animation instances.
		instance.Keyframes = {}

		function instance:GetKeyframes()
			return sortedKeyframes(instance.Keyframes)
		end

		function instance:SetKeyframe(time: number, poses)
			time = math.max(0, tonumber(time) or 0)
			local keyframes = sortedKeyframes(instance.Keyframes)
			local replaced = false
			for _, keyframe in ipairs(keyframes) do
				if math.abs(keyframe.Time - time) <= 1e-5 then
					keyframe.Time = time
					keyframe.Poses = copyPose(poses)
					replaced = true
					break
				end
			end
			if not replaced then
				keyframes[#keyframes + 1] = {
					Time = time,
					Poses = copyPose(poses),
				}
				table.sort(keyframes, function(a, b)
					return a.Time < b.Time
				end)
			end
			instance.Keyframes = keyframes
			instance.Length = math.max(instance.Length or 0, time)
			return keyframes
		end

		function instance:GetKeyframeAt(time: number, tolerance: number?)
			time = math.max(0, tonumber(time) or 0)
			local keyframes = sortedKeyframes(instance.Keyframes)
			local index = findKeyframeIndex(keyframes, time, math.max(0, tonumber(tolerance) or 1e-5))
			return index and keyframes[index] or nil
		end

		function instance:SetBoneKeyframe(time: number, boneName: string, transform)
			assert(type(boneName) == "string" and boneName ~= "", "Animation:SetBoneKeyframe expects a bone name")
			time = math.max(0, tonumber(time) or 0)
			local keyframes = sortedKeyframes(instance.Keyframes)
			local index = findKeyframeIndex(keyframes, time, 1e-5)
			if not index then
				keyframes[#keyframes + 1] = { Time = time, Poses = {} }
				table.sort(keyframes, function(a, b)
					return a.Time < b.Time
				end)
				index = findKeyframeIndex(keyframes, time, 1e-5)
			end
			keyframes[index].Poses[boneName] = transform
			instance.Keyframes = keyframes
			instance.Length = math.max(instance.Length or 0, time)
			return keyframes[index]
		end

		function instance:RemoveBoneKeyframe(time: number, boneName: string, tolerance: number?)
			time = math.max(0, tonumber(time) or 0)
			local keyframes = sortedKeyframes(instance.Keyframes)
			local index = findKeyframeIndex(keyframes, time, math.max(0, tonumber(tolerance) or 1e-5))
			if not index or keyframes[index].Poses[boneName] == nil then
				return false
			end
			keyframes[index].Poses[boneName] = nil
			if poseIsEmpty(keyframes[index].Poses) then
				table.remove(keyframes, index)
			end
			instance.Keyframes = keyframes
			return true
		end

		function instance:MoveKeyframe(fromTime: number, toTime: number, boneName: string?, tolerance: number?)
			fromTime = math.max(0, tonumber(fromTime) or 0)
			toTime = math.max(0, tonumber(toTime) or 0)
			tolerance = math.max(0, tonumber(tolerance) or 1e-5)
			local keyframes = sortedKeyframes(instance.Keyframes)
			local sourceIndex = findKeyframeIndex(keyframes, fromTime, tolerance)
			if not sourceIndex then
				return false
			end

			local source = keyframes[sourceIndex]
			local movedPose = {}
			if boneName then
				local transform = source.Poses[boneName]
				if transform == nil then
					return false
				end
				movedPose[boneName] = transform
				source.Poses[boneName] = nil
				if poseIsEmpty(source.Poses) then
					table.remove(keyframes, sourceIndex)
				end
			else
				movedPose = copyPose(source.Poses)
				table.remove(keyframes, sourceIndex)
			end

			local targetIndex = findKeyframeIndex(keyframes, toTime, 1e-5)
			if not targetIndex then
				keyframes[#keyframes + 1] = { Time = toTime, Poses = {} }
				table.sort(keyframes, function(a, b)
					return a.Time < b.Time
				end)
				targetIndex = findKeyframeIndex(keyframes, toTime, 1e-5)
			end
			for name, transform in pairs(movedPose) do
				keyframes[targetIndex].Poses[name] = transform
			end
			instance.Keyframes = keyframes
			instance.Length = math.max(instance.Length or 0, toTime)
			return true
		end

		function instance:RemoveKeyframe(time: number, tolerance: number?)
			time = math.max(0, tonumber(time) or 0)
			tolerance = math.max(0, tonumber(tolerance) or 1e-5)
			local keyframes = sortedKeyframes(instance.Keyframes)
			local nearestIndex = findKeyframeIndex(keyframes, time, tolerance)
			if nearestIndex then
				table.remove(keyframes, nearestIndex)
				instance.Keyframes = keyframes
				return true
			end
			return false
		end

		function instance:Sample(time: number)
			local keyframes = sortedKeyframes(instance.Keyframes)
			if #keyframes == 0 then
				return {}
			end
			time = math.max(0, tonumber(time) or 0)
			local pose = {}
			local boneNames = {}
			for _, keyframe in ipairs(keyframes) do
				for boneName in pairs(keyframe.Poses or {}) do
					boneNames[boneName] = true
				end
			end
			for boneName in pairs(boneNames) do
				local before = nil
				local after = nil
				for _, keyframe in ipairs(keyframes) do
					local transform = keyframe.Poses and keyframe.Poses[boneName]
					if transform ~= nil then
						if keyframe.Time <= time then
							before = { Time = keyframe.Time, Transform = transform }
						end
						if keyframe.Time >= time then
							after = { Time = keyframe.Time, Transform = transform }
							break
						end
					end
				end
				before = before or after
				after = after or before
				if before and after then
					local span = after.Time - before.Time
					local alpha = span > 1e-6 and math.clamp((time - before.Time) / span, 0, 1) or 0
					pose[boneName] = before.Transform.Lerp
						and before.Transform:Lerp(after.Transform, alpha)
						or before.Transform
				end
			end
			return pose
		end

		return instance
	end,
	inherit = function(tble)
		for prop, val in pairs(propTable) do
			tble[prop] = val
		end
	end,
}
