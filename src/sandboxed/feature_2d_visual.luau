if not FlagExists("feature_2d_visual") then
	return
end

local world = Instance.new("World2D")
world.Name = "Argon2DValidation"
world.OverrideScreenSize = true
world.RenderOffset = Vector2.new(18, 112)
world.Size = UDim2.new(0, 760, 0, 560)
world.BackgroundColor = Color3.fromRGB(10, 16, 34)
world.BackgroundTransparency = 0
world.Gravity = Vector2.new(0, 80)
world.Parent = workspace

local camera = Instance.new("Camera2D")
camera.Position = Vector2.new(0, 0)
camera.Zoom = 1
camera.Rotation = -4
camera.Parent = world
world.CurrentCamera = camera

local colors = {
	Color3.fromRGB(255, 76, 120),
	Color3.fromRGB(255, 190, 45),
	Color3.fromRGB(40, 220, 190),
	Color3.fromRGB(95, 130, 255),
}
for index = 1, 12 do
	local part = Instance.new("Part2D")
	local angle = index / 12 * math.pi * 2
	part.Position = Vector2.new(math.cos(angle) * 235, math.sin(angle) * 180)
	part.Size = Vector2.new(82, 42)
	part.Rotation = index * 19
	part.Color = colors[(index - 1) % #colors + 1]
	part.Anchored = true
	part.ZIndex = 2
	part.Parent = world
end

local center = Instance.new("Part2D")
center.Position = Vector2.new(0, 0)
center.Size = Vector2.new(250, 130)
center.Rotation = 12
center.Color = Color3.fromRGB(220, 70, 255)
center.Anchored = true
center.ZIndex = 3
center.Parent = world

local falling = Instance.new("Part2D")
falling.Name = "Box2DDynamicBody"
falling.Position = Vector2.new(330, -220)
falling.Size = Vector2.new(62, 62)
falling.Color = Color3.fromRGB(255, 255, 255)
falling.Anchored = false
falling.ZIndex = 4
falling.Parent = world

local floor = Instance.new("Part2D")
floor.Name = "Box2DFloor"
floor.Position = Vector2.new(0, 190)
floor.Size = Vector2.new(760, 32)
floor.Color = Color3.fromRGB(80, 210, 255)
floor.Anchored = true
floor.ZIndex = 2
floor.Parent = world

local tilemap = Instance.new("Tilemap")
tilemap.Position = Vector2.new(-470, -370)
tilemap.ZIndex = 0
tilemap:RegisterTile(1, Tile.new({ Name = "GridA", Color = Color3.fromRGB(20, 45, 78) }))
tilemap:RegisterTile(2, Tile.fromColor(Color3.fromRGB(28, 60, 98)))
tilemap:RegisterTile(3, Tile.fromImage("./src/assets/images/icons/Part.png"))
tilemap.Parent = world

local layer = Instance.new("Layer2D")
layer.Width, layer.Height, layer.TileSize = 30, 24, 36
for y = 1, layer.Height do
	for x = 1, layer.Width do
		layer:SetTile(x, y, if (x + y * 3) % 17 == 0 then 3 else (x + y) % 2 + 1)
	end
end
layer.Parent = tilemap
