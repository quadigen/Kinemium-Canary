-- description: "An Argon-backed text input field with rich editing capabilities."
local Enum = require("@EnumMap")
local logic = require("@Kinemium.2dinput")
local GuiObject = require("@GuiObject")
local Color3 = require("@Color3")
local Immco = require("@Immco")
local Argon = require("@Argon")

local propTable = {
	Name = "TextBox", Visible = true, Focused = false, Text = "", PlaceholderText = "Type here...",
	FontSize = 18, TextColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0,
	BackgroundColor3 = Color3.new(1, 1, 1), PlaceholderColor3 = Color3.new(0.5, 0.5, 0.5),
	FocusColor3 = Color3.new(0.02, 0.5, 1), TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Center, Font = Enum.Font.DefaultEngineFont, MultiLine = false,
	ReadOnly = false, MaxLength = nil, TabSize = 4, AutoPairs = true, AutoIndent = false,
	WordWrap = false, Validator = nil, Numeric = false, NumericMin = nil, NumericMax = nil,
	NumericStep = 1, NumericPrecision = nil, Scrollable = false, ShowLineNumbers = false,
	CornerRadius = 0, LineHighlight = true, MatchBrackets = false, EnableMinimap = false,
	SelectAllOnFocus = false, BlurOnSubmit = true, ClearOnEscape = false, EscapeBlurs = false,
	OnChange = nil, OnSubmit = nil, OnFocus = nil, OnBlur = nil, OnValidationError = nil,
	OnSearch = nil, MaxHistory = 100,
}
GuiObject.inherit(propTable)

local function toArgon(color, transparency)
	local r, g, b = color:ToRGB()
	return Argon:RGBA(r, g, b, 1 - (transparency or 0))
end

propTable.render = function(_, object, dt, _, renderer, datamodel)
	local framePos, frameSize = GuiObject.render(renderer.Window, object, dt, renderer)
	if not object.Visible or not framePos or not frameSize then return end

	local themeService = datamodel and datamodel:GetService("StudioThemeService")
	local theme = themeService and themeService.SelectedTheme or {}
	local storage = object._argonTextStorage
	local field = storage[object._argonTextId]
	if field and field.text ~= object.Text and not object.Focused then
		field.text = tostring(object.Text or "")
		field.cursorPos = #field.text
	end

	local previousFocused = object.Focused
	local newText = Immco.TextInput({
		engine_window = renderer.Window, renderer = renderer, theme = theme,
		RetainedStorage = storage, id = object._argonTextId,
		x = framePos.X, y = framePos.Y, width = frameSize.X, height = frameSize.Y,
		text = object.Text, placeholder = object.PlaceholderText, TextSize = object.FontSize,
		TextColor = toArgon(object.TextColor3), PlaceholderColor = toArgon(object.PlaceholderColor3),
		Color = toArgon(object.BackgroundColor3, object.BackgroundTransparency),
		FocusColor = toArgon(object.FocusColor3), ReadOnly = object.ReadOnly,
		MultiLine = object.MultiLine, MaxLength = object.MaxLength, TabSize = object.TabSize,
		AutoCloseBrackets = object.AutoPairs, AutoIndent = object.AutoIndent,
		ShowLineNumbers = object.ShowLineNumbers, EnableMinimap = object.EnableMinimap,
		HighlightCurrentLine = object.LineHighlight, HighlightMatchingBracket = object.MatchBrackets,
		UndoLimit = object.MaxHistory,
		OnChange = function(text)
			object.Text = text
			if object.OnChange then object.OnChange(text) end
		end,
		OnSubmit = function(text)
			if object.OnSubmit then object.OnSubmit(text) end
		end,
	}, dt)

	object.Text = newText
	field = storage[object._argonTextId]
	object.Focused = field ~= nil and storage.focusedId == object._argonTextId
	if object.Focused ~= previousFocused then
		if object.Focused and object.OnFocus then object.OnFocus() end
		if not object.Focused and object.OnBlur then object.OnBlur() end
	end
	return framePos, frameSize
end

return {
	class = "TextBox",
	callback = function(instance)
		logic:SetupSignals(propTable)
		instance:SetProperties(propTable)
		instance._argonTextStorage = {}
		instance._argonTextId = "TextBox:" .. tostring(instance)
		return instance
	end,
	inherit = function(target)
		for prop, value in pairs(propTable) do
			if target[prop] == nil then target[prop] = value end
		end
	end,
}
