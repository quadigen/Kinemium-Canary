local logic = {}

local Argon = require("@Argon")
local Enum = require("@EnumMap")
local MouseCursor = require("@Kinemium.MouseCursor")
local signal = require("@Kinemium.signal")

local LEFT_MOUSE_BUTTON = Argon.MouseButton.Left
local RIGHT_MOUSE_BUTTON = Argon.MouseButton.Right
local buttonStates = setmetatable({}, { __mode = "k" })

local function getButtonState(object)
	local state = buttonStates[object]
	if not state then
		state = {
			leftCaptured = false,
			rightCaptured = false,
		}
		buttonStates[object] = state
	end
	return state
end

function logic:Step(object, _window, callbackHover, callbackLeave)
	local hovered = object.MouseIsInObject == true
	local state = getButtonState(object)

	if hovered then
		if object.ChangeCursorOnHover then
			--MouseCursor.request(Enum.KinemiumMouseCursor.MOUSE_CURSOR_POINTING_HAND.Value)
		end

		if object.AutoButtonColor then
			object.BackgroundTransparency = 0.5
		end

		if callbackHover then
			callbackHover()
		end
	else
		if object.ChangeCursorOnHover then
			--MouseCursor.request(Enum.KinemiumMouseCursor.MOUSE_CURSOR_DEFAULT.Value)
		end

		if object.AutoButtonColor then
			object.BackgroundTransparency = 0
		end

		if callbackLeave then
			callbackLeave()
		end
	end

	if hovered and Argon:IsMouseButtonPressed(LEFT_MOUSE_BUTTON) then
		state.leftCaptured = true
		object.MouseButton1Down:Fire()
	end
	if hovered and Argon:IsMouseButtonPressed(RIGHT_MOUSE_BUTTON) then
		state.rightCaptured = true
		object.MouseButton2Down:Fire()
	end

	if Argon:IsMouseButtonReleased(LEFT_MOUSE_BUTTON) and state.leftCaptured then
		state.leftCaptured = false
		object.MouseButton1Up:Fire()
		if hovered then
			object.MouseButton1Click:Fire()
			object.Activated:Fire()
		end
	end
	if Argon:IsMouseButtonReleased(RIGHT_MOUSE_BUTTON) and state.rightCaptured then
		state.rightCaptured = false
		object.MouseButton2Up:Fire()
		if hovered then
			object.MouseButton2Click:Fire()
		end
	end
end

function logic:SetupSignals(propTable)
	local MouseButton1Click = signal.new()
	local MouseButton2Click = signal.new()
	local MouseButton1Down = signal.new()
	local MouseButton1Up = signal.new()
	local MouseButton2Down = signal.new()
	local MouseButton2Up = signal.new()
	local Activated = signal.new()

	propTable.Activated = Activated
	propTable.MouseButton1Click = MouseButton1Click
	propTable.MouseButton2Click = MouseButton2Click
	propTable.MouseButton1Down = MouseButton1Down
	propTable.MouseButton1Up = MouseButton1Up
	propTable.MouseButton2Down = MouseButton2Down
	propTable.MouseButton2Up = MouseButton2Up
end

return logic
