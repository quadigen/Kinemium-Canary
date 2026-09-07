local StudioThemeService = game:GetService("StudioThemeService")
local Selection = game:GetService("Selection")
local Immco = require("@Immco")
local Argon = require("@Argon")

if IsServer or IsClient then
	return
end

repeat
	task.wait()
until game.CoreGui:FindFirstChild("Studio") and ishared.StudioSystem
local theme = StudioThemeService.SelectedTheme

local AnimatorDock = Instance.new("Frame")
AnimatorDock.Name = "AnimatorDock"
AnimatorDock.Size = theme.OutputCoordinates.Size
AnimatorDock.Position = theme.OutputCoordinates.Position
AnimatorDock.BackgroundTransparency = 1
AnimatorDock.Parent = game.CoreGui:FindFirstChild("Studio")

local FRAME_RATE = 30
local ROW_HEIGHT = 24
local RULER_HEIGHT = 28

local selectedKeyTime = nil
local selectedKeyBone = nil
local timelineKeyDrag = nil
local gizmoDragState = nil
local gizmoMode = "Move"

local retained = {}
local visible = false
local status = "Select a skinned MeshPart or one of its Bones."
local targetMesh = nil
local selectedBone = nil
local selectedClip = nil
local clips = {}
local bonePage = 1
local playhead = 0
local playing = false
local speed = 1
local looped = true

local boneGizmoProxy = Instance.new("Attachment")
boneGizmoProxy.Name = "AnimatorBoneGizmoProxy"

local boneHandles = Instance.new("Handles")
boneHandles.Name = "AnimatorBoneHandles"
boneHandles.Adornee = nil
boneHandles.Style = Enum.HandlesStyle.Movement
boneHandles.RotationSnap = 15
boneHandles.Parent = AnimatorDock

local POSE_FIELD_IDS = {
	"animator-position-x",
	"animator-position-y",
	"animator-position-z",
	"animator-rotation-x",
	"animator-rotation-y",
	"animator-rotation-z",
}

local function alive(object)
	return object ~= nil and rawget(object, "_props") ~= nil and not rawget(object, "Destroyed")
end

local function findMesh(object)
	if not alive(object) then
		return nil
	end
	if object.ClassName == "MeshPart" then
		return object
	end
	local ancestor = object:FindFirstAncestorOfClass("MeshPart")
	if ancestor then
		return ancestor
	end
	for _, descendant in ipairs(object:GetDescendants()) do
		if descendant.ClassName == "MeshPart" then
			return descendant
		end
	end
	return nil
end

local function currentSelection()
	local selected = Selection:Get()
	return selected and selected[1] or nil
end

