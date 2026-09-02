-- description: "Owns compact 2D tile definitions shared by Layer2D children."
local Vector2 = require("@Vector2")
local Tile = require("@Tile")

local propTable = {
	Name = "Tilemap",
	BaseClass = "WorldObject2D",
	Position = Vector2.new(0, 0),
	TileSize = 32,
	Tiles = {},
	Visible = true,
	ZIndex = 0,
}

return {
	class = "Tilemap",
	callback = function(instance)
		instance:SetProperties(propTable)
		instance.Tiles = {}

		function instance:RegisterTile(id, definition)
			assert(type(id) == "number" and id > 0, "Tile IDs must be positive numbers")
			assert(type(definition) == "table", "Tile definitions must be Tile values or tables")
			local image = definition.Image or definition.Texture
			if image ~= nil then
				assert(
					type(image) == "string" or (type(image) == "table" and image._handle ~= nil),
					"Tile Image must be a path or an Argon image"
				)
				definition.Image = image
			end
			self.Tiles[id] = definition
			self.Tiles = self.Tiles
			return definition
		end

		function instance:RegisterImageTile(id, image, sourceRect)
			return self:RegisterTile(id, Tile.fromImage(image, sourceRect))
		end

		function instance:RemoveTile(id)
			self.Tiles[id] = nil
			self.Tiles = self.Tiles
		end

		function instance:GetTileDefinition(id)
			return self.Tiles[id]
		end

		return instance
	end,
}
