local typedefs = require("../typedefs")
local Titlebar = require("./Titlebar")
local Rectangle = require("./Rectangle")
local argon = require("@Argon")

local function withTransparency(color, transparency: number?)
	if not color or transparency == nil then
		return color
	end

	return {
		R = color.R,
		G = color.G,
		B = color.B,
		A = (color.A or 1) * math.clamp(1 - transparency, 0, 1),
	}
end

local function isVisibleColor(color): boolean
	return color ~= nil and (color.A == nil or color.A > 0)
end

return function(params: typedefs.WidgetParams, dt: number)
	local window = params.engine_window
	local theme = params.theme

	local titleBarHeight = 32
	local cornerRadius = theme.CornerRadius or 12

	argon:Save(window)

	argon:ClipRoundRect(window, {
		x = params.x,
		y = params.y,
		width = params.width,
		height = params.height,
	}, cornerRadius, cornerRadius)

	local backgroundColor = withTransparency(params.Color or theme.ThirdColor, params.BackgroundTransparency)
	if isVisibleColor(backgroundColor) then
		Rectangle({
			x = params.x,
			y = params.y,
			width = params.width,
			height = params.height,
			Color = backgroundColor,
			theme = theme,
			engine_window = window,
		}, dt)
	end

	local outlineColor = withTransparency(params.OutlineColor or theme.SecondaryColor, params.OutlineTransparency)
	if isVisibleColor(outlineColor) then
		Rectangle({
			x = params.x,
			y = params.y,
			width = params.width,
			height = params.height,
			Color = outlineColor,
			theme = theme,
			engine_window = window,
			isOutline = true,
		}, dt)
	end

	if params.EnableTitlebar or params.title then
		Titlebar({
			engine_window = window,

			x = params.x,
			y = params.y,
			width = params.width,
			height = titleBarHeight,
			Color = theme.SecondaryColor,

			title = params.title,
			tabs = params.tabs,
			activeTab = params.activeTab,
			OnTabChanged = params.OnTabChanged,
			renderer = params.renderer,
			theme = theme,
		}, dt)
	end

	if params.callback then
		params.callback({
			x = params.x,
			y = params.y + titleBarHeight,
			width = params.width,
			height = params.height,
			window = window,
			theme = theme,
		})
	end
	argon:Restore(window)
end
