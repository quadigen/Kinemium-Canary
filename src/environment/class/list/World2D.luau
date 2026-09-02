-- description: "A first-class 2D world with an independent camera, renderer, and Box2D simulation."
local Color3 = require("@Color3")
local UDim2 = require("@UDim2")
local Vector2 = require("@Vector2")
local argon = require("@Argon")

local propTable = {
	Name = "World2D",
	BaseClass = "World2D",
	Enabled = true,
	Gravity = Vector2.new(0, 981),
	TimeScale = 1,
	Paused = false,
	Position = UDim2.new(0, 0, 0, 0),
	Size = UDim2.new(0, 400, 0, 400),
	RenderOffset = Vector2.new(0, 0),
	OverrideScreenSize = false,
	CurrentCamera = nil,
	BackgroundColor = Color3.new(0, 0, 0),
	BackgroundTransparency = 1,
	FixedDeltaTime = 1 / 60,
	ElapsedTime = 0,
	Accumulator = 0,
	contactHertz = 60,
	contactDampingRatio = 1,
	maximumLinearSpeed = 4000,
	maximumAngularSpeed = 4000,
	restitutionThreshold = 1,
	hitEventThreshold = 0,
	maxContactPushSpeed = 3,
	enableSleep = true,
	enableContinuous = true,
	workerCount = 0,
	MotionLocks = { LinearX = false, LinearY = false, AngularZ = false },
	Bodies = {},
	Constraints = {},
	CollisionLayers = {},
	UseBounds = false,
	MinBounds = Vector2.new(-math.huge, -math.huge),
	MaxBounds = Vector2.new(math.huge, math.huge),
	VelocityIterations = 8,
	PositionIterations = 3,
	AllowSleep = true,
	DebugDraw = false,
	DebugColor = Color3.new(0, 1, 0),
}

local function color(color3, transparency)
	return { R = color3.R, G = color3.G, B = color3.B, A = 1 - (transparency or 0) }
end

local function rotate(point, degrees)
	local angle = math.rad(degrees)
	local c, s = math.cos(angle), math.sin(angle)
	return Vector2.new(point.X * c - point.Y * s, point.X * s + point.Y * c)
end

local function firstCamera(world, workspace)
	if world.CurrentCamera and world.CurrentCamera.ClassName == "Camera2D" then
		return world.CurrentCamera
	end
	if workspace and workspace.CurrentCamera2D and workspace.CurrentCamera2D.ClassName == "Camera2D" then
		return workspace.CurrentCamera2D
	end
	for _, descendant in ipairs(world:GetDescendants()) do
		if descendant.ClassName == "Camera2D" then
			return descendant
		end
	end
	return nil
end

