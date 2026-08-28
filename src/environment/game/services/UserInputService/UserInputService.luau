local Instance = require("@Instance")
local signal = require("@Kinemium.signal")
local Argon = require("@Argon")
local Enum = require("@EnumMap")
local Vector2 = require("@Vector2")
local Vector3 = require("@Vector3")
local CFrame = require("@CFrame")

local UserInputService = Instance.new("UserInputService")
UserInputService._Intents = Enum.PluginIntents.Input

local ZERO2 = Vector2.new(0, 0)
local ZERO3 = Vector3.new(0, 0, 0)
local NONE_KEY = Enum.KeyCode.None or Enum.KeyCode.Unknown

local InputBegan = signal.new()
local InputChanged = signal.new()
local InputEnded = signal.new()
local LastInputTypeChanged = signal.new()
local JumpRequest = signal.new()
local TextBoxFocused = signal.new()
local TextBoxFocusReleased = signal.new()
local WindowFocused = signal.new()
local WindowFocusReleased = signal.new()
local MouseWheel = signal.new()
local TextInput = signal.new()
local GamepadConnected = signal.new()
local GamepadDisconnected = signal.new()
local DeviceAccelerationChanged = signal.new()
local DeviceGravityChanged = signal.new()
local DeviceRotationChanged = signal.new()
local PointerAction = signal.new()
local TouchStarted = signal.new()
local TouchMoved = signal.new()
local TouchEnded = signal.new()
local TouchTap = signal.new()
local TouchTapInWorld = signal.new()
local TouchLongPress = signal.new()
local TouchPan = signal.new()
local TouchPinch = signal.new()
local TouchRotate = signal.new()
local TouchSwipe = signal.new()

local state = {
	renderer = nil,
	datamodel = nil,
	rendererConnection = nil,
	focusConnection = nil,
	pressedKeys = {},
	pressedMouseButtons = {},
	virtualKeys = {},
	virtualMouseButtons = {},
	lastInputType = Enum.UserInputType.None,
	focusedTextBox = nil,
	windowFocused = true,
}

local keyBindings = {}
local keyBindingByName = {}
local keyBindingByValue = {}

local function addKeyBinding(name, scanCode)
	local keyCode = Enum.KeyCode[name]
	if not keyCode then
		return
	end
	local binding = {
		Name = name,
		ScanCode = scanCode,
		KeyCode = keyCode,
	}
	table.insert(keyBindings, binding)
	keyBindingByName[name] = binding
	if keyBindingByValue[keyCode.Value] == nil then
		keyBindingByValue[keyCode.Value] = binding
	end
end

for index = 0, 25 do
	addKeyBinding(string.char(string.byte("A") + index), 4 + index)
end

local digitNames = { "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Zero" }
for index, name in ipairs(digitNames) do
	addKeyBinding(name, 29 + index)
end

local fixedKeyScanCodes = {
	Return = 40,
	Escape = 41,
	Backspace = 42,
	Tab = 43,
	Space = 44,
	Minus = 45,
	Equals = 46,
	LeftBracket = 47,
	RightBracket = 48,
	Backslash = 49,
	Semicolon = 51,
	Quote = 52,
	Grave = 53,
	Comma = 54,
	Period = 55,
	Slash = 56,
	CapsLock = 57,
	F1 = 58,
	F2 = 59,
	F3 = 60,
	F4 = 61,
	F5 = 62,
	F6 = 63,
	F7 = 64,
	F8 = 65,
	F9 = 66,
	F10 = 67,
	F11 = 68,
	F12 = 69,
	PrintScreen = 70,
	ScrollLock = 71,
	Pause = 72,
	Insert = 73,
	Home = 74,
	PageUp = 75,
	Delete = 76,
	End = 77,
	PageDown = 78,
	Right = 79,
	Left = 80,
	Down = 81,
	Up = 82,
	NumLock = 83,
	Divide = 84,
	Multiply = 85,
	Subtract = 86,
	Add = 87,
	KeypadEnter = 88,
	OnePad = 89,
	TwoPad = 90,
	ThreePad = 91,
	FourPad = 92,
	FivePad = 93,
	SixPad = 94,
	SevenPad = 95,
	EightPad = 96,
	NinePad = 97,
	ZeroPad = 98,
	Decimal = 99,
	Apps = 101,
	KeypadEquals = 103,
	LeftControl = 224,
	LeftShift = 225,
	LeftAlt = 226,
	LeftSuper = 227,
	RightControl = 228,
	RightShift = 229,
	RightAlt = 230,
	RightSuper = 231,
}
for name, scanCode in pairs(fixedKeyScanCodes) do
	addKeyBinding(name, scanCode)
