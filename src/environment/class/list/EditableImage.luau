-- description: "A mutable Argon/Skia image that can be drawn onto and modified at runtime."
local Vector2 = require("@Vector2")
local Color3 = require("@Color3")
local argon = require("@Argon")

local propTable = {
	Size = Vector2.new(1024, 1024),
	Name = "EditableImage",
	BaseClass = "Instance",
}

local function byte(value)
	return math.clamp(math.floor((tonumber(value) or 0) * 255 + 0.5), 0, 255)
end

local function rgba(color, transparency)
	return {
		R = math.clamp(tonumber(color and color.R) or 0, 0, 1),
		G = math.clamp(tonumber(color and color.G) or 0, 0, 1),
		B = math.clamp(tonumber(color and color.B) or 0, 0, 1),
		A = 1 - math.clamp(tonumber(transparency) or 0, 0, 1),
	}
end

local function dimensions(value)
	return math.max(1, math.floor(tonumber(value.X) or 1)), math.max(1, math.floor(tonumber(value.Y) or 1))
end

return {
	class = "EditableImage",
	callback = function(instance)
		instance:SetProperties(propTable)
		local resizing, destroyed = false, false

		local function destroySurface()
			if instance._surface then
				argon:DestroySkiaSurface(instance._surface._uihandle)
			end
			instance._surface, instance._image = nil, nil
		end

		local function createSurface(size)
			local width, height = dimensions(size)
			destroySurface()
			instance._surface = argon:CreateSkiaSurface(width, height)
			instance._image = instance._surface -- backwards-compatible backing image handle
			instance._texture = nil
			argon:Clear2D(instance._surface, { R = 0, G = 0, B = 0, A = 0 })
			return width, height
		end

		local function surfacePixels()
			return argon:GetSurfacePixels(instance._surface)
		end

		local function getPixelBytes(x, y)
			local width, height = dimensions(instance.Size)
			x, y = math.floor(x), math.floor(y)
			if x < 0 or y < 0 or x >= width or y >= height then return 0, 0, 0, 0 end
			local pixels, pitch = surfacePixels()
			if not pixels then return 0, 0, 0, 0 end
			local offset = y * pitch + x * 4
			local r, g, b, a = pixels:readu8(offset), pixels:readu8(offset + 1), pixels:readu8(offset + 2), pixels:readu8(offset + 3)
			if a == 0 then return 0, 0, 0, 0 end
			return math.min(255, math.floor(r * 255 / a + 0.5)),
				math.min(255, math.floor(g * 255 / a + 0.5)),
				math.min(255, math.floor(b * 255 / a + 0.5)), a
		end

		local function setPixelBytes(x, y, r, g, b, a)
			local width, height = dimensions(instance.Size)
			x, y = math.floor(x), math.floor(y)
			if x < 0 or y < 0 or x >= width or y >= height then return false end
			local pixels, pitch = surfacePixels()
			if not pixels then return false end
			r, g, b, a = math.clamp(math.floor(r or 0), 0, 255), math.clamp(math.floor(g or 0), 0, 255),
				math.clamp(math.floor(b or 0), 0, 255), math.clamp(math.floor(a or 0), 0, 255)
			local offset = y * pitch + x * 4
			pixels:writeu8(offset, math.floor(r * a / 255 + 0.5))
			pixels:writeu8(offset + 1, math.floor(g * a / 255 + 0.5))
			pixels:writeu8(offset + 2, math.floor(b * a / 255 + 0.5))
			pixels:writeu8(offset + 3, a)
			return true
		end

		local function blendPixel(x, y, r, g, b, a)
			if a <= 0 then return end
			local dr, dg, db, da = getPixelBytes(x, y)
			local sa, destinationAlpha = a / 255, da / 255
			local outputAlpha = sa + destinationAlpha * (1 - sa)
			if outputAlpha <= 0 then setPixelBytes(x, y, 0, 0, 0, 0) return end
			setPixelBytes(x, y,
				(r * sa + dr * destinationAlpha * (1 - sa)) / outputAlpha,
				(g * sa + dg * destinationAlpha * (1 - sa)) / outputAlpha,
				(b * sa + db * destinationAlpha * (1 - sa)) / outputAlpha,
				outputAlpha * 255)
		end

		local function snapshot()
			return instance:ReadPixelsBuffer(Vector2.new(0, 0), instance.Size)
		end

		local function replaceFromBuffer(width, height, data)
			resizing = true
			rawget(instance, "_props").Size = Vector2.new(width, height)
			createSurface(instance.Size)
			instance:WritePixelsBuffer(Vector2.new(0, 0), instance.Size, data)
			resizing = false
			instance._dirty = true
		end

		createSurface(instance.Size)
		instance._dirty = false
		instance.Changed:Connect(function(property)
			if property == "Size" and not resizing and not destroyed then
				createSurface(instance.Size)
				instance._dirty = true
			end
		end)
		instance.Destroying:Connect(function()
			destroyed = true
			destroySurface()
		end)

		function instance:DrawCircle(center, radius, color, transparency, _combineType)
			argon:DrawCircle(self._surface, center, radius, rgba(color, transparency), 0)
			self._dirty = true
		end
		function instance:DrawCircleLines(center, radius, color, transparency)
			argon:DrawCircle(self._surface, center, radius, rgba(color, transparency), 1)
			self._dirty = true
		end
		function instance:DrawRectangle(position, size, color, transparency, _combineType)
			argon:DrawRectangle(self._surface, { x = position.X, y = position.Y, width = size.X, height = size.Y, Color = rgba(color, transparency) })
			self._dirty = true
		end
		instance.DrawRectangleV = instance.DrawRectangle
		function instance:DrawRectangleLines(position, size, thickness, color, transparency)
			thickness = math.max(1, tonumber(thickness) or 1)
			local c, bottomRight = rgba(color, transparency), position + size
			argon:DrawLine(self._surface, position, Vector2.new(bottomRight.X, position.Y), thickness, c)
			argon:DrawLine(self._surface, Vector2.new(bottomRight.X, position.Y), bottomRight, thickness, c)
			argon:DrawLine(self._surface, bottomRight, Vector2.new(position.X, bottomRight.Y), thickness, c)
			argon:DrawLine(self._surface, Vector2.new(position.X, bottomRight.Y), position, thickness, c)
			self._dirty = true
		end
		function instance:DrawRectangleOutline(position, size, color, transparency, thickness)
			self:DrawRectangleLines(position, size, thickness, color, transparency)
		end
		function instance:DrawLine(from, to, color, transparency, _combineType)
			self:DrawLineEx(from, to, 1, color, transparency)
		end
		function instance:DrawLineEx(from, to, thickness, color, transparency)
			argon:DrawLine(self._surface, from, to, math.max(0.5, tonumber(thickness) or 1), rgba(color, transparency))
			self._dirty = true
		end
		function instance:DrawTriangle(v1, v2, v3, color, transparency)
			argon:DrawPolygon(self._surface, { v1, v2, v3 }, true, rgba(color, transparency), 0)
			self._dirty = true
		end
		function instance:DrawTriangleEx(v1, v2, v3, color1, color2, color3, transparency)
			self:DrawTriangle(v1, v2, v3, Color3.new((color1.R + color2.R + color3.R) / 3, (color1.G + color2.G + color3.G) / 3, (color1.B + color2.B + color3.B) / 3), transparency)
		end
		function instance:DrawTriangleLines(v1, v2, v3, color, transparency)
			argon:DrawPolygon(self._surface, { v1, v2, v3 }, true, rgba(color, transparency), 1)
			self._dirty = true
		end
		function instance:DrawText(text, position, fontSize, color, transparency)
			self:DrawTextEx(nil, text, position, fontSize, 0, color, transparency)
		end
		function instance:DrawTextEx(font, text, position, fontSize, _spacing, color, transparency)
			local resolvedFont = if type(font) == "string" then argon:CreateFont(font) else font
			resolvedFont = resolvedFont or argon:CreateFont("./src/assets/fonts/Montserrat-Medium.ttf")
			argon:DrawText(self._surface, tostring(text), { X = position.X, Y = position.Y + (tonumber(fontSize) or 16), TextSize = tonumber(fontSize) or 16, Font = resolvedFont, Color = rgba(color, transparency) })
			self._dirty = true
		end

		function instance:ReadPixelsBuffer(position, size)
			local width, height = dimensions(size)
			local data = buffer.create(width * height * 4)
			for y = 0, height - 1 do
				for x = 0, width - 1 do
					local r, g, b, a = getPixelBytes(position.X + x, position.Y + y)
					local offset = (y * width + x) * 4
					buffer.writeu8(data, offset, r) buffer.writeu8(data, offset + 1, g)
					buffer.writeu8(data, offset + 2, b) buffer.writeu8(data, offset + 3, a)
				end
			end
			return data
		end
		function instance:WritePixelsBuffer(position, size, data)
			local width, height, available = dimensions(size)
			available = buffer.len(data)
			for y = 0, height - 1 do
				for x = 0, width - 1 do
					local offset = (y * width + x) * 4
					if offset + 3 < available then
						setPixelBytes(position.X + x, position.Y + y, buffer.readu8(data, offset), buffer.readu8(data, offset + 1), buffer.readu8(data, offset + 2), buffer.readu8(data, offset + 3))
					end
				end
			end
			self._dirty = true
		end
		function instance:SetPixelColor(position, color, transparency)
			local c = rgba(color, transparency)
			setPixelBytes(position.X, position.Y, byte(c.R), byte(c.G), byte(c.B), byte(c.A))
			self._dirty = true
		end
		instance.DrawPixel = instance.SetPixelColor
		function instance:GetPixelColor(position)
			local color = argon:GetSurfacePixel(self._surface, math.floor(position.X), math.floor(position.Y))
			return Color3.new(color.R, color.G, color.B)
		end
		function instance:Clear(color, transparency)
			argon:Clear2D(self._surface, rgba(color, transparency))
			self._dirty = true
		end
		instance.Fill = instance.Clear

		function instance:DrawImage(position, image, _combineType)
			if not image or not image.ReadPixelsBuffer then return end
			local width, height = dimensions(image.Size)
			local data = image:ReadPixelsBuffer(Vector2.new(0, 0), image.Size)
			for y = 0, height - 1 do
				for x = 0, width - 1 do
					local offset = (y * width + x) * 4
					blendPixel(position.X + x, position.Y + y, buffer.readu8(data, offset), buffer.readu8(data, offset + 1), buffer.readu8(data, offset + 2), buffer.readu8(data, offset + 3))
				end
			end
			self._dirty = true
		end
		function instance:DrawImageTransformed(position, scale, rotation, image, _options)
			if not image or not image.ReadPixelsBuffer then return end
			local sourceWidth, sourceHeight = dimensions(image.Size)
			local data = image:ReadPixelsBuffer(Vector2.new(0, 0), image.Size)
			local scaleX, scaleY = math.max(0.001, math.abs(scale.X)), math.max(0.001, math.abs(scale.Y))
			local targetWidth, targetHeight = math.max(1, math.floor(sourceWidth * scaleX)), math.max(1, math.floor(sourceHeight * scaleY))
			local radians = math.rad(tonumber(rotation) or 0)
			local cosine, sine = math.cos(radians), math.sin(radians)
			for y = 0, targetHeight - 1 do
				for x = 0, targetWidth - 1 do
					local rx, ry = x - targetWidth * 0.5, y - targetHeight * 0.5
					local sx = math.floor((rx * cosine + ry * sine) / scaleX + sourceWidth * 0.5)
					local sy = math.floor((-rx * sine + ry * cosine) / scaleY + sourceHeight * 0.5)
					if sx >= 0 and sy >= 0 and sx < sourceWidth and sy < sourceHeight then
						local offset = (sy * sourceWidth + sx) * 4
						blendPixel(position.X + x, position.Y + y, buffer.readu8(data, offset), buffer.readu8(data, offset + 1), buffer.readu8(data, offset + 2), buffer.readu8(data, offset + 3))
					end
				end
			end
			self._dirty = true
		end
		function instance:DrawImageProjected(mesh, _projection, brushConfig)
			if not mesh or not mesh.GetFaces then return end
			local color = brushConfig and brushConfig.Color or Color3.new(1, 1, 1)
			for _, faceId in ipairs(mesh:GetFaces()) do
				local vertices, points = mesh:GetFaceVertices(faceId), {}
				if #vertices == 3 then
					for index, vertexId in ipairs(vertices) do
						local point = mesh:GetPosition(vertexId)
						points[index] = Vector2.new((point.X + 1) * 0.5 * self.Size.X, (point.Y + 1) * 0.5 * self.Size.Y)
					end
					self:DrawTriangle(points[1], points[2], points[3], color, 0)
				end
			end
		end

		local function remapPixels(self, width, height, mapper)
			local sourceWidth, sourceHeight, source = dimensions(self.Size)
			source = snapshot()
			local output = buffer.create(width * height * 4)
			for y = 0, height - 1 do
				for x = 0, width - 1 do
					local sx, sy = mapper(x, y, sourceWidth, sourceHeight)
					local destinationOffset = (y * width + x) * 4
					if sx >= 0 and sy >= 0 and sx < sourceWidth and sy < sourceHeight then
						local sourceOffset = (math.floor(sy) * sourceWidth + math.floor(sx)) * 4
						for index = 0, 3 do buffer.writeu8(output, destinationOffset + index, buffer.readu8(source, sourceOffset + index)) end
					end
				end
			end
			replaceFromBuffer(width, height, output)
		end
		function instance:Resize(newSize)
			local width, height = dimensions(newSize)
			remapPixels(self, width, height, function(x, y, sw, sh) return x * sw / width, y * sh / height end)
		end
		function instance:Crop(position, size)
			local width, height = dimensions(size)
			remapPixels(self, width, height, function(x, y) return position.X + x, position.Y + y end)
		end
		function instance:FlipHorizontal()
			local width, height = dimensions(self.Size)
			remapPixels(self, width, height, function(x, y, sw) return sw - 1 - x, y end)
		end
		function instance:FlipVertical()
			local width, height = dimensions(self.Size)
			remapPixels(self, width, height, function(x, y, _, sh) return x, sh - 1 - y end)
		end
		function instance:Flip(horizontal, vertical)
			if horizontal then self:FlipHorizontal() end
			if vertical then self:FlipVertical() end
		end
		function instance:Rotate(angle)
			local sw, sh = dimensions(self.Size)
			local radians = math.rad(tonumber(angle) or 0)
			local cosine, sine = math.cos(radians), math.sin(radians)
			local width = math.max(1, math.ceil(math.abs(sw * cosine) + math.abs(sh * sine)))
			local height = math.max(1, math.ceil(math.abs(sw * sine) + math.abs(sh * cosine)))
			remapPixels(self, width, height, function(x, y)
				local rx, ry = x - width * 0.5, y - height * 0.5
				return rx * cosine + ry * sine + sw * 0.5, -rx * sine + ry * cosine + sh * 0.5
			end)
		end

		local function filterPixels(self, transform)
			local width, height, data = dimensions(self.Size)
			data = snapshot()
			for offset = 0, width * height * 4 - 4, 4 do
				local r, g, b, a = transform(buffer.readu8(data, offset), buffer.readu8(data, offset + 1), buffer.readu8(data, offset + 2), buffer.readu8(data, offset + 3))
				buffer.writeu8(data, offset, math.clamp(math.floor(r + 0.5), 0, 255))
				buffer.writeu8(data, offset + 1, math.clamp(math.floor(g + 0.5), 0, 255))
				buffer.writeu8(data, offset + 2, math.clamp(math.floor(b + 0.5), 0, 255))
				buffer.writeu8(data, offset + 3, math.clamp(math.floor(a + 0.5), 0, 255))
			end
			self:WritePixelsBuffer(Vector2.new(0, 0), self.Size, data)
		end
		function instance:ApplyGrayscale()
			filterPixels(self, function(r, g, b, a) local l = r * 0.2126 + g * 0.7152 + b * 0.0722 return l, l, l, a end)
		end
		function instance:ApplyInvert() filterPixels(self, function(r, g, b, a) return 255 - r, 255 - g, 255 - b, a end) end
		function instance:ApplyContrast(contrast)
			contrast = math.clamp(tonumber(contrast) or 0, -255, 254)
			local factor = (259 * (contrast + 255)) / (255 * (259 - contrast))
			filterPixels(self, function(r, g, b, a) return factor * (r - 128) + 128, factor * (g - 128) + 128, factor * (b - 128) + 128, a end)
		end
		function instance:ApplyBrightness(brightness)
			brightness = tonumber(brightness) or 0
			filterPixels(self, function(r, g, b, a) return r + brightness, g + brightness, b + brightness, a end)
		end
		function instance:ColorReplace(oldColor, newColor)
			local oldR, oldG, oldB, newR, newG, newB = byte(oldColor.R), byte(oldColor.G), byte(oldColor.B), byte(newColor.R), byte(newColor.G), byte(newColor.B)
			filterPixels(self, function(r, g, b, a) if r == oldR and g == oldG and b == oldB then return newR, newG, newB, a end return r, g, b, a end)
		end
		function instance:Blur(strength)
			local radius = math.max(1, math.floor(tonumber(strength) or 1))
			local width, height, source = dimensions(self.Size)
			source = snapshot()
			local output = buffer.create(buffer.len(source))
			for y = 0, height - 1 do
				for x = 0, width - 1 do
					local sums, count = { 0, 0, 0, 0 }, 0
					for oy = -radius, radius do for ox = -radius, radius do
						local sx, sy = x + ox, y + oy
						if sx >= 0 and sy >= 0 and sx < width and sy < height then
							local offset = (sy * width + sx) * 4
							for index = 1, 4 do sums[index] += buffer.readu8(source, offset + index - 1) end count += 1
						end
					end end
					local offset = (y * width + x) * 4
					for index = 1, 4 do buffer.writeu8(output, offset + index - 1, math.floor(sums[index] / count + 0.5)) end
				end
			end
			self:WritePixelsBuffer(Vector2.new(0, 0), self.Size, output)
		end
		function instance:Sharpen()
			local width, height, source = dimensions(self.Size)
			source = snapshot()
			local output, kernel = buffer.create(buffer.len(source)), { 0, -1, 0, -1, 5, -1, 0, -1, 0 }
			for y = 0, height - 1 do for x = 0, width - 1 do
				local offset = (y * width + x) * 4
				for channelIndex = 0, 2 do
					local sum, kernelIndex = 0, 1
					for oy = -1, 1 do for ox = -1, 1 do
						local sx, sy = math.clamp(x + ox, 0, width - 1), math.clamp(y + oy, 0, height - 1)
						sum += buffer.readu8(source, (sy * width + sx) * 4 + channelIndex) * kernel[kernelIndex] kernelIndex += 1
					end end
					buffer.writeu8(output, offset + channelIndex, math.clamp(math.floor(sum + 0.5), 0, 255))
				end
				buffer.writeu8(output, offset + 3, buffer.readu8(source, offset + 3))
			end end
			self:WritePixelsBuffer(Vector2.new(0, 0), self.Size, output)
		end
		function instance:DrawGradient(fromPosition, toPosition, color1, color2, transparency)
			local width, height = dimensions(self.Size)
			local dx, dy = toPosition.X - fromPosition.X, toPosition.Y - fromPosition.Y
			local denominator, alpha = math.max(dx * dx + dy * dy, 1e-6), byte(1 - math.clamp(tonumber(transparency) or 0, 0, 1))
			for y = 0, height - 1 do for x = 0, width - 1 do
				local t = math.clamp(((x - fromPosition.X) * dx + (y - fromPosition.Y) * dy) / denominator, 0, 1)
				setPixelBytes(x, y, byte(color1.R + (color2.R - color1.R) * t), byte(color1.G + (color2.G - color1.G) * t), byte(color1.B + (color2.B - color1.B) * t), alpha)
			end end
			self._dirty = true
		end

		function instance:AlphaMask(mask)
			if not mask or not mask.ReadPixelsBuffer then return end
			local width, height, data = dimensions(self.Size)
			data = snapshot()
			local maskData = mask:ReadPixelsBuffer(Vector2.new(0, 0), Vector2.new(width, height))
			for offset = 0, width * height * 4 - 4, 4 do buffer.writeu8(data, offset + 3, math.floor(buffer.readu8(data, offset + 3) * buffer.readu8(maskData, offset + 3) / 255 + 0.5)) end
			self:WritePixelsBuffer(Vector2.new(0, 0), self.Size, data)
		end
		function instance:GetImageAlphaBorder()
			local width, height = dimensions(self.Size)
			local minX, minY, maxX, maxY = width, height, -1, -1
			for y = 0, height - 1 do for x = 0, width - 1 do local _, _, _, a = getPixelBytes(x, y) if a > 0 then minX, minY, maxX, maxY = math.min(minX, x), math.min(minY, y), math.max(maxX, x), math.max(maxY, y) end end end
			if maxX < minX then return { x = 0, y = 0, width = 0, height = 0 } end
			return { x = minX, y = minY, width = maxX - minX + 1, height = maxY - minY + 1 }
		end
		function instance:AlphaCrop(alphaThreshold)
			local border, threshold = self:GetImageAlphaBorder(), math.clamp(tonumber(alphaThreshold) or 0, 0, 1)
			if threshold > 0 then
				local width, height = dimensions(self.Size) local minX, minY, maxX, maxY = width, height, -1, -1
				for y = 0, height - 1 do for x = 0, width - 1 do local _, _, _, a = getPixelBytes(x, y) if a > threshold * 255 then minX, minY, maxX, maxY = math.min(minX, x), math.min(minY, y), math.max(maxX, x), math.max(maxY, y) end end end
				border = if maxX >= minX then { x = minX, y = minY, width = maxX - minX + 1, height = maxY - minY + 1 } else border
			end
			if border.width > 0 then self:Crop(Vector2.new(border.x, border.y), Vector2.new(border.width, border.height)) end
		end
		function instance:AlphaClear(color, transparency)
			local c = rgba(color, transparency)
			filterPixels(self, function(r, g, b, a) if a <= 127 then return byte(c.R), byte(c.G), byte(c.B), byte(c.A) end return r, g, b, a end)
		end
		function instance:AlphaPremultiply() self._dirty = true end -- Skia surfaces are already premultiplied.
		function instance:Dither(rBits, gBits, bBits, aBits)
			local function quantize(value, bits) local levels = math.max(1, 2 ^ math.clamp(math.floor(bits or 8), 1, 8) - 1) return math.floor(value / 255 * levels + 0.5) / levels * 255 end
			filterPixels(self, function(r, g, b, a) return quantize(r, rBits), quantize(g, gBits), quantize(b, bBits), quantize(a, aBits) end)
		end
		function instance:ExportToFile(_filepath)
			warn("EditableImage:ExportToFile requires an Argon Skia encoder, which is not exposed yet")
			return false
		end
		function instance:GetDimensions() return Vector2.new(self.Size.X, self.Size.Y) end
		function instance:GetArea() return self.Size.X * self.Size.Y end
		function instance:IsDirty() return self._dirty end
		function instance:MarkDirty() self._dirty = true end
		function instance:ClearDirty() self._dirty = false end

		return instance
	end,
	inherit = function() return propTable end,
}
