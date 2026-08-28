-- skia adapter
local skia = require("./skia")
local SkiaAdapter = {}
local typedefs = require("../../typedefs")
local zembed = require("@zembed")

local DEFAULT_FONT_PATH = zembed.AssetPath("kineasset://fonts/Montserrat-Medium.ttf")

local function colorToBytes(color: typedefs.Color)
	return math.floor(color.R * 255 + 0.5),
		math.floor(color.G * 255 + 0.5),
		math.floor(color.B * 255 + 0.5),
		math.floor(color.A * 255 + 0.5)
end

local function getFontPath(font: typedefs.Font?): string
	if type(font) == "table" then
		return font._path or font.path or font._handle or DEFAULT_FONT_PATH
	end
	if type(font) == "string" and font ~= "" then
		return font
	end
	return DEFAULT_FONT_PATH
end

-- Used by internals only
function SkiaAdapter:Init(width, height)
	return skia.lib.Kine_Skia_Surface_Create(width, height)
end

function SkiaAdapter:CreateVulkanContext(backend)
	return skia.lib.Kine_Skia_Vulkan_CreateContext(backend)
end

function SkiaAdapter:DestroyVulkanContext(context)
	if context then
		skia.lib.Kine_Skia_Vulkan_DestroyContext(context)
	end
end

function SkiaAdapter:Clear(context, color: typedefs.Color)
	skia.lib.Kine_Skia_Surface_Clear(
		context,
		math.floor(color.R * 255 + 0.5),
		math.floor(color.G * 255 + 0.5),
		math.floor(color.B * 255 + 0.5),
		math.floor(color.A * 255 + 0.5),
		0
	)
end

function SkiaAdapter:DrawRect(context, rect: typedefs.Rectangle)
	local r, g, b, a = colorToBytes(rect.Color)
	skia.lib.Kine_Skia_Surface_DrawRect(
		context,
		rect.x,
		rect.y,
		rect.width,
		rect.height,
		r,
		g,
		b,
		a,
		rect.isOutline and 1 or 0,
		rect.isOutline and 2 or 0
	)
end

function SkiaAdapter:DrawRoundRect(
	context,
	rect: typedefs.Rectangle,
	radiusX: number,
	radiusY: number,
	strokeWidth: number?
)
	local r, g, b, a = colorToBytes(rect.Color)
	skia.lib.Kine_Skia_Surface_DrawRoundRect(
		context,
		rect.x,
		rect.y,
		rect.width,
		rect.height,
		radiusX,
		radiusY,
		r,
		g,
		b,
		a,
		strokeWidth or (if rect.isOutline then 1 else 0)
	)
end

function SkiaAdapter:DrawSquircle(
	context,
	rect: typedefs.Rectangle,
	radius: number,
	exponent: number,
	strokeWidth: number?
)
	local r, g, b, a = colorToBytes(rect.Color)
	skia.lib.Kine_Skia_Surface_DrawSquircle(
		context,
		rect.x,
		rect.y,
		rect.width,
		rect.height,
		radius,
		exponent,
		r,
		g,
		b,
		a,
		strokeWidth or (if rect.isOutline then 1 else 0)
	)
end

function SkiaAdapter:DrawUIShadow(
	context,
	rect: typedefs.Rectangle,
	radius: number,
	exponent: number,
	offset,
	blur: number,
	spread: number
)
	local r, g, b, a = colorToBytes(rect.Color)
	skia.lib.Kine_Skia_Surface_DrawUIShadow(
		context,
		rect.x,
		rect.y,
		rect.width,
		rect.height,
		radius,
		exponent,
		offset.X or 0,
		offset.Y or 0,
		blur,
		spread,
		r,
		g,
		b,
		a
	)
end

function SkiaAdapter:DrawBackdropBlur(
	context,
	rect: typedefs.Rectangle,
	blur: number,
	radiusX: number?,
	radiusY: number?,
	tint
)
	local tr, tg, tb, ta = 0, 0, 0, 0
	if tint then
		tr, tg, tb, ta = colorToBytes(tint)
	end
	skia.lib.Kine_Skia_Surface_DrawBackdropBlurRect(
		context,
		rect.x,
		rect.y,
		rect.width,
		rect.height,
		radiusX or 0,
		radiusY or 0,
		blur,
		math.floor((rect.alpha or 1) * 255 + 0.5),
		tr,
		tg,
		tb,
		ta
	)
end