end

table.sort(keyBindings, function(a, b)
	return a.ScanCode < b.ScanCode
end)

local mouseTypeBySDLButton = {
	[1] = Enum.UserInputType.MouseButton1,
	[2] = Enum.UserInputType.MouseButton3,
	[3] = Enum.UserInputType.MouseButton2,
}

local function resolveKeyBinding(keyCode)
	if type(keyCode) == "table" then
		return keyBindingByName[keyCode.Name]
	elseif type(keyCode) == "string" then
		return keyBindingByName[keyCode]
	elseif type(keyCode) == "number" then
		return keyBindingByValue[keyCode] or { ScanCode = keyCode, KeyCode = NONE_KEY, Name = tostring(keyCode) }
	end
	return nil
end

local function resolveMouseButton(mouseButton)
	local name = type(mouseButton) == "table" and mouseButton.Name or nil
	if name == "MouseButton1" or name == "Left" then
		return 1, Enum.UserInputType.MouseButton1
	elseif name == "MouseButton2" or name == "Right" then
		return 3, Enum.UserInputType.MouseButton2
	elseif name == "MouseButton3" or name == "Middle" then
		return 2, Enum.UserInputType.MouseButton3
	elseif type(mouseButton) == "number" then
		local legacyToSDL = { [0] = 1, [1] = 3, [2] = 2 }
		local sdlButton = legacyToSDL[mouseButton] or mouseButton
		return sdlButton, mouseTypeBySDLButton[sdlButton]
	end
	return nil, nil
end

local function isModifierKeyDown(modifier)
	local name = type(modifier) == "table" and modifier.Name or tostring(modifier)
	if name == "Shift" then
		return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
	elseif name == "Ctrl" or name == "Control" then
		return UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
	elseif name == "Alt" then
		return UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt)
	elseif name == "Meta" then
		return UserInputService:IsKeyDown(Enum.KeyCode.LeftSuper) or UserInputService:IsKeyDown(Enum.KeyCode.RightSuper)
	end
	return false
end

local function newInputObject(userInputType, userInputState, keyCode, position, delta)
	local input = {
		__type = "InputObject",
		UserInputType = userInputType or Enum.UserInputType.None,
		UserInputState = userInputState or Enum.UserInputState.None,
		KeyCode = keyCode or NONE_KEY,
		Position = position or ZERO3,
		Delta = delta or ZERO3,
		Changed = signal.new(),
	}

	function input:IsModifierKeyDown(modifier)
		return isModifierKeyDown(modifier)
	end

	return input
end

local function setLastInputType(inputType)
	if not inputType or state.lastInputType == inputType then
		return
	end
	state.lastInputType = inputType
	UserInputService.LastInputType = inputType
	if
		inputType == Enum.UserInputType.Keyboard
		or inputType == Enum.UserInputType.MouseMovement
		or inputType == Enum.UserInputType.MouseButton1
		or inputType == Enum.UserInputType.MouseButton2
		or inputType == Enum.UserInputType.MouseButton3
		or inputType == Enum.UserInputType.MouseWheel
	then
		UserInputService.PreferredInput = Enum.PreferredInput.KeyboardAndMouse
	end
	LastInputTypeChanged:Fire(inputType)
end

local function getMousePosition3()
	if not state.renderer then
		return ZERO3
	end
	local position = Argon:GetMousePosition()
	return Vector3.new(position.X or 0, position.Y or 0, 0)
end

local function fireKeyboardTransition(binding, down)
	local inputState = down and Enum.UserInputState.Begin or Enum.UserInputState.End
	local input = newInputObject(Enum.UserInputType.Keyboard, inputState, binding.KeyCode)
	local processed = state.focusedTextBox ~= nil
	if down then
		setLastInputType(Enum.UserInputType.Keyboard)
		InputBegan:Fire(input, processed)
		if binding.Name == "Space" then
			JumpRequest:Fire()
		end
	else
		InputEnded:Fire(input, processed)
	end
end

local function fireMouseTransition(sdlButton, down, position)
	local inputType = mouseTypeBySDLButton[sdlButton]
	if not inputType then
		return
	end
	local inputState = down and Enum.UserInputState.Begin or Enum.UserInputState.End
	local input = newInputObject(inputType, inputState, NONE_KEY, position or getMousePosition3())
	if down then
		setLastInputType(inputType)
		InputBegan:Fire(input, false)
	else
		InputEnded:Fire(input, false)
	end
end

