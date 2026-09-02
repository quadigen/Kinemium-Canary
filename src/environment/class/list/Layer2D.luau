-- description: "A compact tile grid that must be parented to a Tilemap."
local Vector2 = require("@Vector2")

local propTable = {
	Name = "Layer2D",
	BaseClass = "WorldObject2D",
	Width = 0,
	Height = 0,
	TileSize = 0,
	Tiles = {},
	Visible = true,
	ZIndex = 0,
	Offset = Vector2.new(0, 0),
	Parallax = Vector2.new(1, 1),
	CollisionEnabled = false,
}

local function row(layer, y, create)
	local result = layer.Tiles[y]
	if not result and create then
		result = {}
		layer.Tiles[y] = result
	end
	return result
end

return {
	class = "Layer2D",
	callback = function(instance)
		instance:SetProperties(propTable)
		instance.Tiles = {}

		function instance:SetTile(x, y, tileId)
			assert(x >= 1 and y >= 1, "Tile coordinates are one-based")
			row(self, y, true)[x] = tileId or 0
			self.Width = math.max(self.Width, x)
			self.Height = math.max(self.Height, y)
			self.Tiles = self.Tiles
		end

		function instance:GetTile(x, y)
			local tileRow = row(self, y, false)
			return tileRow and tileRow[x] or 0
		end

		function instance:Fill(tileId)
			for y = 1, self.Height do
				local tileRow = row(self, y, true)
				for x = 1, self.Width do
					tileRow[x] = tileId or 0
				end
			end
			self.Tiles = self.Tiles
		end

		instance:SetBarrier("Parent", function(parent)
			if parent ~= nil and parent.ClassName ~= "Tilemap" then
				warn("Layer2D.Parent must be a Tilemap")
				return false
			end
			return true
		end)

		return instance
	end,
}
