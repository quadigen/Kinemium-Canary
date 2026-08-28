-- description: "Renders GUI children on a camera-facing plane in 3D."
local Vector2 = require("@Vector2")
local Vector3 = require("@Vector3")
local CFrame = require("@CFrame")
local UDim2 = require("@UDim2")
local argon = require("@Argon")

local propTable = {
	Name = "BillboardGui",
	Enabled = true,
	Camera = nil,
	Size = UDim2.new(0, 200, 0, 100),
	RenderOffset = Vector2.new(0, 0),
	Adornee = nil,
	StudsOffset = Vector3.new(0, 0, 0),
	StudsOffsetWorldSpace = Vector3.new(0, 0, 0),
	PixelsPerStud = 50,
	MaxDistance = 0,
	AlwaysOnTop = true,
	BaseClass = "UIContainer",
}

local function getAdorneePosition(instance)
	local adornee = instance.Adornee or instance.Parent
	if not adornee then
		return nil
	end
	local offset = instance.StudsOffset or Vector3.new(0, 0, 0)
	local worldOffset = instance.StudsOffsetWorldSpace or Vector3.new(0, 0, 0)
	if adornee.CFrame then
		return adornee.CFrame * offset + worldOffset
	end
	if adornee.WorldPosition then
		return adornee.WorldPosition + offset + worldOffset
	end
	if adornee.Position then
		return adornee.Position + offset + worldOffset
	end
	return nil
end

return {
	class = "BillboardGui",
	callback = function(instance, renderer, datamodel)
		instance:SetProperties(propTable)
		if _G.IsHeadless or not renderer or not renderer.Window then
			return instance
		end

		local surface, texture, decal
		local canvasWidth, canvasHeight, worldWidth, worldHeight = 0, 0, 1, 1
		local function desiredSize()
			local pps = math.max(1, instance.PixelsPerStud or 50)
			local size = instance.Size or UDim2.new(0, 200, 0, 100)
			worldWidth = math.max(0.01, (size.X.Scale or 0) + (size.X.Offset or 0) / pps)
			worldHeight = math.max(0.01, (size.Y.Scale or 0) + (size.Y.Offset or 0) / pps)
			return math.max(1, math.floor(worldWidth * pps + 0.5)), math.max(1, math.floor(worldHeight * pps + 0.5))
		end
		local function destroyResources()
			if decal then
				argon:RemoveDecal(renderer.Window, decal)
				decal = nil
			end
			if texture then
				argon:Destroy3DTexture(renderer.Window, texture)
				texture = nil
			end
			if surface then
				argon:DestroySkiaSurface(surface._uihandle)
				surface = nil
			end
		end
		local function ensureResources()
			local width, height = desiredSize()
			if surface and width == canvasWidth and height == canvasHeight then
				return decal ~= nil
			end
			destroyResources()
			canvasWidth, canvasHeight = width, height
			instance.RenderOffset = Vector2.new(0, 0)
			instance.AbsolutePosition, instance.AbsoluteSize = Vector2.new(0, 0), Vector2.new(width, height)
			surface = argon:CreateSkiaSurface(width, height)
			argon:Clear2D(surface, { R = 0, G = 0, B = 0, A = 0 })
			texture = argon:CreateSurface3DTexture(renderer.Window, surface)
			if texture then
				decal = argon:CreateDecal(renderer.Window, 1, 1, texture, 0, 0, 0, 0)
			end
			return decal ~= nil
		end

		ensureResources()
		local render2dId = renderer.Pool.new("2d", function()
			if not instance.Enabled or not ensureResources() then
				return
			end
			argon:Clear2D(surface, { R = 0, G = 0, B = 0, A = 0 })
			for _, child in ipairs(instance:GetChildren()) do
				if child.render then
					child.render(surface, child, renderer.RuntimeLibrary.dt, renderer)
				end
			end
			argon:UpdateSurface3DTexture(renderer.Window, texture, surface)
		end)
		local render3dId = renderer.Pool.new("3d", function()
			if not instance.Enabled or not ensureResources() then
				return
			end
			local position = getAdorneePosition(instance)
			local workspace = datamodel and datamodel.Workspace
			local camera = instance.Camera or (workspace and (workspace.CurrentCamera or workspace.Camera))
			local cameraPosition = camera and camera.CFrame and camera.CFrame.Position
			if not position or not cameraPosition then
				return
			end
			if (instance.MaxDistance or 0) > 0 and (cameraPosition - position):Magnitude() > instance.MaxDistance then
				argon:SetDecalTransform(renderer.Window, decal, CFrame.new(0, -100000, 0):ToEngineMatrix())
				return
			end
			local scaleFactor = 1
			if instance.AlwaysOnTop then
				local delta = position - cameraPosition
				local distance = delta:Magnitude()
				if distance > 0.25 then
					scaleFactor = 0.25 / distance
					position = cameraPosition + delta * scaleFactor
				end
			end
			local faceCamera = CFrame.lookAt(position, cameraPosition) * CFrame.Angles(math.rad(90), math.rad(180), 0)
			argon:SetDecalTransform(
				renderer.Window,
				decal,
				faceCamera:ToEngineMatrix(Vector3.new(worldWidth * scaleFactor, 0.01, worldHeight * scaleFactor))
			)
			argon:SetDecalTiling(renderer.Window, decal, worldWidth, worldHeight, 0, 0, 0, 0)
		end)
		instance.Destroying:Connect(function()
			renderer.Pool.Destroy(render2dId)
			renderer.Pool.Destroy(render3dId)
			destroyResources()
		end)
		return instance
	end,
	inherit = function(tble)
		for prop, val in pairs(propTable) do
			tble[prop] = val
		end
	end,
}