local function updateTextBoxFocus(textBox, focused)
	if focused then
		if state.focusedTextBox == textBox then
			return
		end
		if state.focusedTextBox then
			TextBoxFocusReleased:Fire(state.focusedTextBox)
		end
		state.focusedTextBox = textBox
		TextBoxFocused:Fire(textBox)
	elseif state.focusedTextBox == textBox then
		state.focusedTextBox = nil
		TextBoxFocusReleased:Fire(textBox)
	end
end

local function updateWindowFocus()
	if not state.renderer or not Argon.IsWindowFocused then
		return
	end
	local focused = Argon:IsWindowFocused(state.renderer.Window)
	if focused == state.windowFocused then
		return
	end
	state.windowFocused = focused
	if focused then
		WindowFocused:Fire()
	else
		WindowFocusReleased:Fire()
	end
end

local function updateInputFrame()
	if not state.renderer then
		return
	end

	updateWindowFocus()

	local touchedMouseButtons = {}
	for _, click in ipairs(state.renderer.PendingClicks or {}) do
		local sdlButton = click.Button
		local down = click.Down == true
		touchedMouseButtons[sdlButton] = true
		state.pressedMouseButtons[sdlButton] = down
		fireMouseTransition(sdlButton, down, Vector3.new(click.X or 0, click.Y or 0, 0))
	end

	for _, sdlButton in ipairs({ 1, 2, 3 }) do
		if not touchedMouseButtons[sdlButton] then
			local down = state.virtualMouseButtons[sdlButton] == true or Argon:IsMouseButtonDown(sdlButton)
			local previous = state.pressedMouseButtons[sdlButton]
			if previous == nil then
				state.pressedMouseButtons[sdlButton] = down
				if down then
					fireMouseTransition(sdlButton, true)
				end
			elseif previous ~= down then
				state.pressedMouseButtons[sdlButton] = down
				fireMouseTransition(sdlButton, down)
			end
		end
	end

	for _, binding in ipairs(keyBindings) do
		local down = state.virtualKeys[binding.ScanCode] == true or Argon:IsKeyDown(binding.ScanCode)
		local previous = state.pressedKeys[binding.ScanCode]
		if previous == nil then
			state.pressedKeys[binding.ScanCode] = down
			if down then
				fireKeyboardTransition(binding, true)
			end
		elseif previous ~= down then
			state.pressedKeys[binding.ScanCode] = down
			fireKeyboardTransition(binding, down)
		end
	end

	local mouseDelta = Argon:GetMouseDelta()
	if mouseDelta.x ~= 0 or mouseDelta.y ~= 0 then
		local delta = Vector3.new(mouseDelta.x, mouseDelta.y, 0)
		local input = newInputObject(
			Enum.UserInputType.MouseMovement,
			Enum.UserInputState.Change,
			NONE_KEY,
			getMousePosition3(),
			delta
		)
		setLastInputType(Enum.UserInputType.MouseMovement)
		InputChanged:Fire(input, false)
	end

	local wheel = Argon:GetMouseWheelMove()
	if wheel ~= 0 then
		local delta = Vector3.new(0, 0, wheel)
		local input = newInputObject(
			Enum.UserInputType.MouseWheel,
			Enum.UserInputState.Change,
			NONE_KEY,
			getMousePosition3(),
			delta
		)
		input.WheelDelta = wheel
		setLastInputType(Enum.UserInputType.MouseWheel)
		InputChanged:Fire(input, false)
		MouseWheel:Fire({
			Delta = wheel,
			Position = input.Position,
			UserInputType = input.UserInputType,
			UserInputState = input.UserInputState,
		})
	end

	for _, text in ipairs(state.renderer.TextInputs or {}) do
		local input = newInputObject(Enum.UserInputType.TextInput, Enum.UserInputState.Change, NONE_KEY)
		input.Text = text
		setLastInputType(Enum.UserInputType.TextInput)
		TextInput:Fire(text, input)
		InputChanged:Fire(input, true)
	end
end

function UserInputService:IsKeyDown(keyCode)
	local binding = resolveKeyBinding(keyCode)
	if not binding then
		return false
	end
	return state.virtualKeys[binding.ScanCode] == true or (state.renderer ~= nil and Argon:IsKeyDown(binding.ScanCode))
end

function UserInputService:IsMouseButtonPressed(mouseButton)
	local sdlButton = resolveMouseButton(mouseButton)
	if not sdlButton then
		return false
	end
	return state.virtualMouseButtons[sdlButton] == true
		or (state.renderer ~= nil and Argon:IsMouseButtonDown(sdlButton))
end

UserInputService.IsMouseButtonDown = UserInputService.IsMouseButtonPressed

