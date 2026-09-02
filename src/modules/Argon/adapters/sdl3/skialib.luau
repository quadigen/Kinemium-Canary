-- skia adapter
local skia = require("./skia")
local SkiaAdapter = {}
local typedefs = require("../../typedefs")
local zembed = require("@zembed")

local DEFAULT_FONT_PATH = zembed.AssetPath("kineasset://fonts/Montserrat-Medium.ttf")

local function readCString(pointer, maxLength: number?): string
	if not pointer or pointer == zune.ffi.null then
		return ""
	end
	local bytes = {}
	for index = 0, (maxLength or 4096) - 1 do
		local byte = pointer:readu8(index)
		if byte == 0 then
			break
		end
		bytes[#bytes + 1] = string.char(byte)
	end
	return table.concat(bytes)
end

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

function SkiaAdapter:CreateRuntimeShader(source: string)
	local handle = skia.lib.Kine_Skia_RuntimeShader_Create(source)
	if not handle or handle == zune.ffi.null then
		return nil, readCString(skia.lib.Kine_Skia_RuntimeShader_GetLastError())
	end
	return handle
end

function SkiaAdapter:DestroyRuntimeShader(shader)
	if shader and shader ~= zune.ffi.null then
		skia.lib.Kine_Skia_RuntimeShader_Destroy(shader)
	end
end

function SkiaAdapter:SetRuntimeShaderUniform(shader, name: string, values: { number })
	if not shader or shader == zune.ffi.null or #values == 0 then
		return false
	end
	local data = zune.ffi.alloc(#values * 4)
	for index, value in ipairs(values) do
		data:writef32((index - 1) * 4, value)
	end
	local result = skia.lib.Kine_Skia_RuntimeShader_SetUniform(shader, name, data, #values) ~= 0
	zune.ffi.free(data)
	return result
end

function SkiaAdapter:DrawRuntimeShaderRect(context, shader, rect: typedefs.Rectangle)
	if shader and shader ~= zune.ffi.null then
		skia.lib.Kine_Skia_Surface_DrawRuntimeShaderRect(context, shader, rect.x, rect.y, rect.width, rect.height)
	end
end

function SkiaAdapter:DrawTextShadow(
	skiaSurface,
	text: string,
	position: typedefs.TextArgs,
	offset,
	blur: number,
	spread: number,
	color: typedefs.Color
)
	local fontPath = getFontPath(position.Font)
	local r, g, b, a = colorToBytes(color)

	skia.lib.Kine_Skia_Surface_DrawTextShadow(
		skiaSurface,
		text,
		position.X,
		position.Y,
		position.TextSize,
		fontPath,
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
		rect.isOutline and 2 or 0
	)
end

function SkiaAdapter:DrawRotatedRect(context, rect: typedefs.Rectangle, rotationDegrees: number)
	local r, g, b, a = colorToBytes(rect.Color)
	skia.lib.Kine_Skia_Surface_DrawRotatedRect(
		context,
		rect.x,
		rect.y,
		rect.width,
		rect.height,
		rotationDegrees,
		r,
		g,
		b,
		a,
		rect.isOutline and 2 or 0
	)
end

function SkiaAdapter:DrawCircle(context, center, radius: number, color: typedefs.Color, strokeWidth: number?)
	local r, g, b, a = colorToBytes(color)
	skia.lib.Kine_Skia_Surface_DrawCircle(context, center.X, center.Y, radius, r, g, b, a, strokeWidth or 0)
end

function SkiaAdapter:DrawLine(context, from, to, strokeWidth: number, color: typedefs.Color)
	local r, g, b, a = colorToBytes(color)
	skia.lib.Kine_Skia_Surface_DrawLine(context, from.X, from.Y, to.X, to.Y, strokeWidth, r, g, b, a)
end

function SkiaAdapter:DrawPolygon(context, points, closed: boolean, color: typedefs.Color, strokeWidth: number?)
	if type(points) ~= "table" or #points < 2 then
		return
	end
	local data = zune.ffi.alloc(#points * 8)
	for index, point in ipairs(points) do
		local offset = (index - 1) * 8
		data:writef32(offset, point.X)
		data:writef32(offset + 4, point.Y)
	end
	local r, g, b, a = colorToBytes(color)
	skia.lib.Kine_Skia_Surface_DrawPolygon(context, data, #points, closed and 1 or 0, r, g, b, a, strokeWidth or 0)
	zune.ffi.free(data)
end

function SkiaAdapter:GetPixel(context, x: number, y: number)
	local rgba = zune.ffi.alloc(4)
	skia.lib.Kine_Skia_Surface_GetPixel(context, x, y, rgba, rgba:offset(1), rgba:offset(2), rgba:offset(3))
	local color = {
		R = rgba:readu8(0) / 255,
		G = rgba:readu8(1) / 255,
		B = rgba:readu8(2) / 255,
		A = rgba:readu8(3) / 255,
	}
	zune.ffi.free(rgba)
	return color
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

function SkiaAdapter:DrawImageRect(
	skiaSurface,
	image: typedefs.Image,
	sourceRect: typedefs.Rectangle,
	destinationRect: typedefs.Rectangle,
	alpha: number?
)
	skia.lib.Kine_Skia_Surface_DrawImageRect(
		skiaSurface,
		image._handle,
		sourceRect.x,
		sourceRect.y,
		sourceRect.width,
		sourceRect.height,
		destinationRect.x,
		destinationRect.y,
		destinationRect.width,
		destinationRect.height,
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
