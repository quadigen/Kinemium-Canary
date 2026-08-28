local StudioThemeService = game:GetService("StudioThemeService")
local Immco = require("@Immco")
local theme = StudioThemeService.SelectedTheme
local Argon = require("@Argon")
local retained = {}

if IsServer then
	return
end

if IsClient then
	return
end

repeat
	task.wait()
until game.CoreGui:FindFirstChild("Studio")

local CodeEditor = Instance.new("Frame")
CodeEditor.Name = "CodeEditor"
CodeEditor.Size = theme.CodeEditorCoordinates.Size
CodeEditor.Position = theme.CodeEditorCoordinates.Position
CodeEditor.Parent = game.CoreGui:FindFirstChild("Studio")
CodeEditor.BackgroundTransparency = 1

local enabled = false

ishared.StudioSystem:Connect(function(prop, value)
	if prop == "toggle_code_editor" then
		enabled = value
		renderer.UpdateCamera = not enabled
	end
end)

renderer.Pool.new("2da", function()
	local dt = renderer.RuntimeLibrary.dt
	local absolutePosition = CodeEditor.AbsolutePosition
	local absoluteSize = CodeEditor.AbsoluteSize

	CodeEditor.Size = theme.CodeEditorCoordinates.Size
	CodeEditor.Position = theme.CodeEditorCoordinates.Position

	if not absolutePosition then
		return
	end
	if not absoluteSize then
		return
	end
	if not enabled then
		return
	end

	Immco.Widget({
		x = absolutePosition.X,
		y = absolutePosition.Y + 5,
		width = absoluteSize.X,
		height = absoluteSize.Y,
		BackgroundTransparency = 1,
		theme = theme,
		engine_window = renderer.Window,

		callback = function(params)
			local rect = {
				x = params.x,
				y = params.y - 32,
				width = params.width,
				height = params.height + 32,
			}
			Argon:DrawBackdropBlur(renderer.Window, rect, 20, 10, 15, Argon:RGBA(0, 0, 0, 0.3))
			Immco.TextInput({
				x = rect.x,
				y = rect.y,
				width = rect.width,
				height = rect.height,
				RetainedStorage = retained,
				id = "editor",
				renderer = renderer,
				BackgroundTransparency = 1,
				GutterBackgroundTransparency = 1,
				engine_window = renderer.Window,
				Color = { R = 0.15, G = 0.15, B = 0.15, A = 1 },
				FocusColor = { R = 0.2, G = 0.2, B = 0.25, A = 1 },
				TextColor = { R = 1, G = 1, B = 1, A = 1 },
				PlaceholderColor = { R = 0.5, G = 0.5, B = 0.5, A = 1 },
				placeholder = "hello world",
				CodeEditor = true,
				MultiLine = true,
				AllowTab = true,
				TabSize = 4,
				InsertSpacesForTab = true,
				AutoIndent = true,
				UndoLimit = 200,
				theme = theme,
				AutoCloseBrackets = true,
				WordNavigation = true,
				Language = "luau",
				HighlightMatchingBracket = true,
				HighlightCurrentLine = true,
				CurrentLineColor = Argon:RGBA(255, 255, 255, 0.05),
				ShowLineNumbers = true,
				IndentGuides = true,
				EnableMinimap = true,
				MinimapWidth = 86,
				MinimapBackgroundTransparency = 0.55,
				MinimapViewportColor = Argon:RGBA(255, 255, 255, 0.14),
				MinimapCursorLineColor = Argon:RGBA(255, 255, 255, 0.35),
				CommentPrefix = "--",
			}, dt)
		end,
	}, dt)
end)