function UserInputService:IsMouseButtonPressedThisFrame(mouseButton)
	local sdlButton = resolveMouseButton(mouseButton)
	return sdlButton ~= nil and state.renderer ~= nil and Argon:IsMouseButtonPressed(sdlButton)
end

function UserInputService:IsMouseButtonReleased(mouseButton)
	local sdlButton = resolveMouseButton(mouseButton)
	return sdlButton ~= nil and state.renderer ~= nil and Argon:IsMouseButtonReleased(sdlButton)
end

function UserInputService:GetKeysPressed()
	local result = {}
	for _, binding in ipairs(keyBindings) do
		if self:IsKeyDown(binding.KeyCode) then
			table.insert(
				result,
				newInputObject(Enum.UserInputType.Keyboard, Enum.UserInputState.Change, binding.KeyCode)
			)
		end
	end
	return result
end

function UserInputService:GetMouseButtonsPressed()
	local result = {}
	for _, sdlButton in ipairs({ 1, 3, 2 }) do
		if state.virtualMouseButtons[sdlButton] == true or (state.renderer and Argon:IsMouseButtonDown(sdlButton)) then
			table.insert(
				result,
				newInputObject(
					mouseTypeBySDLButton[sdlButton],
					Enum.UserInputState.Change,
					NONE_KEY,
					getMousePosition3()
				)
			)
		end
	end
	return result
end

function UserInputService:GetMouseDelta()
	if not state.renderer then
		return ZERO2
	end
	local delta = Argon:GetMouseDelta()
	local sensitivity = tonumber(self.MouseDeltaSensitivity) or 1
	return Vector2.new(delta.x * sensitivity, delta.y * sensitivity)
end

function UserInputService:GetMouseLocation()
	if not state.renderer then
		return ZERO2
	end
	local position = Argon:GetMousePosition()
	return Vector2.new(position.X or 0, position.Y or 0)
end

function UserInputService:SetMouseLocation(x, y)
	if not state.renderer then
		return
	end
	if type(x) == "table" then
		y = x.Y
		x = x.X
	end
	Argon:SetMousePosition(state.renderer.Window, x or 0, y or 0)
end

UserInputService.SetMousePosition = UserInputService.SetMouseLocation

function UserInputService:DisableCursor()
	self.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
end

function UserInputService:EnableCursor()
	self.MouseBehavior = Enum.MouseBehavior.Default
end

function UserInputService:GetLastInputType()
	return state.lastInputType
end

function UserInputService:GetFocusedTextBox()
	return state.focusedTextBox
end

function UserInputService:GetStringForKeyCode(keyCode)
	local binding = resolveKeyBinding(keyCode)
	if not binding then
		return ""
	end
	local names = {
		Return = "Enter",
		LeftControl = "Left Ctrl",
		RightControl = "Right Ctrl",
		LeftShift = "Left Shift",
		RightShift = "Right Shift",
		LeftAlt = "Left Alt",
		RightAlt = "Right Alt",
	}
	return names[binding.Name] or binding.Name
end

function UserInputService:GetImageForKeyCode()
	return ""
end

function UserInputService:GetConnectedGamepads()
	return {}
end

function UserInputService:GetNavigationGamepads()
	return {}
end

function UserInputService:GetSupportedGamepadKeyCodes()
	return {}
end

function UserInputService:GetGamepadState()
	return {}
end

function UserInputService:GetGamepadConnected()
	return false
end

function UserInputService:GamepadSupports()
	return false
end

function UserInputService:IsGamepadButtonDown()
	return false
end

function UserInputService:IsNavigationGamepad()
	return false
end

function UserInputService:SetNavigationGamepad() end

function UserInputService:GetDeviceAcceleration()
	return newInputObject(Enum.UserInputType.Accelerometer, Enum.UserInputState.Change)
end

function UserInputService:GetDeviceGravity()
	return newInputObject(Enum.UserInputType.Accelerometer, Enum.UserInputState.Change)
end

function UserInputService:GetDeviceRotation()
	return newInputObject(Enum.UserInputType.Gyro, Enum.UserInputState.Change), CFrame.new()
end

function UserInputService:GetUserCFrame()
	return CFrame.new()
end

function UserInputService:RecenterUserHeadCFrame() end

