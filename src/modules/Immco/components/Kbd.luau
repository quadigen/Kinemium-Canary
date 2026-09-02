local typedefs = require("../typedefs")

local Text = require("./Text")
local argon = require("@Argon")

local SIZES = {
	xs = {
		height = 16,
		textSize = 10,
	},

	sm = {
		height = 20,
		textSize = 12,
	},

	md = {
		height = 24,
		textSize = 14,
	},

	lg = {
		height = 28,
		textSize = 16,
	},

	xl = {
		height = 32,
		textSize = 18,
	},
}

return function(params: typedefs.KbdParams, dt: number): (number, number)
	local window = params.engine_window
	local theme = params.theme

	local sizeName = string.lower(params.Size or "md")
	local sizeInfo = SIZES[sizeName] or SIZES.md

	local text = params.Text or "K"

	local height = params.height or sizeInfo.height
	local textSize = params.TextSize or sizeInfo.textSize

	local font = argon:CreateFont(params.Font or theme.Font)

	local textWidth = argon:MeasureText(window, text, textSize, font)

	local paddingX = params.PaddingX or (textSize * 0.5)

	local width = params.width or math.max(height, textWidth + paddingX * 2)

	local cornerRadius = params.CornerRadius or theme.CornerRadius or 4

	local backgroundColor = params.BackgroundColor or theme.SecondaryColor or theme.BgColor

	local borderColor = params.BorderColor or theme.AlternatingColor1 or theme.SecondaryTextColor

	local textColor = params.TextColor or theme.TextColor

	local borderThickness = params.BorderThickness or 1
	local bottomBorderExtra = params.BottomBorderExtra or 1

	local outerRect = {
		x = params.x,
		y = params.y,
		width = width,
		height = height,
	}

	-- Outer border.
	argon:Save(window)

	argon:ClipRoundRect(window, outerRect, cornerRadius, cornerRadius)

	argon:DrawRectangle(window, {
		x = outerRect.x,
		y = outerRect.y,
		width = outerRect.width,
		height = outerRect.height,
		Color = borderColor,
	})

	argon:Restore(window)

	local innerRect = {
		x = params.x + borderThickness,
		y = params.y + borderThickness,

		width = math.max(0, width - borderThickness * 2),

		height = math.max(0, height - borderThickness * 2 - bottomBorderExtra),
	}

	local innerRadius = math.max(0, cornerRadius - borderThickness)

	argon:Save(window)

	argon:ClipRoundRect(window, innerRect, innerRadius, innerRadius)

	argon:DrawRectangle(window, {
		x = innerRect.x,
		y = innerRect.y,
		width = innerRect.width,
		height = innerRect.height,
		Color = backgroundColor,
	})

	argon:Restore(window)

	-- Center text.
	local textHeight = argon:GetFontLineHeight(textSize, font)

	local textAscent = argon:GetFontAscent(textSize, font)

	local textX = params.x + (width - textWidth) / 2

	local textY = params.y + (height - textHeight) / 2 + textAscent - (bottomBorderExtra / 2)

	Text({
		x = textX,
		y = textY,

		Text = text,
		text = text,

		TextSize = textSize,
		Font = font,

		Color = textColor,

		theme = theme,
		engine_window = window,
	}, dt)

	return width, height
end
