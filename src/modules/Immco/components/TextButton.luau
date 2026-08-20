local typedefs = require("../typedefs")
local argon = require("@Argon")
local Text = require("./Text")

return function(params: typedefs.TextButtonParams, dt: number)
	local window = params.engine_window
	local theme = params.theme
	local cornerRadius = theme.ButtonCornerRadius or 12

	argon:Save(window)

	argon:ClipRoundRect(window, {
		x = params.x,
		y = params.y,
		width = params.width,
		height = params.height,
	}, cornerRadius, cornerRadius)

	local backgroundColor = {
		R = params.Color.R,
		G = params.Color.G,
		B = params.Color.B,
		A = params.BgVisible and 255 or 0,
	}

	argon:DrawRectangle(window, {
		x = params.x,
		y = params.y,
		width = params.width,
		height = params.height,
		Color = argon:RGBA(backgroundColor.R, backgroundColor.G, backgroundColor.B, backgroundColor.A),
	})

	local text = params.text or "Text"
	local textSize = 16
	local font = argon:CreateFont(theme.Font)

	local textWidth = argon:MeasureText(window, text, textSize, font)
	local textHeight = argon:GetFontLineHeight(textSize, font)
	local textAscent = argon:GetFontAscent(textSize, font)

	local textX = params.x + (params.width / 2) - (textWidth / 2)
	local textY = params.y + (params.height - textHeight) / 2 + textAscent

	Text({
		x = textX,
		y = textY,
		TextSize = textSize,
		theme = theme,
		Font = font,
		text = text,
		Color = params.TextColor,
		engine_window = window,
	}, dt)

	argon:Restore(window)
end