return {
	class = "World2D",
	callback = function(instance, renderer, game)
		instance:SetProperties(propTable)
		instance.Bodies = {}
		instance.Constraints = {}
		instance.CollisionLayers = {}

		local box2DService = game:GetService("Box2DService")
		local workspace = game:GetService("Workspace")
		local textureCache = {}

		local function viewportSize()
			if instance.OverrideScreenSize then
				return Vector2.new(instance.Size.X.Offset, instance.Size.Y.Offset)
			end
			local scale = argon:GetDPIScale(renderer.Window)
			return Vector2.new(renderer.Width / scale, renderer.Height / scale)
		end

		local function worldToScreen(point, camera, parallax, viewport)
			local factor = parallax or Vector2.new(1, 1)
			local cameraPosition = camera and camera.Position or Vector2.new(0, 0)
			local relative = Vector2.new(point.X - cameraPosition.X * factor.X, point.Y - cameraPosition.Y * factor.Y)
			local zoom = camera and math.max(camera.Zoom, 0.0001) or 1
			local rotation = camera and camera.Rotation or 0
			return instance.RenderOffset + viewport * 0.5 + rotate(relative, -rotation) * zoom
		end

		local function drawPart(object, camera, viewport, canvas)
			if object.Visible == false or object.Enabled == false or object.Transparency >= 1 then
				return
			end
			local zoom = camera and math.max(camera.Zoom, 0.0001) or 1
			local center = worldToScreen(object.Position, camera, nil, viewport)
			argon:DrawRotatedRectangle(canvas, {
				x = center.X,
				y = center.Y,
				width = object.Size.X * zoom,
				height = object.Size.Y * zoom,
				Color = color(object.Color, object.Transparency),
			}, (object.Rotation or 0) - (camera and camera.Rotation or 0))
		end

		local function tileTexture(source)
			if source == nil or source == "" then
				return nil
			end
			if type(source) == "table" and source._handle ~= nil then
				return source
			end
			if type(source) ~= "string" then
				return nil
			end
			if textureCache[source] == nil then
				textureCache[source] = argon:CreateImageFromPath(source) or false
			end
			return textureCache[source] or nil
		end

		local function tileSourceRect(definition)
			local rect = definition.SourceRect
			if rect then
				local x = rect.x or rect.X or 0
				local y = rect.y or rect.Y or 0
				local width = rect.width or rect.Width
				local height = rect.height or rect.Height
				if width and height and width > 0 and height > 0 then
					return { x = x, y = y, width = width, height = height }
				end
			end
			local offset = definition.ImageRectOffset
			local size = definition.ImageRectSize
			if offset and size and size.X > 0 and size.Y > 0 then
				return { x = offset.X, y = offset.Y, width = size.X, height = size.Y }
			end
			return nil
		end

		local function drawLayer(tilemap, layer, camera, viewport, canvas)
			if tilemap.Visible == false or layer.Visible == false then
				return
			end
			local tileSize = if layer.TileSize > 0 then layer.TileSize else tilemap.TileSize
			local zoom = camera and math.max(camera.Zoom, 0.0001) or 1
			local size = tileSize * zoom
			local origin = tilemap.Position + layer.Offset

			for y = 1, layer.Height do
				local tileRow = layer.Tiles[y]
				if not tileRow then
					continue
				end
				for x = 1, layer.Width do
					local tileId = tileRow[x] or 0
					local definition = tileId ~= 0 and tilemap.Tiles[tileId] or nil
					if not definition then
						continue
					end
					local tileCenter = origin + Vector2.new((x - 0.5) * tileSize, (y - 0.5) * tileSize)
					local screen = worldToScreen(tileCenter, camera, layer.Parallax, viewport)
					local rect = { x = screen.X - size * 0.5, y = screen.Y - size * 0.5, width = size, height = size }
					local image = tileTexture(definition.Image or definition.Texture)
					if image then
						local sourceRect = tileSourceRect(definition)
						if sourceRect then
							argon:DrawImageRect(canvas, image, sourceRect, rect, 1 - (definition.Transparency or 0))
						else
							argon:DrawImageSized(canvas, image, rect, 1 - (definition.Transparency or 0))
						end
					else
						local tileColor = definition.Color or Color3.new(1, 0, 1)
						rect.Color = color(tileColor, definition.Transparency)
						argon:DrawRectangle(canvas, rect)
					end
				end
			end
		end

		local function render()
			if not instance.Enabled then
				return
			end

			local canvas = renderer.Window
			local viewport = viewportSize()
			instance.Size = UDim2.new(0, viewport.X, 0, viewport.Y)
			local camera = firstCamera(instance, workspace)
			if camera then
				camera.ViewportSize = viewport
			end
			argon:Save(canvas)
			argon:ClipRoundRect(canvas, {
				x = instance.RenderOffset.X,
				y = instance.RenderOffset.Y,
				width = viewport.X,
				height = viewport.Y,
			}, 0, 0)

			if instance.BackgroundTransparency < 1 then
				argon:DrawRectangle(canvas, {
					x = instance.RenderOffset.X,
					y = instance.RenderOffset.Y,
					width = viewport.X,
					height = viewport.Y,
					Color = color(instance.BackgroundColor, instance.BackgroundTransparency),
				})
			end

			local drawables = {}
			for _, descendant in ipairs(instance:GetDescendants()) do
				if descendant.ClassName == "Part2D" then
					table.insert(drawables, { z = descendant.ZIndex or 0, kind = "part", object = descendant })
				elseif
					descendant.ClassName == "Layer2D"
					and descendant.Parent
					and descendant.Parent.ClassName == "Tilemap"
				then
					table.insert(drawables, {
						z = (descendant.Parent.ZIndex or 0) + (descendant.ZIndex or 0),
						kind = "layer",
						object = descendant,
						tilemap = descendant.Parent,
					})
				end
			end
			table.sort(drawables, function(a, b)
				return a.z < b.z
			end)
			for _, drawable in ipairs(drawables) do
				if drawable.kind == "part" then
					drawPart(drawable.object, camera, viewport, canvas)
				else
					drawLayer(drawable.tilemap, drawable.object, camera, viewport, canvas)
				end
			end
			argon:Restore(canvas)
		end

		local renderId = renderer.Pool.new("2da", render)
		if not box2DService or type(box2DService.init) ~= "function" then
			error("World2D requires the initialized Box2DService")
		end
		box2DService.init(instance, function(object, newPosition)
			object.Position = newPosition
		end)

		instance.Destroying:Connect(function()
			renderer.Pool.Destroy(renderId)
		end)

		return instance
	end,
	inherit = function(target)
		for key, value in pairs(propTable) do
			target[key] = value
		end
	end,
}
