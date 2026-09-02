local typedefs = require("../typedefs")
local argon = require("@Argon")
local Image = require("./Image")
local Text = require("./Text")

local TEXT_SIZE = 13

return function(params: typedefs.ImageTextButtonParams, dt: number)
	local window = params.engine_window
	local theme = params.theme
	local cornerRadius = params.CornerRadius or theme.ButtonCornerRadius or 12

	local drawX = params.x
	local drawY = params.y

	argon:Save(window)

	argon:ClipRoundRect(window, {
		x = drawX,
		y = drawY,
		width = params.width,
		height = params.height,
	}, cornerRadius, cornerRadius)

	argon:DrawRectangle(window, {
		x = drawX,
		y = drawY,
		width = params.width,
		height = params.height,
		Color = params.Color,
	})

	local padding = params.padding or 8
	local textSize = params.TextSize or TEXT_SIZE
	local font = argon:CreateFont(theme.Font)
	local textHeight = argon:GetFontLineHeight(textSize, font)
	local textAscent = argon:GetFontAscent(textSize, font)

	local textAreaHeight = textHeight + padding * 2
	local imageAreaHeight = math.max(params.height - textAreaHeight, 0)

	local maxImageWidth = params.width - padding * 2
	local maxImageHeight = imageAreaHeight - padding * 2

	local imageWidth = params.imageWidth or maxImageWidth
	local imageHeight = params.imageHeight or maxImageHeight

	if params.preserveAspectRatio and params.imageAspectRatio then
		local aspect = params.imageAspectRatio
		if imageWidth / aspect > imageHeight then
			imageWidth = imageHeight * aspect
		else
			imageHeight = imageWidth / aspect
		end
	end

	imageWidth = math.min(imageWidth, maxImageWidth)
	imageHeight = math.min(imageHeight, maxImageHeight)

	local imageX = drawX + (params.width / 2) - (imageWidth / 2)
	local imageY = drawY + padding + (maxImageHeight / 2) - (imageHeight / 2)

	Image({
		x = imageX,
		y = imageY,
		width = imageWidth,
		height = imageHeight,
		Image = params.Image,
		engine_window = window,
	}, dt)

	local text = params.text or ""
	local textWidth = argon:MeasureText(window, text, textSize, font)
	local textX = drawX + (params.width / 2) - (textWidth / 2)
	local textY = drawY + params.height - textAreaHeight + (textAreaHeight - textHeight) / 2 + textAscent

	Text({
		x = textX,
		y = textY,
		TextSize = textSize,
		theme = theme,
		Font = font,
		text = text,
		Color = params.TextColor or theme.TextColor,
		engine_window = window,
	}, dt)

	argon:Restore(window)
end