local function setRetainedText(id, value)
	local field = retained[id]
	if field then
		field.text = tostring(value)
		field.cursorPos = math.min(field.cursorPos or 0, #field.text)
	end
end

local function formatNumber(value)
	if math.abs(value or 0) < 1e-7 then
		return "0"
	end
	return string.format("%.4f", value):gsub("0+$", ""):gsub("%.$", "")
end

local function syncPoseFields()
	if not alive(selectedBone) then
		return
	end
	local transform = selectedBone.Transform or CFrame.new()
	local rx, ry, rz = transform:ToOrientation()
	local values = {
		transform.Position.X,
		transform.Position.Y,
		transform.Position.Z,
		math.deg(rx),
		math.deg(ry),
		math.deg(rz),
	}
	for index, id in ipairs(POSE_FIELD_IDS) do
		setRetainedText(id, formatNumber(values[index]))
	end
end

local function meshBones()
	if not alive(targetMesh) or not targetMesh.GetBones then
		return {}
	end
	return targetMesh:GetBones()
end

local function selectBone(bone)
	selectedBone = bone
	syncPoseFields()
	if alive(bone) then
		Selection:Set({ bone })
	end
end

local function clipLength(entry)
	if not entry then
		return 1
	end
	if entry.kind == "custom" then
		return math.max(0.001, tonumber(entry.animation.Length) or 1)
	end
	return math.max(0.001, tonumber(entry.length) or 1)
end

local function snapTime(value)
	local length = clipLength(selectedClip)
	value = math.clamp(value, 0, length)

	return math.clamp(math.floor(value * FRAME_RATE + 0.5) / FRAME_RATE, 0, length)
end

local function formatFrameTime(value)
	local totalFrames = math.floor(math.max(0, value) * FRAME_RATE + 0.5)
	local seconds = math.floor(totalFrames / FRAME_RATE)
	local frame = totalFrames % FRAME_RATE

	return string.format("%d:%02d", seconds, frame)
end

local function keyframeTime(keyframe)
	return tonumber(keyframe.Time) or 0
end

local function clipKeyframes(entry)
	if not entry then
		return {}
	end

	local source = nil

	if entry.kind == "custom" and entry.animation.GetKeyframes then
		source = entry.animation:GetKeyframes()
	elseif type(entry.keyframes) == "table" then
		source = entry.keyframes
	end

	local result = {}

	for _, keyframe in ipairs(source or {}) do
		result[#result + 1] = keyframe
	end

	table.sort(result, function(a, b)
		return keyframeTime(a) < keyframeTime(b)
	end)

	return result
end

local function keyframePose(keyframe)
	if type(keyframe) ~= "table" then
		return nil
	end

	return keyframe.Poses or keyframe.Pose or keyframe.Transforms or keyframe.Value or keyframe.pose
end

local function keyframeHasBone(keyframe, bone)
	local pose = keyframePose(keyframe)

	-- Your current SetKeyframe(time, snapshotPose()) format is a
	-- full-pose keyframe, so fall back to showing it on every track.
	if type(pose) ~= "table" then
		return true
	end

	return pose[bone.Name] ~= nil
end

local function timelineMajorStep(length, width)
	if length <= 0 then
		return 1
	end

	local target = length / math.max(1, width / 85)

	local steps = {
		1 / 30,
		1 / 15,
		0.1,
		0.2,
		0.25,
		0.5,
		1,
		2,
		5,
		10,
		20,
		30,
		60,
	}

	for _, step in ipairs(steps) do
		if step >= target then
			return step
		end
	end

	return steps[#steps]
end

local function timelineX(time, rect, length)
	return rect.x + math.clamp(time / math.max(length, 0.001), 0, 1) * rect.width
end

local function refreshClips(preferred)
	local previous = preferred or selectedClip
	clips = {}
	selectedClip = nil
	if not alive(targetMesh) then
		return
	end

	if targetMesh.GetAnimationClips then
		for _, clip in ipairs(targetMesh:GetAnimationClips()) do
			clips[#clips + 1] = {
				kind = "imported",
				name = clip.Name ~= "" and clip.Name or ("Imported " .. tostring(clip.Index)),
				length = clip.Length,
				index = clip.Index,
			}
		end
	end

	for _, child in ipairs(targetMesh:GetChildren()) do
		if child.ClassName == "Animation" and type(child.Keyframes) == "table" then
			clips[#clips + 1] = {
				kind = "custom",
				name = child.Name,
				animation = child,
			}
		end
	end

	for _, entry in ipairs(clips) do
		if previous == entry or (previous and previous.animation and previous.animation == entry.animation) then
			selectedClip = entry
			break
		end
	end
	selectedClip = selectedClip or clips[1]
	playhead = math.clamp(playhead, 0, clipLength(selectedClip))

	local dropdownState = retained["animator-clips"]
	if dropdownState then
		dropdownState.selected = selectedClip and (table.find(clips, selectedClip) or 0) or 0
	end
end

local function setTarget(mesh, sourceObject)
	playing = false
	targetMesh = mesh
	selectedBone = nil
	bonePage = 1
	playhead = 0
	selectedKeyTime = nil
	selectedKeyBone = nil
	timelineKeyDrag = nil
	boneHandles.Adornee = nil
	if not mesh then
		clips = {}
		selectedClip = nil
		status = "Selection has no MeshPart."
		return
	end
	local bones = meshBones()
	selectedBone = sourceObject and sourceObject.ClassName == "Bone" and sourceObject or bones[1]
	refreshClips()
	syncPoseFields()
	if #bones == 0 then
		status = `Selected {mesh.Name}, but it has no imported skin/bones yet.`
	else
		status = `Editing {mesh:GetFullName()} ({#bones} bones)`
	end
end

local function useSelection()
	local object = currentSelection()
	setTarget(findMesh(object), object)
end

local function snapshotPose()
	local pose = {}
	for _, bone in ipairs(meshBones()) do
		pose[bone.Name] = bone.Transform or CFrame.new()
	end
	return pose
end

local function applyCustomPose(entry, time)
	if not entry or entry.kind ~= "custom" or not entry.animation.Sample then
		return
	end
	for boneName, transform in pairs(entry.animation:Sample(time)) do
		local bone = targetMesh:GetBoneByName(boneName)
		if bone then
			bone.Transform = transform
		end
	end
	syncPoseFields()
end

local function scrub(time)
	if not alive(targetMesh) or not selectedClip then
		return
	end
	playhead = math.clamp(time, 0, clipLength(selectedClip))
	if selectedClip.kind == "custom" then
		targetMesh:StopAnimation()
		applyCustomPose(selectedClip, playhead)
	else
		if targetMesh.CurrentAnimation ~= selectedClip.name then
			targetMesh:PlayAnimation(selectedClip.index or selectedClip.name, looped, 0)
		end
		targetMesh.AnimationTime = playhead
		targetMesh.AnimationSpeed = 0
	end
end

local function stopPlayback(resetPose)
	playing = false
	playhead = 0
	if alive(targetMesh) then
		if resetPose and targetMesh.ResetBoneTransforms then
			targetMesh:ResetBoneTransforms()
		else
			targetMesh:StopAnimation()
		end
	end
	syncPoseFields()
end

local function playSelected()
	if not alive(targetMesh) or not selectedClip then
		status = "Choose a rig and animation clip first."
		return
	end
	playing = true
	if selectedClip.kind == "imported" then
		if not targetMesh:PlayAnimation(selectedClip.index or selectedClip.name, looped, speed) then
			playing = false
			status = "The imported clip could not be started."
			return
		end
		targetMesh.AnimationTime = playhead
	else
		targetMesh:StopAnimation()
		applyCustomPose(selectedClip, playhead)
	end
	status = `Playing {selectedClip.name}`
end

local function pausePlayback()
	playing = false
	if alive(targetMesh) and selectedClip and selectedClip.kind == "imported" then
		playhead = targetMesh.AnimationTime or playhead
		targetMesh.AnimationSpeed = 0
	end
	status = "Paused"
end

local function uniqueClipName(baseName)
	baseName = tostring(baseName or "Animation"):gsub("^%s+", ""):gsub("%s+$", "")
	if baseName == "" then
		baseName = "Animation"
	end
	local name = baseName
	local suffix = 2
	while targetMesh:FindFirstChild(name) do
		name = baseName .. tostring(suffix)
		suffix += 1
	end
	return name
end

local function createClip(name, length)
	if not alive(targetMesh) or #meshBones() == 0 then
		status = "Select a skinned MeshPart before creating a clip."
		return
	end
	local animation = Instance.new("Animation")
	animation.Name = uniqueClipName(name)
	animation.AnimationId = "kinemium://" .. animation.Name
	animation.Length = math.max(0.001, tonumber(length) or 1)
	animation.Looped = looped
	animation.Parent = targetMesh
	animation:SetKeyframe(0, snapshotPose())
	refreshClips({ animation = animation })
	playhead = 0
	selectedKeyTime = 0
	selectedKeyBone = selectedBone
	status = `Created {animation.Name} with a bind-pose keyframe.`
end

local function recordKeyframe()
	if not selectedClip or selectedClip.kind ~= "custom" then
		status = "Create or select an editable clip first."
		return
	end

	playhead = snapTime(playhead)

	if alive(selectedBone) and selectedClip.animation.SetBoneKeyframe then
		selectedClip.animation:SetBoneKeyframe(playhead, selectedBone.Name, selectedBone.Transform or CFrame.new())
		selectedKeyBone = selectedBone
	else
		selectedClip.animation:SetKeyframe(playhead, snapshotPose())
		selectedKeyBone = nil
	end

	selectedKeyTime = playhead

	status = string.format(
		"Waypoint added at %s%s",
		formatFrameTime(playhead),
		selectedKeyBone and (" for " .. selectedKeyBone.Name) or ""
	)
end

local function deleteKeyframe()
	if not selectedClip or selectedClip.kind ~= "custom" then
		status = "Imported keyframes are read-only."
		return
	end

	local time = selectedKeyTime or playhead
	local tolerance = math.max(1 / FRAME_RATE, clipLength(selectedClip) / 1000)

	local removed = false
	if alive(selectedKeyBone) and selectedClip.animation.RemoveBoneKeyframe then
		removed = selectedClip.animation:RemoveBoneKeyframe(time, selectedKeyBone.Name, tolerance)
	else
		removed = selectedClip.animation:RemoveKeyframe(time, tolerance)
	end

	if removed then
		playhead = time
		selectedKeyTime = nil
		selectedKeyBone = nil

		applyCustomPose(selectedClip, playhead)

		status = string.format("Deleted waypoint at %s", formatFrameTime(time))
	else
		status = "Select a keyframe first."
	end
end

local function text(rect, value, color, size, dt)
	Immco.Text({
		x = rect.x,
		y = rect.y,
		text = value,
		Color = color or theme.TextColor,
		TextSize = size or 14,
		theme = theme,
		engine_window = renderer.Window,
	}, dt)
end

local function drawDiamond(x, y, color, dt)
	text({
		x = x - 6,
		y = y - 9,
	}, "◆", color, 15, dt)
end

local function button(rect, label, callback, dt, active, disabled)
	Immco.TextButton({
		x = rect.x,
		y = rect.y,
		width = rect.width,
		height = rect.height,
		text = label,
		Color = active and theme.AccentColor
			or (renderer:isMouseInRect(rect) and not disabled and theme.ThirdColor or theme.SecondaryColor),
		TextColor = disabled and theme.SecondaryTextColor or theme.TextColor,
		BgVisible = true,
		theme = theme,
		engine_window = renderer.Window,
	}, dt)
	if not disabled and renderer:HasClicked(rect) then
		callback()
	end
end

local function field(id, initial, rect, dt)
	return Immco.TextInput({
		x = rect.x,
		y = rect.y,
		width = rect.width,
		height = rect.height,
		text = initial,
		RetainedStorage = retained,
		id = id,
		renderer = renderer,
		engine_window = renderer.Window,
		theme = theme,
		Color = theme.BgColor,
		TextColor = theme.TextColor,
	}, dt)
end

local function applyTransform(values)
	if not alive(selectedBone) then
		status = "Select a bone first."
		return
	end
	local numeric = {}
	for index, value in ipairs(values) do
		numeric[index] = tonumber(value)
		if numeric[index] == nil then
			status = "Transform fields must contain numbers."
			return
		end
	end
	pausePlayback()
	targetMesh:StopAnimation()
	selectedBone.Transform = CFrame.new(numeric[1], numeric[2], numeric[3])
		* CFrame.Angles(math.rad(numeric[4]), math.rad(numeric[5]), math.rad(numeric[6]))
	if selectedClip and selectedClip.kind == "custom" and selectedKeyTime ~= nil then
		selectedClip.animation:SetBoneKeyframe(selectedKeyTime, selectedBone.Name, selectedBone.Transform)
		selectedKeyBone = selectedBone
	end
	status = `Posed {selectedBone.Name}`
end

local function normalAxis(normalId)
	local name = normalId and normalId.Name
	if name == "Right" then
		return Vector3.new(1, 0, 0)
	elseif name == "Top" then
		return Vector3.new(0, 1, 0)
	end
	return Vector3.new(0, 0, 1)
end

local function boneWorldCFrame(bone)
	if not alive(bone) or not alive(targetMesh) then
		return CFrame.new()
	end
	local localTransform = (bone.CFrame or CFrame.new()) * (bone.Transform or CFrame.new())
	if bone.Parent and bone.Parent.ClassName == "Bone" then
		return boneWorldCFrame(bone.Parent) * localTransform
	end
	return targetMesh.CFrame * localTransform
end

local function boneTransformFromWorld(bone, worldCFrame)
	local parentWorld = targetMesh.CFrame
	if bone.Parent and bone.Parent.ClassName == "Bone" then
		parentWorld = boneWorldCFrame(bone.Parent)
	end
	return (bone.CFrame or CFrame.new()):Inverse() * parentWorld:Inverse() * worldCFrame
end

local function selectedWaypointHasBone()
	if
		not selectedClip
		or selectedClip.kind ~= "custom"
		or selectedKeyTime == nil
		or not alive(selectedBone)
	then
		return false
	end
	local keyframe = selectedClip.animation:GetKeyframeAt(selectedKeyTime, 1 / FRAME_RATE / 2)
	local pose = keyframePose(keyframe)
	return type(pose) == "table" and pose[selectedBone.Name] ~= nil
end

local function refreshBoneGizmo()
	if not visible or not selectedWaypointHasBone() or gizmoMode == nil then
		boneHandles.Adornee = nil
		return
	end
	boneHandles.Style = gizmoMode == "Rotate" and Enum.HandlesStyle.Rotation or Enum.HandlesStyle.Movement
	boneHandles.Adornee = boneGizmoProxy
	if not gizmoDragState then
		boneGizmoProxy.CFrame = boneWorldCFrame(selectedBone)
	end
end

boneHandles.MouseButton1Down:Connect(function()
	if not selectedWaypointHasBone() then
		return
	end
	playing = false
	gizmoDragState = {
		bone = selectedBone,
		world = boneWorldCFrame(selectedBone),
		time = selectedKeyTime,
	}
	boneGizmoProxy.CFrame = gizmoDragState.world
	game.Stop3DInput = true
end)

boneHandles.MouseDrag:Connect(function(normalId, delta)
	local state = gizmoDragState
	if not state or state.bone ~= selectedBone or not alive(state.bone) then
		return
	end
	local axis = normalAxis(normalId)
	local desiredWorld
	if gizmoMode == "Rotate" then
		desiredWorld = state.world * CFrame.fromAxisAngle(axis, delta)
	else
		local worldAxis = state.world:VectorToWorldSpace(axis)
		desiredWorld = state.world:WithPosition(state.world.Position + worldAxis * delta)
	end
	state.bone.Transform = boneTransformFromWorld(state.bone, desiredWorld)
	boneGizmoProxy.CFrame = desiredWorld
	selectedClip.animation:SetBoneKeyframe(state.time, state.bone.Name, state.bone.Transform)
	selectedKeyBone = state.bone
	syncPoseFields()
end)

boneHandles.MouseButton1Up:Connect(function()
	if gizmoDragState then
		status = `Updated {gizmoDragState.bone.Name} at {formatFrameTime(gizmoDragState.time)}`
	end
	gizmoDragState = nil
	game.Stop3DInput = false
	refreshBoneGizmo()
end)

ishared.StudioSystem:Connect(function(route)
	if route == "toggle_animator" then
		visible = not visible
		if visible then
			useSelection()
		else
			boneHandles.Adornee = nil
			gizmoDragState = nil
			timelineKeyDrag = nil
			game.Stop3DInput = false
		end
	end
end)

renderer.Pool.new("2da", function(lib)
	if not visible then
		return
	end

	local dt = lib.dt
	theme = StudioThemeService.SelectedTheme

	AnimatorDock.Size = theme.OutputCoordinates.Size
	AnimatorDock.Position = theme.OutputCoordinates.Position

	local position = AnimatorDock.AbsolutePosition
	local size = AnimatorDock.AbsoluteSize

	if not position or not size then
		return
	end

	if targetMesh and not alive(targetMesh) then
		setTarget(nil)
	end

	if playing and selectedClip and alive(targetMesh) then
		local length = clipLength(selectedClip)

		if selectedClip.kind == "custom" then
			playhead += dt * speed

			if playhead > length then
				if looped then
					playhead %= length
				else
					playhead = length
					playing = false
				end
			end

			applyCustomPose(selectedClip, playhead)
		else
			playhead = math.clamp(targetMesh.AnimationTime or playhead, 0, length)

			if not looped and playhead >= length then
				pausePlayback()
			end
		end
	end

	refreshBoneGizmo()

	Immco.Widget({
		x = position.X,
		y = position.Y + 5,
		width = size.X,
		height = size.Y,

		title = status ~= "" and `Animator — {status}` or "Animator",

		theme = theme,
		engine_window = renderer.Window,
		renderer = renderer,

		RetainedStorage = retained,
		id = "animator-widget",

		callback = function(params)
			local padding = 8

			local x = params.x + padding
			local y = params.y + padding

			local width = params.width - padding * 2
			local height = params.height - padding * 2

			------------------------------------------------------------
			-- CLIP TOOLBAR
			------------------------------------------------------------

			local rowHeight = 32
			local gap = 6

			local useWidth = 96
			local nameWidth = 110
			local lengthWidth = 58
			local newWidth = 54
			local closeWidth = 56

			local closeX = x + width - closeWidth
			local newX = closeX - gap - newWidth
			local lengthX = newX - gap - lengthWidth
			local nameX = lengthX - gap - nameWidth

			local dropdownX = x + useWidth + gap

			local dropdownWidth = math.max(150, nameX - gap - dropdownX)

			button({
				x = x,
				y = y,
				width = useWidth,
				height = rowHeight,
			}, "Use Selected", useSelection, dt)

			local options = {}

			for index, entry in ipairs(clips) do
				options[index] = {
					Text = (entry.kind == "custom" and "Editable: " or "Imported: ") .. entry.name,

					Value = index,
				}
			end

			Immco.Dropdown({
				RetainedStorage = retained,
				id = "animator-clips",

				renderer = renderer,
				window = renderer.Window,

				theme = theme,

				x = dropdownX,
				y = y,

				width = dropdownWidth,
				height = rowHeight,

				Options = options,

				InitialSelected = selectedClip and (table.find(clips, selectedClip) or 0) or 0,

				OptionHeight = 26,
				MaxVisibleOptions = 8,

				OnChanged = function(_, index)
					playing = false
					selectedKeyTime = nil
					selectedKeyBone = nil

					selectedClip = clips[index]
					playhead = 0

					scrub(0)
				end,
			}, dt)

			local clipName = field("animator-new-clip-name", "Animation", {
				x = nameX,
				y = y,
				width = nameWidth,
				height = rowHeight,
			}, dt)

			local clipDuration = field("animator-new-clip-length", "1", {
				x = lengthX,
				y = y,
				width = lengthWidth,
				height = rowHeight,
			}, dt)

			button(
				{
					x = newX,
					y = y,
					width = newWidth,
					height = rowHeight,
				},
				"New",
				function()
					createClip(clipName, clipDuration)
				end,
				dt,
				false,
				not alive(targetMesh)
			)

			button(
				{
					x = closeX,
					y = y,
					width = closeWidth,
					height = rowHeight,
				},
				"Close",
				function()
					visible = false
					pausePlayback()
					boneHandles.Adornee = nil
					game.Stop3DInput = false
				end,
				dt
			)

			------------------------------------------------------------
			-- PLAYBACK BAR
			------------------------------------------------------------

			local controlsY = y + rowHeight + gap

			local controlX = x

			button(
				{
					x = controlX,
					y = controlsY,
					width = 36,
					height = rowHeight,
				},
				"|<",
				function()
					playing = false
					selectedKeyTime = nil
					selectedKeyBone = nil
					scrub(0)
				end,
				dt,
				false,
				not selectedClip
			)

			controlX += 42

			button(
				{
					x = controlX,
					y = controlsY,
					width = 36,
					height = rowHeight,
				},
				"<",
				function()
					playing = false
					selectedKeyTime = nil
					selectedKeyBone = nil
					scrub(snapTime(playhead - 1 / FRAME_RATE))
				end,
				dt,
				false,
				not selectedClip
			)

			controlX += 42

			button(
				{
					x = controlX,
					y = controlsY,
					width = 64,
					height = rowHeight,
				},
				playing and "Pause" or "Play",
				function()
					if playing then
						pausePlayback()
					else
						selectedKeyTime = nil
						selectedKeyBone = nil
						playSelected()
					end
				end,
				dt,
				playing,
				not selectedClip
			)

			controlX += 70

			button(
				{
					x = controlX,
					y = controlsY,
					width = 36,
					height = rowHeight,
				},
				">",
				function()
					playing = false
					selectedKeyTime = nil
					selectedKeyBone = nil
					scrub(snapTime(playhead + 1 / FRAME_RATE))
				end,
				dt,
				false,
				not selectedClip
			)

			controlX += 42

			button(
				{
					x = controlX,
					y = controlsY,
					width = 36,
					height = rowHeight,
				},
				">|",
				function()
					playing = false
					selectedKeyTime = nil
					selectedKeyBone = nil
					scrub(clipLength(selectedClip))
				end,
				dt,
				false,
				not selectedClip
			)

			controlX += 42

			button(
				{
					x = controlX,
					y = controlsY,
					width = 54,
					height = rowHeight,
				},
				"Stop",
				function()
					selectedKeyTime = nil
					selectedKeyBone = nil
					stopPlayback(true)
					status = "Stopped"
				end,
				dt,
				false,
				not selectedClip
			)

			controlX += 60

			button(
				{
					x = controlX,
					y = controlsY,
					width = 76,
					height = rowHeight,
				},
				looped and "Loop On" or "Loop Off",
				function()
					looped = not looped

					if selectedClip and selectedClip.kind == "custom" then
						selectedClip.animation.Looped = looped
					end

					if alive(targetMesh) then
						targetMesh.LoopAnimation = looped
					end
				end,
				dt,
				looped
			)

			controlX += 82

			button({
				x = controlX,
				y = controlsY,
				width = 88,
				height = rowHeight,
			}, "+ Waypoint", recordKeyframe, dt, false, not selectedClip or selectedClip.kind ~= "custom")

			controlX += 94

			button({
				x = controlX,
				y = controlsY,
				width = 62,
				height = rowHeight,
			}, "Delete", deleteKeyframe, dt, false, not selectedClip or selectedClip.kind ~= "custom")

			controlX += 68

			local gizmoDisabled = not selectedWaypointHasBone()
			button({
				x = controlX,
				y = controlsY,
				width = 54,
				height = rowHeight,
			}, "Move", function()
				gizmoMode = gizmoMode == "Move" and nil or "Move"
				refreshBoneGizmo()
			end, dt, gizmoMode == "Move" and not gizmoDisabled, gizmoDisabled)

			controlX += 60

			button({
				x = controlX,
				y = controlsY,
				width = 58,
				height = rowHeight,
			}, "Rotate", function()
				gizmoMode = gizmoMode == "Rotate" and nil or "Rotate"
				refreshBoneGizmo()
			end, dt, gizmoMode == "Rotate" and not gizmoDisabled, gizmoDisabled)

			controlX += 64

			local speedText = field("animator-speed", "1", {
				x = controlX,
				y = controlsY,
				width = 48,
				height = rowHeight,
			}, dt)

			local newSpeed = tonumber(speedText)

			if newSpeed then
				newSpeed = math.clamp(newSpeed, 0, 8)

				if newSpeed ~= speed then
					speed = newSpeed

					if playing and alive(targetMesh) and selectedClip and selectedClip.kind == "imported" then
						targetMesh.AnimationSpeed = speed
					end
				end
			end

			local timeText =
				string.format("%s / %s", formatFrameTime(playhead), formatFrameTime(clipLength(selectedClip)))

			text({
				x = x + width - 150,
				y = controlsY + 8,
			}, timeText, theme.SecondaryTextColor, 13, dt)

			------------------------------------------------------------
			-- TIMELINE / DOPE SHEET
			------------------------------------------------------------

			local timelineTop = controlsY + rowHeight + gap

			local footerHeight = 22

			local timelineHeight = height - (timelineTop - y) - footerHeight

			if timelineHeight < 60 then
				return
			end

			local trackWidth = math.clamp(math.floor(width * 0.22), 180, 260)

			local scrollbarReserve = 12

			local timeArea = {
				x = x + trackWidth,
				y = timelineTop,

				width = math.max(1, width - trackWidth - scrollbarReserve),

				height = timelineHeight,
			}

			local rulerRect = {
				x = timeArea.x,
				y = timeArea.y,
				width = timeArea.width,
				height = RULER_HEIGHT,
			}

			local rowsY = timelineTop + RULER_HEIGHT
			local rowsHeight = timelineHeight - RULER_HEIGHT

			local length = clipLength(selectedClip)
			local bones = meshBones()
			local keyframes = clipKeyframes(selectedClip)

			------------------------------------------------------------
			-- TRACK HEADER
			------------------------------------------------------------

			Argon:DrawRectangle(renderer.Window, {
				x = x,
				y = timelineTop,
				width = trackWidth,
				height = RULER_HEIGHT,

				Color = theme.SecondaryColor,
			})

			text({
				x = x + 8,
				y = timelineTop + 7,
			}, `Tracks ({#bones})`, theme.SecondaryTextColor, 13, dt)

			------------------------------------------------------------
			-- RULER BACKGROUND
			------------------------------------------------------------

			Argon:DrawRectangle(renderer.Window, {
				x = rulerRect.x,
				y = rulerRect.y,
				width = rulerRect.width,
				height = rulerRect.height,

				Color = theme.SecondaryColor,
			})

			local majorStep = timelineMajorStep(length, rulerRect.width)

			local minorStep = majorStep / 4

			local minorCount = math.ceil(length / math.max(minorStep, 0.00001))

			for tickIndex = 0, minorCount do
				local tickTime = tickIndex * minorStep

				if tickTime > length + 0.0001 then
					break
				end

				local tickX = timelineX(tickTime, rulerRect, length)

				local major = tickIndex % 4 == 0

				Argon:DrawRectangle(renderer.Window, {
					x = tickX,
					y = rulerRect.y + (major and 12 or 18),

					width = 1,

					height = major and 16 or 10,

					Color = major and theme.SecondaryTextColor or theme.ThirdColor,
				})

				if major then
					text({
						x = tickX + 3,
						y = rulerRect.y + 1,
					}, formatFrameTime(tickTime), theme.SecondaryTextColor, 11, dt)
				end
			end

			------------------------------------------------------------
			-- TRACKS + KEYFRAMES
			------------------------------------------------------------

			local rowCount = #bones + 1

			local contentHeight = math.max(rowsHeight, rowCount * ROW_HEIGHT)

			local hoveredKey = nil

			Immco.Scroller({
				id = "animator-dope-sheet",

				x = x,
				y = rowsY,

				width = width,
				height = rowsHeight,

				ViewHeight = rowsHeight,
				ContentHeight = contentHeight,

				ScrollSpeed = 38,
				ScrollLerpSpeed = 20,

				renderer = renderer,
				window = renderer.Window,

				theme = theme,
				RetainedStorage = retained,

				callback = function(scroll)
					local contentY = scroll.y

					local viewTop = rowsY
					local viewBottom = rowsY + rowsHeight

					----------------------------------------------------
					-- ROW BACKGROUNDS / LABELS
					----------------------------------------------------

					for rowIndex = 1, rowCount do
						local rowY = contentY + (rowIndex - 1) * ROW_HEIGHT

						if rowY + ROW_HEIGHT >= viewTop and rowY <= viewBottom then
							local bone = rowIndex > 1 and bones[rowIndex - 1] or nil

							local selected = bone ~= nil and bone == selectedBone

							local rowColor

							if selected then
								rowColor = theme.SecondaryColor
							elseif rowIndex % 2 == 0 then
								rowColor = theme.AlternatingColor2 or theme.ThirdColor
							else
								rowColor = theme.AlternatingColor1 or theme.BgColor
							end

							Argon:DrawRectangle(renderer.Window, {
								x = x,
								y = rowY,

								width = width - scrollbarReserve,

								height = ROW_HEIGHT,

								Color = rowColor,
							})

							Argon:DrawRectangle(renderer.Window, {
								x = x,
								y = rowY + ROW_HEIGHT - 1,

								width = width - scrollbarReserve,

								height = 1,

								Color = theme.ThirdColor,
							})

							if rowIndex == 1 then
								text({
									x = x + 8,
									y = rowY + 6,
								}, "◆ Summary", theme.TextColor, 12, dt)
							else
								local depth = 0
								local parent = bone.Parent

								while parent and parent ~= targetMesh do
									depth += 1
									parent = parent.Parent
								end

								depth = math.min(depth, 8)

								text({
									x = x + 8 + depth * 12,

									y = rowY + 6,
								}, bone.Name, selected and theme.TextColor or theme.SecondaryTextColor, 12, dt)

								local labelRect = {
									x = x,
									y = rowY,
									width = trackWidth,
									height = ROW_HEIGHT,
								}

								if renderer:HasClicked(labelRect) then
									selectBone(bone)
								end
							end
						end
					end

					----------------------------------------------------
					-- VERTICAL TIMELINE GRID
					----------------------------------------------------

					for tickIndex = 0, minorCount do
						local tickTime = tickIndex * minorStep

						if tickTime > length + 0.0001 then
							break
						end

						local tickX = timelineX(tickTime, rulerRect, length)

						local major = tickIndex % 4 == 0

						Argon:DrawRectangle(renderer.Window, {
							x = tickX,
							y = rowsY,

							width = 1,
							height = rowsHeight,

							Color = major and theme.SecondaryColor or theme.ThirdColor,
						})
					end

					----------------------------------------------------
					-- KEYFRAME RENDERER
					----------------------------------------------------

					local function renderKeyframe(keyframe, rowY, bone)
						if bone and not keyframeHasBone(keyframe, bone) then
							return
						end

						local time = keyframeTime(keyframe)

						local keyX = timelineX(time, rulerRect, length)

						local keyY = rowY + ROW_HEIGHT / 2

						local selected = selectedKeyTime ~= nil
							and math.abs(selectedKeyTime - time) < 0.00001
							and (bone == nil or selectedKeyBone == bone)

						drawDiamond(keyX, keyY, selected and theme.AccentColor or theme.TextColor, dt)

						local hitRect = {
							x = keyX - 8,
							y = rowY + 3,

							width = 16,
							height = ROW_HEIGHT - 6,
						}

						if renderer:isMouseInRect(hitRect) then
							hoveredKey = {
								time = time,
								bone = bone,
								rect = hitRect,
							}
						end
					end

					----------------------------------------------------
					-- SUMMARY KEYS
					----------------------------------------------------

					local summaryY = contentY

					if summaryY + ROW_HEIGHT >= viewTop and summaryY <= viewBottom then
						for _, keyframe in ipairs(keyframes) do
							renderKeyframe(keyframe, summaryY, nil)
						end
					end

					----------------------------------------------------
					-- BONE TRACK KEYS
					----------------------------------------------------

					for boneIndex, bone in ipairs(bones) do
						local rowY = contentY + boneIndex * ROW_HEIGHT

						if rowY + ROW_HEIGHT >= viewTop and rowY <= viewBottom then
							for _, keyframe in ipairs(keyframes) do
								renderKeyframe(keyframe, rowY, bone)
							end
						end
					end
				end,
			}, dt)

			------------------------------------------------------------
			-- TRACK / TIMELINE DIVIDER
			------------------------------------------------------------

			Argon:DrawRectangle(renderer.Window, {
				x = timeArea.x - 1,
				y = timelineTop,

				width = 1,
				height = timelineHeight,

				Color = theme.SecondaryTextColor,
			})

			------------------------------------------------------------
			-- PLAYHEAD
			------------------------------------------------------------

			local playX = timelineX(playhead, rulerRect, length)

			Argon:DrawRectangle(renderer.Window, {
				x = playX - 1,
				y = timelineTop,

				width = 2,
				height = timelineHeight,

				Color = theme.AccentColor,
			})

			drawDiamond(playX, rulerRect.y + 7, theme.AccentColor, dt)

			------------------------------------------------------------
			-- KEYFRAME CLICKING / SCRUBBING
			------------------------------------------------------------

			local interactionRect = {
				x = rulerRect.x,
				y = rulerRect.y,
				width = rulerRect.width,
				height = timelineHeight,
			}
			local leftPressed = Argon:IsMouseButtonPressed(Argon.MouseButton.Left)
			local leftDown = Argon:IsMouseButtonDown(Argon.MouseButton.Left)
			local leftReleased = Argon:IsMouseButtonReleased(Argon.MouseButton.Left)
			local mouse = Argon:GetMousePosition()

			if hoveredKey and leftPressed then
				playing = false
				selectedKeyTime = hoveredKey.time
				selectedKeyBone = hoveredKey.bone or selectedBone
				if hoveredKey.bone then
					selectBone(hoveredKey.bone)
				end
				scrub(hoveredKey.time)
				if selectedClip and selectedClip.kind == "custom" then
					timelineKeyDrag = {
						fromTime = hoveredKey.time,
						currentTime = hoveredKey.time,
						bone = hoveredKey.bone,
					}
					game.Stop3DInput = true
				end
			elseif timelineKeyDrag then
				if leftDown then
					local normalized = (mouse.X - rulerRect.x) / rulerRect.width
					timelineKeyDrag.currentTime = snapTime(normalized * length)
					playhead = timelineKeyDrag.currentTime
				elseif leftReleased or not leftDown then
					local drag = timelineKeyDrag
					timelineKeyDrag = nil
					local boneName = drag.bone and drag.bone.Name or nil
					if selectedClip.animation:MoveKeyframe(
						drag.fromTime,
						drag.currentTime,
						boneName,
						1 / FRAME_RATE / 2
					) then
						selectedKeyTime = drag.currentTime
						selectedKeyBone = drag.bone or selectedKeyBone
						scrub(drag.currentTime)
						status = string.format("Moved waypoint to %s", formatFrameTime(drag.currentTime))
					end
					game.Stop3DInput = false
				end
			elseif renderer:isMouseInRect(interactionRect) and leftDown and not hoveredKey then
				local normalized = (mouse.X - rulerRect.x) / rulerRect.width
				selectedKeyTime = nil
				selectedKeyBone = nil
				playing = false
				scrub(snapTime(normalized * length))
			end
		end,
	}, dt)
end)
