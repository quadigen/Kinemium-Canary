-- description: "Defines the position, orientation, and rendering settings used to view the world."

local Argon = require("@Argon")
local Vector3 = require("@Vector3")
local CFrame = require("@CFrame")
local Enum = require("@EnumMap")

_G.SecurityCapabilities = Enum.SecurityCapabilities.Internals

local DEFAULT_CFRAME = CFrame.new(Vector3.new(3, 3, 3), Vector3.new(0, 0, 0))
local WORLD_UP = Vector3.new(0, 1, 0)
local MAX_PITCH = math.rad(89)
local RIGHT_MOUSE_BUTTON = 3

local propTable = {
	FieldOfView = 70,
	CFrame = DEFAULT_CFRAME,
	Position = DEFAULT_CFRAME.Position,
	Roll = 0,
	Name = "Camera",
	CameraType = Enum.CameraType.Custom,
	CameraSubject = nil,
	Focus = CFrame.new(0, 0, 0),
	MoveSpeed = 10,
	MouseSensitivity = 0.003,
	OrbitDistance = 12,
	MinOrbitDistance = 2,
	MaxOrbitDistance = 128,
	FirstPersonOffset = Vector3.new(0, 0, 0),
	SubjectSmoothing = 8,
	FollowDistance = 12,
	FollowHeight = 4,
	FollowLookAhead = 0.15,
	FollowFocusOffset = Vector3.new(0, 2, 0),
	ShoulderOffset = Vector3.new(3, 2, 8),
	ShoulderFocusOffset = Vector3.new(0, 2, 0),
	TopDownHeight = 32,
	IsometricOffset = Vector3.new(1, 1, 1),
}

local function getModeName(cameraType)
	if type(cameraType) == "table" then
		return cameraType.Name
	end
	if type(cameraType) == "string" then
		return cameraType
	end
	return "Scriptable"
end

local function getCFramePosition(value)
	if type(value) == "table" and value.Position then
		return value.Position
	end
	return nil
end

local function getSubjectCFrame(subject)
	if type(subject) ~= "table" then
		return nil
	end

	local props = rawget(subject, "_props")
	if props then
		local primaryPart = props.PrimaryPart
		local primaryProps = type(primaryPart) == "table" and rawget(primaryPart, "_props") or nil
		local primaryCFrame = primaryProps and primaryProps.CFrame
		if getCFramePosition(primaryCFrame) then
			return primaryCFrame
		end

		local rootPart = props.RootPart
		local rootProps = type(rootPart) == "table" and rawget(rootPart, "_props") or nil
		local rootCFrame = rootProps and rootProps.CFrame
		if getCFramePosition(rootCFrame) then
			return rootCFrame
		end

		if getCFramePosition(props.CFrame) then
			return props.CFrame
		end
		if getCFramePosition(props.WorldPivot) then
			return props.WorldPivot
		end
		if props.Position then
			return CFrame.new(props.Position)
		end

		if props.ClassName == "Humanoid" and props.Parent then
			local parentProps = rawget(props.Parent, "_props")
			local parentPrimary = parentProps and parentProps.PrimaryPart
			local parentPrimaryProps = type(parentPrimary) == "table" and rawget(parentPrimary, "_props") or nil
			local parentPrimaryCFrame = parentPrimaryProps and parentPrimaryProps.CFrame
			if getCFramePosition(parentPrimaryCFrame) then
				return parentPrimaryCFrame
			end
		end
	end

	if getCFramePosition(subject.CFrame) then
		return subject.CFrame
	end
	if subject.Position then
		return CFrame.new(subject.Position)
	end
	return nil
end

local function getSubjectPosition(subject)
	local cframe = getSubjectCFrame(subject)
	return cframe and cframe.Position or nil
end

local function getSubjectVelocity(subject)
	if type(subject) ~= "table" then
		return Vector3.new(0, 0, 0)
	end

	local props = rawget(subject, "_props")
	if props then
		local velocity = props.AssemblyLinearVelocity or props.Velocity
		if velocity then
			return velocity
		end

		local rootPart = props.RootPart or props.PrimaryPart
		local rootProps = type(rootPart) == "table" and rawget(rootPart, "_props") or nil
		if rootProps then
			return rootProps.AssemblyLinearVelocity or rootProps.Velocity or Vector3.new(0, 0, 0)
		end
	end

	return Vector3.new(0, 0, 0)
end

local function clampDistance(instance, distance)
	local minimum = math.max(0.05, tonumber(instance.MinOrbitDistance) or 2)
	local maximum = math.max(minimum, tonumber(instance.MaxOrbitDistance) or 128)
	return math.clamp(distance, minimum, maximum)
