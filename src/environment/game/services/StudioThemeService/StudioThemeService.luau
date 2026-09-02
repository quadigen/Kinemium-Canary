local Instance = require("@Instance")
local Color3 = require("@Color3")
local UDim2 = require("@UDim2")
local Vector2 = require("@Vector2")
local Enum = require("@EnumMap")
local StudioTheme = require("@StudioTheme")
local signal = require("@Kinemium.signal")
local argon = require("@Argon")

local StudioThemeService = Instance.new("StudioThemeService")
StudioThemeService.ExplorerHidden = true
StudioThemeService._Intents = Enum.PluginIntents.UI
StudioThemeService.ThemeChanged = signal.new()

StudioThemeService.InitRenderer = function(renderer, renderer_signal, datamodel)
	local P = 4
	local TopH = 33
	local BottomPad = 12
	local showOutput = true

	local function getCoordinates()
		local viewportTop = 2 * P + TopH
		local viewportHeight = showOutput and 0.7 or 1
		local viewportHeightOffset = showOutput and -(viewportTop + P / 2) or -(viewportTop + BottomPad)

		local outputCoordinates = showOutput
				and {
					Size = UDim2.new(0.78, -P * 1.5, 0.3, -(P / 2 + P + BottomPad)),
					Position = UDim2.new(0, P, 0.7, P / 2),
				}
			or {
				Size = UDim2.new(0, 0, 0, 0),
				Position = UDim2.new(0, 0, 1, 0),
			}

		return {
			TopbarCoordinates = {
				Size = UDim2.new(1, -P * 2, 0, TopH),
				Position = UDim2.new(0, P, 0, P),
			},

			ViewportCoordinates = {
				Size = UDim2.new(0.78, -P * 1.5, viewportHeight, viewportHeightOffset),
				Position = UDim2.new(0, P, 0, viewportTop),
			},

			OutputCoordinates = outputCoordinates,

			ExplorerCoordinates = {
				Size = UDim2.new(0.22, -P * 1.5, 0.5, -(2 * P + TopH + P / 2)),
				Position = UDim2.new(0.78, P / 2, 0, 2 * P + TopH),
			},

			InspectorCoordinates = {
				Size = UDim2.new(0.22, -P * 1.5, 0.5, -(P / 2 + P + BottomPad)),
				Position = UDim2.new(0.78, P / 2, 0.5, P / 2),
			},

			CodeEditorCoordinates = {
				Size = UDim2.new(0.78, -P * 1.5, viewportHeight, viewportHeightOffset),
				Position = UDim2.new(0, P, 0, viewportTop),
			},
		}
	end

	local Coordinates = getCoordinates()

	local default = {
		BaseColor = argon:RGBA(15, 15, 15),
		BgColor = argon:RGBA(35, 35, 35),
		AccentColor = argon:RGBA(214, 133, 37),
		SecondaryColor = argon:RGBA(43, 43, 43),
		ThirdColor = argon:RGBA(25, 25, 25),
		SecondaryTextColor = argon:RGBA(180, 180, 180),
		TextColor = argon:RGBA(220, 220, 220),
		TextColorDimmed = argon:RGBA(0, 0, 0),
		CornerRadius = 4,
		ButtonCornerRadius = 8,
		InputColor = argon:RGBA(38, 38, 38),
		InputFocusColor = argon:RGBA(51, 51, 64),
		InputTextColor = argon:RGBA(255, 255, 255),
		InputPlaceholderColor = argon:RGBA(128, 128, 128),
		AlternatingColor1 = argon:RGBA(50, 50, 50),
		AlternatingColor2 = argon:RGBA(45, 45, 45),
		CodeEditorBgColor = argon:RGBA(0, 0, 0, 0.8),
		Font = "./src/assets/fonts/Montserrat-Regular.ttf",
		FontBold = "./src/assets/fonts/Montserrat-Regular.ttf",

		TopbarCoordinates = Coordinates.TopbarCoordinates,
		ViewportCoordinates = Coordinates.ViewportCoordinates,
		OutputCoordinates = Coordinates.OutputCoordinates,
		ExplorerCoordinates = Coordinates.ExplorerCoordinates,
		InspectorCoordinates = Coordinates.InspectorCoordinates,
		CodeEditorCoordinates = Coordinates.CodeEditorCoordinates,
		LayoutConfig = {
			P = 4,
			TopH = 33,
			BottomPad = 12,

			Topbar = { flexGrow = 0 },
			Content = { flexGrow = 1 },

			Left = { flexGrow = 0.78, minWidth = 0 },
			Right = { flexGrow = 0.22, minWidth = 0 },

			Viewport = { flexGrow = 0.7, layoutOrder = 1 },
			CodeEditor = { target = "Viewport" },
			Output = { flexGrow = 0.3, layoutOrder = 2 },

			Explorer = { flexGrow = 0.5, layoutOrder = 1 },
			Inspector = { flexGrow = 0.5, layoutOrder = 2 },
		},
	}

	--[[
	local system_theme = argon:GetSystemTheme()
	if system_theme == "dark" then
		default.BaseColor = argon:RGBA(15, 15, 15)
		default.BgColor = argon:RGBA(35, 35, 35)
		default.AccentColor = argon:RGBA(214, 133, 37)
		default.SecondaryColor = argon:RGBA(43, 43, 43)
		default.ThirdColor = argon:RGBA(25, 25, 25)
		default.TextColor = argon:RGBA(220, 220, 220)
	elseif system_theme == "light" then
		default.BaseColor = argon:RGBA(233, 233, 233)
		default.BgColor = argon:RGBA(245, 245, 245)
		default.AccentColor = argon:RGBA(214, 133, 37)
		default.SecondaryColor = argon:RGBA(235, 235, 235)
		default.ThirdColor = argon:RGBA(255, 255, 255)
		default.TextColor = argon:RGBA(35, 35, 35)
	end
	--]]

	function StudioThemeService:ChangeLayoutSettings(padding, headerHeight, bottomPadding)
		P = padding or P
		TopH = headerHeight or TopH
		BottomPad = bottomPadding or BottomPad

		default.TopbarCoordinates = {
			Size = UDim2.new(1, -P * 2, 0, TopH),
			Position = UDim2.new(0, P, 0, P),
		}
		default.ViewportCoordinates = {
			Size = UDim2.new(0.78, -P * 1.5, 0.7, -(2 * P + TopH + P / 2)),
			Position = UDim2.new(0, P, 0, 2 * P + TopH),
		}
		default.CodeEditorCoordinates = {
			Size = default.ViewportCoordinates.Size,
			Position = default.ViewportCoordinates.Position,
		}
		default.OutputCoordinates = {
			Size = UDim2.new(0.78, -P * 1.5, 0.3, -(P / 2 + P + BottomPad)),
			Position = UDim2.new(0, P, 0.7, P / 2),
		}
		default.ExplorerCoordinates = {
			Size = UDim2.new(0.22, -P * 1.5, 0.5, -(2 * P + TopH + P / 2)),
			Position = UDim2.new(0.78, P / 2, 0, 2 * P + TopH),
		}
		default.InspectorCoordinates = {
			Size = UDim2.new(0.22, -P * 1.5, 0.5, -(P / 2 + P + BottomPad)),
			Position = UDim2.new(0.78, P / 2, 0.5, P / 2),
		}
	end

	local themeObject = Instance.new("StudioTheme")
	StudioTheme.callback(themeObject)

	local function toColor3(color)
		return Color3.new(color.R or 0, color.G or 0, color.B or 0)
	end

	themeObject:SetColor("MainBackground", toColor3(default.BgColor))
	themeObject:SetColor("Titlebar", toColor3(default.ThirdColor))
	themeObject:SetColor("Button", toColor3(default.SecondaryColor))
	themeObject:SetColor("MainButton", toColor3(default.AccentColor))
	themeObject:SetColor("MainText", toColor3(default.TextColor))
	themeObject:SetColor("SubText", toColor3(default.SecondaryTextColor))
	themeObject:SetColor("InputFieldBackground", toColor3(default.InputColor))

	StudioThemeService:SetProperties({
		SelectedTheme = default,
		ThemeObject = themeObject,
	})

	function StudioThemeService:GetTheme()
		return default
	end

	function StudioThemeService:SetTheme(theme, robloxTheme)
		if type(theme) ~= "table" then
			error("StudioThemeService:SetTheme expects an Argon theme table")
		end
		default = theme
		self.SelectedTheme = theme
		if robloxTheme then
			themeObject = robloxTheme
			self.ThemeObject = robloxTheme
		end
		self.ThemeChanged:Fire(themeObject)
	end

	function StudioThemeService.MakeUIPadded()
		StudioThemeService.SelectedTheme.WindowConfig = {
			Explorer = {
				position = UDim2.new(1, -20, 0, 40),
				anchorPoint = Vector2.new(1, 0),
				size = UDim2.new(0, 400, 0.38, 0),
			},
			GameSettings = {
				position = UDim2.new(0.5, 0, 0.5, 0),
				anchorPoint = Vector2.new(0.5, 0.5),
				size = UDim2.new(0.5, 0, 0.7, 0),
			},
			Toolbox = {
				position = UDim2.new(0.5, 0, 0.5, 0),
				anchorPoint = Vector2.new(0.5, 0.5),
				size = UDim2.new(0.6, 0, 0.7, 0),
			},
			Inspector = {
				position = UDim2.new(1, -20, 0.44, 0),
				anchorPoint = Vector2.new(1, 0),
				size = UDim2.new(0, 400, 0.55, 0),
			},
			Output = {
				position = UDim2.new(0, 20, 0.99, 0),
				anchorPoint = Vector2.new(0, 1),
				size = UDim2.new(1, -450, 0, 200),
			},
			Toolbar = {
				position = UDim2.new(0, 0, 0, 0),
				anchorPoint = Vector2.new(0, 0),
				size = UDim2.new(1, 0, 0, 170),
			},
			CodeEditor = {
				position = UDim2.new(0, 20, 0, 40),
				anchorPoint = Vector2.new(0, 0),
				size = UDim2.new(0, 800, 0, 600),
			},
		}
	end

	function StudioThemeService.MakeUIBoxed()
		local xSize = 350
		StudioThemeService.SelectedTheme.WindowConfig = {
			Toolbar = {
				position = UDim2.new(0, 0, 0, 0),
				anchorPoint = Vector2.new(0, 0),
				size = UDim2.new(1, 0, 0, 200),
			},
			Explorer = {
				position = UDim2.new(1, 0, 0, 30),
				anchorPoint = Vector2.new(1, 0),
				size = UDim2.new(0, xSize, 0.5, -50),
			},
			Inspector = {
				position = UDim2.new(1, 0, 0.5, -20),
				anchorPoint = Vector2.new(1, 0),
				size = UDim2.new(0, xSize, 0.5, 20),
			},
			CodeEditor = {
				position = UDim2.new(0, xSize, 0, 0),
				anchorPoint = Vector2.new(0, 0),
				size = UDim2.new(1, -xSize * 2, 1, -200),
			},
			Output = {
				position = UDim2.new(0, 0, 1, 0),
				anchorPoint = Vector2.new(0, 1),
				size = UDim2.new(1, -xSize, 0, 200),
			},
			GameSettings = {
				position = UDim2.new(0.5, 0, 0.5, 0),
				anchorPoint = Vector2.new(0.5, 0.5),
				size = UDim2.new(0.5, 0, 0.7, 0),
			},
			Toolbox = {
				position = UDim2.new(0.5, 0, 0.5, 0),
				anchorPoint = Vector2.new(0.5, 0.5),
				size = UDim2.new(0.6, 0, 0.7, 0),
			},
			FileBrowser = {
				position = UDim2.new(0, 0, 1, 0),
				anchorPoint = Vector2.new(0, 1),
				size = UDim2.new(0, xSize, 1, -20),
			},
		}
	end

	function StudioThemeService:ExportThemeAsJson()
		local function serialize(tbl)
			local result = {}

			for key, value in pairs(tbl) do
				if type(value) ~= "table" then
					result[key] = value
				elseif value.type then
					-- Userdata object (Color3, UDim2, etc.)

					if value.type == "Color3" then
						result[key] = Color3.fromHex(value)
					else
						print(value.type)
						result[key] = value:ToTable()
					end
				else
					-- Nested table
					result[key] = serialize(value)
				end
			end

			return result
		end

		local jsonCompat = serialize(default)
		local encoded = zune.serde.json.encode(jsonCompat)

		zune.fs.writeFile("./src/theme.json", encoded)

		return encoded
	end

	function StudioThemeService:LoadThemeJson(theme)
		local decoded = type(theme) == "string" and zune.serde.json.decode(theme) or theme
		if type(decoded) ~= "table" then
			error("StudioThemeService:LoadThemeJson expects JSON or a theme table")
		end
		for key, value in pairs(decoded) do
			default[key] = value
		end
		self.ThemeChanged:Fire(themeObject)
		return default
	end

	StudioThemeService.MakeUIBoxed()
end

return StudioThemeService