function UserInputService:CreateVirtualInput()
	local virtualInput = {}

	function virtualInput:SendKey(isPressed, keyCode)
		local binding = resolveKeyBinding(keyCode)
		if binding then
			state.virtualKeys[binding.ScanCode] = isPressed == true
		end
	end

	function virtualInput:SendMouseButton(position, mouseButton, isDown)
		local sdlButton = resolveMouseButton(mouseButton)
		if sdlButton then
			state.virtualMouseButtons[sdlButton] = isDown == true
			if position then
				UserInputService:SetMouseLocation(position)
			end
		end
	end

	function virtualInput:SendMouseDelta(delta)
		if delta and state.renderer then
			local current = UserInputService:GetMouseLocation()
			UserInputService:SetMouseLocation(current + delta)
		end
	end

	return virtualInput
end

local function applyMouseBehavior(value)
	if not state.renderer then
		return
	end
	local name = type(value) == "table" and value.Name or tostring(value)
	if name == "Default" then
		Argon:EnableCursor(state.renderer.Window)
	else
		Argon:DisableCursor(state.renderer.Window)
	end
end

local function applyMouseIconEnabled(enabled)
	if enabled == false then
		Argon:HideCursor()
	else
		Argon:ShowCursor()
	end
end

UserInputService:SetProperties({
	Name = "UserInputService",
	AccelerometerEnabled = false,
	GamepadEnabled = false,
	GyroscopeEnabled = false,
	KeyboardEnabled = true,
	MouseEnabled = true,
	TouchEnabled = false,
	TouchScreenEnabled = false,
	VREnabled = false,
	ModalEnabled = false,
	MouseBehavior = Enum.MouseBehavior.Default,
	MouseDeltaSensitivity = 1,
	MouseIcon = "",
	MouseIconEnabled = true,
	OnScreenKeyboardPosition = ZERO2,
	OnScreenKeyboardSize = ZERO2,
	OnScreenKeyboardVisible = false,
	PreferredInput = Enum.PreferredInput.KeyboardAndMouse,
	LastInputType = Enum.UserInputType.None,
	InputBegan = InputBegan,
	InputChanged = InputChanged,
	InputEnded = InputEnded,
	LastInputTypeChanged = LastInputTypeChanged,
	JumpRequest = JumpRequest,
	TextBoxFocused = TextBoxFocused,
	TextBoxFocusReleased = TextBoxFocusReleased,
	WindowFocused = WindowFocused,
	WindowFocusReleased = WindowFocusReleased,
	MouseWheel = MouseWheel,
	TextInput = TextInput,
	GamepadConnected = GamepadConnected,
	GamepadDisconnected = GamepadDisconnected,
	DeviceAccelerationChanged = DeviceAccelerationChanged,
	DeviceGravityChanged = DeviceGravityChanged,
	DeviceRotationChanged = DeviceRotationChanged,
	PointerAction = PointerAction,
	TouchStarted = TouchStarted,
	TouchMoved = TouchMoved,
	TouchEnded = TouchEnded,
	TouchTap = TouchTap,
	TouchTapInWorld = TouchTapInWorld,
	TouchLongPress = TouchLongPress,
	TouchPan = TouchPan,
	TouchPinch = TouchPinch,
	TouchRotate = TouchRotate,
	TouchSwipe = TouchSwipe,
})

UserInputService:_SetPropertyHandler("MouseBehavior", applyMouseBehavior)
UserInputService:_SetPropertyHandler("MouseIconEnabled", applyMouseIconEnabled)

UserInputService.InitRenderer = function(renderer, rendererSignal, datamodel)
	state.renderer = renderer
	state.datamodel = datamodel
	table.clear(state.pressedKeys)
	table.clear(state.pressedMouseButtons)

	if state.rendererConnection then
		state.rendererConnection:Disconnect()
	end
	if state.focusConnection then
		state.focusConnection:Disconnect()
	end

	if IsHeadless then
		UserInputService.KeyboardEnabled = false
		UserInputService.MouseEnabled = false
		return
	end

	applyMouseBehavior(UserInputService.MouseBehavior)
	applyMouseIconEnabled(UserInputService.MouseIconEnabled)
	state.windowFocused = not Argon.IsWindowFocused or Argon:IsWindowFocused(renderer.Window)

	if datamodel then
		for _, descendant in ipairs(datamodel:GetDescendants()) do
			if descendant.ClassName == "TextBox" and descendant.Focused == true then
				updateTextBoxFocus(descendant, true)
				break
			end
		end
		state.focusConnection = datamodel.DescendantChanged:Connect(function(descendant, property, value)
			if descendant.ClassName == "TextBox" and property == "Focused" then
				updateTextBoxFocus(descendant, value == true)
			end
		end)
	end

	state.rendererConnection = rendererSignal:Connect(function(route)
		if route == "PreRender" then
			updateInputFrame()
		end
	end)
end

return UserInputService