end

local function getSmoothingAlpha(instance, delta)
	local smoothing = math.max(0, tonumber(instance.SubjectSmoothing) or 0)
	if smoothing == 0 then
		return 1
	end
	return 1 - math.exp(-smoothing * math.clamp(delta or 0, 0, 0.25))
end

local function readRotation(cframe)
	if not cframe or not cframe.GetYawPitchRoll then
		return 0, 0
	end
	local yaw, pitch = cframe:GetYawPitchRoll()
	return yaw, math.clamp(pitch, -MAX_PITCH, MAX_PITCH)
end

local function readOrbit(cframe, subjectPosition, fallbackDistance)
	local offset = cframe.Position - subjectPosition
	local distance = offset:Magnitude()
	if distance < 0.001 then
		distance = fallbackDistance
		offset = Vector3.new(0, 0, distance)
	end

	local pitch = math.asin(math.clamp(offset.Y / distance, -1, 1))
	local yaw = math.atan2(offset.X, offset.Z)
	return yaw, math.clamp(pitch, -MAX_PITCH, MAX_PITCH)
end

local function setCursorCaptured(state, window, captured)
	if state.cursorCaptured == captured or not window then
		return
	end
	state.cursorCaptured = captured
	if captured then
		Argon:DisableCursor(window)
	else
		Argon:EnableCursor(window)
	end
end

local function updateLookInput(instance, state, window, alwaysCaptured)
	local captured = alwaysCaptured or Argon:IsMouseButtonDown(RIGHT_MOUSE_BUTTON)
	setCursorCaptured(state, window, captured)
	if not captured then
		return
	end

	local mouseDelta = Argon:GetMouseDelta()
	local sensitivity = tonumber(instance.MouseSensitivity) or 0.003
	state.yaw = state.yaw - mouseDelta.x * sensitivity
	state.pitch = math.clamp(state.pitch - mouseDelta.y * sensitivity, -MAX_PITCH, MAX_PITCH)
end

local function writeCamera(instance, state, cframe, focusPosition)
	state.writing = true
	instance.CFrame = cframe
	instance.Position = cframe.Position
	instance.Focus = CFrame.new(focusPosition)
	state.writing = false
end

local function smoothSubjectCamera(instance, state, desiredPosition, desiredFocus, delta, up)
	local alpha = getSmoothingAlpha(instance, delta)
	state.position = state.position:Lerp(desiredPosition, alpha)
	state.focusPosition = state.focusPosition:Lerp(desiredFocus, alpha)
	writeCamera(
		instance,
		state,
		CFrame.lookAt(state.position, state.focusPosition, up or WORLD_UP),
		state.focusPosition
	)
end

local function updateDistanceProperty(instance, state, propertyName)
	local wheel = Argon:GetMouseWheelMove()
	if wheel == 0 then
		return
	end

	local current = tonumber(instance[propertyName]) or state.distance
	local distance = clampDistance(instance, current - wheel * math.max(1, current * 0.1))
	state.distance = distance
	state.writing = true
	instance[propertyName] = distance
	state.writing = false
end

local function initializeMode(instance, state, mode, subjectPosition)
	local cframe = instance.CFrame or DEFAULT_CFRAME
	state.mode = mode
	state.subject = instance.CameraSubject
	state.position = cframe.Position
	state.focusPosition = subjectPosition or cframe.Position + cframe:GetLookVector()

	if subjectPosition and (mode == "Orbital" or mode == "ThirdPerson" or mode == "Track") then
		state.yaw, state.pitch =
			readOrbit(cframe, subjectPosition, clampDistance(instance, tonumber(instance.OrbitDistance) or 12))
		state.distance = clampDistance(instance, tonumber(instance.OrbitDistance) or 12)
	else
		state.yaw, state.pitch = readRotation(cframe)
		state.distance = clampDistance(instance, tonumber(instance.OrbitDistance) or 12)
	end
end

local function updateCustom(instance, state, delta, window)
	updateLookInput(instance, state, window, false)

	local rotation = CFrame.fromEulerAnglesYXZ(state.yaw, -state.pitch, math.rad(tonumber(instance.Roll) or 0)).Rotation
	local cframe = CFrame.new(state.position):WithRotation(rotation)
	local forward = cframe:GetLookVector()
	local right = cframe:GetRightVector()
	local sideway = (Argon:IsKeyDown(7) and 1 or 0)
		- (Argon:IsKeyDown(4) and 1 or 0)
		+ (Argon:IsKeyDown(79) and 1 or 0)
		- (Argon:IsKeyDown(80) and 1 or 0)
	local forwardInput = (Argon:IsKeyDown(26) and 1 or 0)
		- (Argon:IsKeyDown(22) and 1 or 0)
		+ (Argon:IsKeyDown(82) and 1 or 0)
		- (Argon:IsKeyDown(81) and 1 or 0)
	local vertical = (Argon:IsKeyDown(44) and 1 or 0) - (Argon:IsKeyDown(225) and 1 or 0)
	local wheel = Argon:GetMouseWheelMove()
	local move = right * sideway + forward * (forwardInput + wheel * 2) + WORLD_UP * vertical
	state.position = state.position + move * (tonumber(instance.MoveSpeed) or 10) * math.max(delta or 0, 0)

	cframe = CFrame.new(state.position):WithRotation(rotation)
	writeCamera(instance, state, cframe, state.position + cframe:GetLookVector())