function SkiaAdapter:DrawBackdropBlurSquircle(
	context,
	rect: typedefs.Rectangle,
	blur: number,
	radius: number,
	exponent: number,
	tint
)
	local tr, tg, tb, ta = 0, 0, 0, 0
	if tint then
		tr, tg, tb, ta = colorToBytes(tint)
	end
	skia.lib.Kine_Skia_Surface_DrawBackdropBlurSquircle(
		context,
		rect.x,
		rect.y,
		rect.width,
		rect.height,
		radius,
		exponent,
		blur,
		math.floor((rect.alpha or 1) * 255 + 0.5),
		tr,
		tg,
		tb,
		ta
	)
end

function SkiaAdapter:GetFontAscent(fontSize, font: typedefs.Font)
	return skia.lib.Kine_Skia_Surface_GetFontAscent(fontSize, getFontPath(font))
end

function SkiaAdapter:GetPixelsAndPitch(skiaSurface)
	skia.lib.Kine_Skia_Surface_Flush(skiaSurface)
	local pixels = skia.lib.Kine_Skia_Surface_GetPixels(skiaSurface)
	local pitch = skia.lib.Kine_Skia_Surface_GetRowBytes(skiaSurface)
	return pixels, pitch
end

function SkiaAdapter:Save(skiaSurface)
	skia.lib.Kine_Skia_Surface_Save(skiaSurface)
end

function SkiaAdapter:Restore(skiaSurface)
	skia.lib.Kine_Skia_Surface_Restore(skiaSurface)
end

function SkiaAdapter:CreateImage(path): typedefs.Image
	return skia.lib.Kine_Skia_Image_LoadFromFile(path)
end

function SkiaAdapter:DestroyImage(image)
	if image and image ~= zune.ffi.null then
		skia.lib.Kine_Skia_Image_Destroy(image)
	end
end

function SkiaAdapter:MeasureText(text: string, size: number, font: typedefs.Font)
	return skia.lib.Kine_Skia_Surface_MeasureText(text, size, getFontPath(font))
end

function SkiaAdapter:DrawImageSized(skiaSurface, image: typedefs.Image, rect: typedefs.Rectangle, alpha: number?)
	skia.lib.Kine_Skia_Surface_DrawImageSized(
		skiaSurface,
		image._handle,
		rect.x,
		rect.y,
		rect.width,
		rect.height,
		alpha and math.floor(alpha * 255 + 0.5) or 255
	)
end

function SkiaAdapter:DrawImageOutlineSized(
	skiaSurface,
	image: typedefs.Image,
	rect: typedefs.Rectangle,
	color: typedefs.Color,
	thickness: number,
	alpha: number?
)
	local r, g, b, a = colorToBytes(color)
	skia.lib.Kine_Skia_Surface_DrawImageOutlineSized(
		skiaSurface,
		image._handle,
		rect.x,
		rect.y,
		rect.width,
		rect.height,
		thickness,
		r,
		g,
		b,
		a,
		alpha and math.floor(alpha * 255 + 0.5) or 255
	)
end

function SkiaAdapter:GetFontLineHeight(fontSize, font: typedefs.Font)
	return skia.lib.Kine_Skia_Surface_GetFontLineHeight(fontSize, getFontPath(font))
end

function SkiaAdapter:CreateFont(fontPath)
	return { _handle = fontPath, _path = fontPath } :: typedefs.Font
end

function SkiaAdapter:ClipRoundRect(context, rect: typedefs.Rectangle, radiusX: number, radiusY: number)
	skia.lib.Kine_Skia_Surface_ClipRoundRect(context, rect.x, rect.y, rect.width, rect.height, radiusX, radiusY)
end

function SkiaAdapter:ClipSquircle(context, rect: typedefs.Rectangle, radius: number, exponent: number)
	skia.lib.Kine_Skia_Surface_ClipSquircle(context, rect.x, rect.y, rect.width, rect.height, radius, exponent)
end

function SkiaAdapter:InitSkiaSurface(width, height)
	return skia.lib.Kine_Skia_Surface_Create(width, height)
end

function SkiaAdapter:DestroySurface(skiaSurface)
	skia.lib.Kine_Skia_Surface_Destroy(skiaSurface)
end

function SkiaAdapter:DrawText(skiaSurface, text, position: typedefs.TextArgs)
	local fontPath = getFontPath(position.Font)
	skia.lib.Kine_Skia_Surface_DrawText(
		skiaSurface,
		text,
		position.X,
		position.Y,
		position.TextSize,
		fontPath,
		math.floor(position.Color.R * 255 + 0.5),
		math.floor(position.Color.G * 255 + 0.5),
		math.floor(position.Color.B * 255 + 0.5),
		math.floor(position.Color.A * 255 + 0.5)
	)
end

return SkiaAdapter
