-- description: "A Roblox-compatible Studio theme backed by Kinemium's Argon palette."
local Color3 = require("@Color3")

local propTable = { Name = "Dark", BaseClass = "StudioTheme" }

local function itemName(value)
	if type(value) == "table" then
		return value.Name or value.name
	end
	return type(value) == "string" and value or nil
end

local function shade(color, amount)
	local target = amount >= 0 and Color3.new(1, 1, 1) or Color3.new(0, 0, 0)
	return color:Lerp(target, math.abs(amount))
end

local function createPalette()
	local bg = Color3.fromRGB(35, 35, 35)
	local base = Color3.fromRGB(15, 15, 15)
	local secondary = Color3.fromRGB(43, 43, 43)
	local surface = Color3.fromRGB(25, 25, 25)
	local text = Color3.fromRGB(220, 220, 220)
	local subtext = Color3.fromRGB(180, 180, 180)
	local accent = Color3.fromRGB(214, 133, 37)
	local selection = Color3.fromRGB(51, 51, 64)

	return {
		MainBackground = bg,
		Titlebar = surface,
		Dropdown = secondary,
		Tooltip = surface,
		Notification = surface,
		ScrollBar = accent,
		ScrollBarBackground = secondary,
		TabBar = secondary,
		Tab = bg,
		RibbonTab = bg,
		RibbonTabTopBar = surface,
		Button = secondary,
		MainButton = accent,
		RibbonButton = secondary,
		ViewPortBackground = bg,
		InputFieldBackground = Color3.fromRGB(38, 38, 38),
		ColorPickerFrame = bg,
		Border = secondary,
		DropShadow = Color3.new(),
		Shadow = Color3.new(),
		Light = text,
		Dark = surface,
		Mid = secondary,
		Midlight = shade(secondary, 0.08),
		MainText = text,
		SubText = subtext,
		TitlebarText = text,
		BrightText = Color3.new(1, 1, 1),
		DimmedText = subtext,
		LinkText = accent,
		WarningText = Color3.fromRGB(255, 200, 0),
		ErrorText = Color3.fromRGB(255, 80, 80),
		InfoText = Color3.fromRGB(0, 170, 255),
		SensitiveText = Color3.fromRGB(255, 120, 120),
		ScriptSideWidget = secondary,
		ScriptBackground = base,
		ScriptText = text,
		ScriptSelectionText = text,
		ScriptSelectionBackground = selection,
		ScriptFindSelectionBackground = Color3.fromRGB(75, 65, 35),
		ScriptMatchingWordSelectionBackground = selection,
		ScriptOperator = Color3.fromRGB(197, 134, 192),
		ScriptNumber = Color3.fromRGB(181, 206, 168),
		ScriptString = Color3.fromRGB(206, 145, 120),
		ScriptComment = Color3.fromRGB(106, 153, 85),
		ScriptKeyword = Color3.fromRGB(197, 134, 192),
		ScriptBuiltInFunction = Color3.fromRGB(86, 156, 214),
		ScriptWarning = Color3.fromRGB(255, 200, 0),
		ScriptError = Color3.fromRGB(255, 80, 80),
		ScriptInformation = Color3.fromRGB(0, 170, 255),
		ScriptHint = Color3.fromRGB(120, 120, 120),
		ScriptWhitespace = Color3.fromRGB(80, 80, 80),
		ScriptRuler = secondary,
		DocViewCodeBackground = bg,
		DebuggerCurrentLine = selection,
		DebuggerErrorLine = Color3.fromRGB(100, 30, 30),
		ScriptEditorCurrentLine = Color3.fromRGB(30, 30, 30),
		ButtonBorder = secondary,
		ButtonText = text,
		InputFieldBorder = secondary,
		CheckedFieldBackground = accent,
		CheckedFieldBorder = accent,
		CheckedFieldIndicator = text,
		HeaderSection = secondary,
		StatusBar = surface,
		Separator = secondary,
		DialogButton = secondary,
		DialogButtonText = text,
		DialogButtonBorder = secondary,
		DialogMainButton = accent,
		DialogMainButtonText = text,
		AutocompleteBackground = bg,
		AutocompleteBorder = secondary,
		AutocompleteSelection = selection,
		AutocompleteText = text,
	}
end

return {
	class = "StudioTheme",
	callback = function(instance)
		instance:SetProperties(propTable)
		local palette = createPalette()

		function instance:GetColor(style, modifier)
			local color = palette[itemName(style)] or Color3.new()
			local modifierName = itemName(modifier)
			if modifierName == "Hover" then
				return shade(color, 0.08)
			end
			if modifierName == "Pressed" then
				return shade(color, -0.1)
			end
			if modifierName == "Disabled" then
				return color:Lerp(palette.MainBackground, 0.55)
			end
			if modifierName == "Selected" then
				return shade(color, 0.12)
			end
			return color
		end

		function instance:SetColor(style, color)
			local name = itemName(style)
			if name and color then
				palette[name] = color
			end
		end

		function instance:ApplyDirectVar(name, value)
			if type(name) == "string" and value then
				palette[name] = value
			end
		end

		function instance:GetColors()
			local copy = {}
			for name, color in pairs(palette) do
				copy[name] = color
			end
			return copy
		end

		function instance:Apply() end
		return instance
	end,
	inherit = function(target)
		for prop, value in pairs(propTable) do
			target[prop] = value
		end
	end,
}