end

local function updateOrbit(instance, state, subjectPosition, window)
	updateLookInput(instance, state, window, false)

	local wheel = Argon:GetMouseWheelMove()
	if wheel ~= 0 then
		state.distance = clampDistance(instance, state.distance - wheel * math.max(1, state.distance * 0.1))
		state.writing = true
		instance.OrbitDistance = state.distance
		state.writing = false
	end

	local horizontal = math.cos(state.pitch) * state.distance
	local offset = Vector3.new(
		math.sin(state.yaw) * horizontal,
		math.sin(state.pitch) * state.distance,
		math.cos(state.yaw) * horizontal
	)
	writeCamera(instance, state, CFrame.lookAt(subjectPosition + offset, subjectPosition, WORLD_UP), subjectPosition)
end

local function updateFirstPerson(instance, state, subjectPosition, window)
	updateLookInput(instance, state, window, true)
	local position = subjectPosition + (instance.FirstPersonOffset or Vector3.new(0, 0, 0))
	local rotation = CFrame.fromEulerAnglesYXZ(state.yaw, state.pitch, math.rad(tonumber(instance.Roll) or 0)).Rotation
	local cframe = CFrame.new(position):WithRotation(rotation)
	writeCamera(instance, state, cframe, position + cframe:GetLookVector())
end

local function updateWatch(instance, state, subjectPosition, window)
	setCursorCaptured(state, window, false)
	local position = instance.CFrame.Position
	if (position - subjectPosition):Magnitude() < 0.001 then
		position = subjectPosition + Vector3.new(0, 0, clampDistance(instance, state.distance))
	end
	writeCamera(instance, state, CFrame.lookAt(position, subjectPosition, WORLD_UP), subjectPosition)
end

local function updateFollow(instance, state, subject, subjectCFrame, delta, window)
	setCursorCaptured(state, window, false)
	updateDistanceProperty(instance, state, "FollowDistance")

	local velocity = getSubjectVelocity(subject)
	local lookAhead = math.max(0, tonumber(instance.FollowLookAhead) or 0)
	local focusOffset = instance.FollowFocusOffset or Vector3.new(0, 2, 0)
	local focus = subjectCFrame * focusOffset + velocity * lookAhead
	local distance = clampDistance(instance, tonumber(instance.FollowDistance) or 12)
	local height = tonumber(instance.FollowHeight) or 4
	local desiredPosition = focus - subjectCFrame:GetLookVector() * distance + WORLD_UP * height
	smoothSubjectCamera(instance, state, desiredPosition, focus, delta)
end

local function updateShoulder(instance, state, subjectCFrame, delta, window)
	setCursorCaptured(state, window, false)
	local cameraOffset = instance.ShoulderOffset or Vector3.new(3, 2, 8)
	local focusOffset = instance.ShoulderFocusOffset or Vector3.new(0, 2, 0)
	local desiredPosition = subjectCFrame * cameraOffset
	local focus = subjectCFrame * focusOffset
	smoothSubjectCamera(instance, state, desiredPosition, focus, delta)
end

local function updateTopDown(instance, state, subjectCFrame, delta, window)
	setCursorCaptured(state, window, false)
	updateDistanceProperty(instance, state, "TopDownHeight")

	local focus = subjectCFrame.Position
	local height = clampDistance(instance, tonumber(instance.TopDownHeight) or 32)
	local desiredPosition = focus + WORLD_UP * height
	local cameraUp = subjectCFrame:GetLookVector()
	cameraUp = Vector3.new(cameraUp.X, 0, cameraUp.Z)
	if cameraUp:Magnitude() < 0.001 then
		cameraUp = Vector3.new(0, 0, -1)
	else
		cameraUp = cameraUp:Unit()
	end
	smoothSubjectCamera(instance, state, desiredPosition, focus, delta, cameraUp)
end

