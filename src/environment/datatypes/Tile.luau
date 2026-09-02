local Color3 = require("@Color3")
local Vector2 = require("@Vector2")

local Tile = { __type = "Tile" }
Tile.__index = Tile

local function copySourceRect(rect)
	if not rect then
		return nil
	end
	if rect.Min and rect.Max then
		return {
			x = rect.Min.X,
			y = rect.Min.Y,
			width = rect.Max.X - rect.Min.X,
			height = rect.Max.Y - rect.Min.Y,
		}
	end
	local width = rect.width or rect.Width
	local height = rect.height or rect.Height
	assert(type(width) == "number" and width > 0, "Tile SourceRect width must be positive")
	assert(type(height) == "number" and height > 0, "Tile SourceRect height must be positive")
	return {
		x = rect.x or rect.X or 0,
		y = rect.y or rect.Y or 0,
		width = width,
		height = height,
	}
end

local function isColor3(value)
	return type(value) == "table" and value.__type == "Color3"
end

function Tile.new(options)
	if options == nil then
		options = {}
	elseif type(options) == "string" then
		options = { Image = options }
	elseif isColor3(options) then
		options = { Color = options }
	end
	assert(type(options) == "table", "Tile.new expects an options table, image path, or Color3")

	local image = options.Image or options.Texture
	if image ~= nil then
		assert(
			type(image) == "string" or (type(image) == "table" and image._handle ~= nil),
			"Tile Image must be a path or an Argon image"
		)
	end
	local color = options.Color or Color3.new(1, 1, 1)
	assert(isColor3(color), "Tile Color must be a Color3")

	return setmetatable({
		__type = "Tile",
		Name = options.Name or "Tile",
		Image = image,
		Color = color,
		Transparency = math.clamp(options.Transparency or 0, 0, 1),
		SourceRect = copySourceRect(options.SourceRect),
		ImageRectOffset = options.ImageRectOffset,
		ImageRectSize = options.ImageRectSize,
		Metadata = options.Metadata,
	}, Tile)
end

function Tile.fromImage(image, sourceRect)
	return Tile.new({ Image = image, SourceRect = sourceRect })
end

function Tile.fromColor(color)
	return Tile.new({ Color = color })
end

function Tile:Clone()
	return Tile.new({
		Name = self.Name,
		Image = self.Image,
		Color = self.Color,
		Transparency = self.Transparency,
		SourceRect = self.SourceRect,
		ImageRectOffset = self.ImageRectOffset,
		ImageRectSize = self.ImageRectSize,
		Metadata = self.Metadata,
	})
end

function Tile:ToTable()
	return {
		type = "Tile",
		Name = self.Name,
		Image = type(self.Image) == "string" and self.Image or nil,
		Color = self.Color:ToTable(),
		Transparency = self.Transparency,
		SourceRect = self.SourceRect and {
			x = self.SourceRect.x,
			y = self.SourceRect.y,
			width = self.SourceRect.width,
			height = self.SourceRect.height,
		} or nil,
		ImageRectOffset = self.ImageRectOffset and self.ImageRectOffset:ToTable() or nil,
		ImageRectSize = self.ImageRectSize and self.ImageRectSize:ToTable() or nil,
		Metadata = self.Metadata,
	}
end

function Tile.FromTable(value)
	assert(value.type == "Tile" or value.__type == "Tile", "Table is not a Tile")
	return Tile.new({
		Name = value.Name,
		Image = value.Image,
		Color = value.Color and Color3.FromTable(value.Color) or nil,
		Transparency = value.Transparency,
		SourceRect = value.SourceRect,
		ImageRectOffset = value.ImageRectOffset and Vector2.FromTable(value.ImageRectOffset) or nil,
		ImageRectSize = value.ImageRectSize and Vector2.FromTable(value.ImageRectSize) or nil,
		Metadata = value.Metadata,
	})
end

function Tile:__tostring()
	if self.Image then
		return string.format("Tile(%s, %s)", self.Name, tostring(self.Image))
	end
	return string.format("Tile(%s)", self.Name)
end

return Tile