local function updateIsometric(instance, state, subjectPosition, delta, window)
	setCursorCaptured(state, window, false)
	updateDistanceProperty(instance, state, "OrbitDistance")

	local offset = instance.IsometricOffset or Vector3.new(1, 1, 1)
	if offset:Magnitude() < 0.001 then
		offset = Vector3.new(1, 1, 1)
	end
	local distance = clampDistance(instance, tonumber(instance.OrbitDistance) or 12)
	local desiredPosition = subjectPosition + offset:Unit() * distance
	smoothSubjectCamera(instance, state, desiredPosition, subjectPosition, delta)
end

return {
	class = "Camera",
	singleton = true,
	callback = function(instance, renderer)
		instance:SetProperties(propTable)

		local state = {
			mode = nil,
			subject = nil,
			position = DEFAULT_CFRAME.Position,
			focusPosition = propTable.Focus.Position,
			yaw = 0,
			pitch = 0,
			distance = propTable.OrbitDistance,
			cursorCaptured = false,
			writing = false,
		}
		rawset(instance, "_cameraState", state)

		instance:_SetPropertyHandler("CFrame", function(value)
			if state.writing or not value or not value.Position then
				return
			end
			state.position = value.Position
			local mode = getModeName(instance.CameraType)
			local subjectPosition = getSubjectPosition(instance.CameraSubject)
			if subjectPosition and (mode == "Orbital" or mode == "ThirdPerson" or mode == "Track") then
				state.yaw, state.pitch =
					readOrbit(value, subjectPosition, clampDistance(instance, tonumber(instance.OrbitDistance) or 12))
			else
				state.yaw, state.pitch = readRotation(value)
			end
			rawget(instance, "_props").Position = value.Position
		end)

		instance:_SetPropertyHandler("Position", function(value)
			if state.writing or not value then
				return
			end
			state.position = value
			local cframe = instance.CFrame
			if cframe and cframe.WithPosition then
				rawget(instance, "_props").CFrame = cframe:WithPosition(value)
			end
		end)

		instance:_SetPropertyHandler("CameraType", function()
			state.mode = nil
		end)
		instance:_SetPropertyHandler("CameraSubject", function()
			state.mode = nil
		end)
		instance:_SetPropertyHandler("OrbitDistance", function(value)
			if not state.writing then
				state.distance = clampDistance(instance, tonumber(value) or propTable.OrbitDistance)
			end
		end)

		rawset(instance, "_UpdateCamera", function(delta)
			local mode = getModeName(instance.CameraType)
			local subjectCFrame = getSubjectCFrame(instance.CameraSubject)
			local subjectPosition = subjectCFrame and subjectCFrame.Position or nil
			if state.mode ~= mode or state.subject ~= instance.CameraSubject then
				initializeMode(instance, state, mode, subjectPosition)
			end

			local window = renderer and renderer.Window
			if mode == "Scriptable" or mode == "Fixed" then
				setCursorCaptured(state, window, false)
				return
			elseif mode == "Custom" then
				updateCustom(instance, state, delta, window)
			elseif mode == "FirstPerson" or mode == "Attach" then
				if subjectPosition then
					updateFirstPerson(instance, state, subjectPosition, window)
				else
					setCursorCaptured(state, window, false)
				end
			elseif mode == "Watch" then
				if subjectPosition then
					updateWatch(instance, state, subjectPosition, window)
				else
					setCursorCaptured(state, window, false)
				end
			elseif mode == "Follow" then
				if subjectCFrame then
					updateFollow(instance, state, instance.CameraSubject, subjectCFrame, delta, window)
				else
					setCursorCaptured(state, window, false)
				end
			elseif mode == "Shoulder" then
				if subjectCFrame then
					updateShoulder(instance, state, subjectCFrame, delta, window)
				else
					setCursorCaptured(state, window, false)
				end
			elseif mode == "TopDown" then
				if subjectCFrame then
					updateTopDown(instance, state, subjectCFrame, delta, window)
				else
					setCursorCaptured(state, window, false)
				end
			elseif mode == "Isometric" then
				if subjectPosition then
					updateIsometric(instance, state, subjectPosition, delta, window)
				else
					setCursorCaptured(state, window, false)
				end
			elseif subjectPosition then
				updateOrbit(instance, state, subjectPosition, window)
			else
				setCursorCaptured(state, window, false)
			end
		end)

		rawset(instance, "SetMoveSpeed", function(_, speed)
			instance.MoveSpeed = speed
		end)
		rawset(instance, "SetMouseSensitivity", function(_, sensitivity)
			instance.MouseSensitivity = sensitivity
		end)

		return instance
	end,
	inherit = function(tble)
		for prop, val in pairs(propTable) do
			tble[prop] = val
		end
	end,
}
