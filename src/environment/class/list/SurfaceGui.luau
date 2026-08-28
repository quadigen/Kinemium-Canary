-- description: "Displays 2D GUI children on a BasePart face."
local Vector2 = require("@Vector2")
local Vector3 = require("@Vector3")
local CFrame = require("@CFrame")
local UDim2 = require("@UDim2")
local Enum = require("@EnumMap")
local argon = require("@Argon")

local propTable = {
	Name = "SurfaceGui",
	Enabled = true,
	Adornee = nil,
	Face = Enum.NormalId.Front,
	CanvasSize = Vector2.new(800, 600),
	PixelsPerStud = 50,
	SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
	AlwaysOnTop = false,
	LightInfluence = 1,
	Brightness = 1,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	ZOffset = 0,
	Size = UDim2.new(0, 800, 0, 600),
	RenderOffset = Vector2.new(0, 0),
	BaseClass = "UIContainer",
}

local function getAdornee(instance)
	local adornee = instance.Adornee or instance.Parent
	return adornee and adornee.CFrame and adornee.Size and adornee or nil
end

local function enumIs(value, enumValue, name)
	return value == enumValue or (type(value) == "table" and value.Name == name) or value == name
end

local function getFaceSize(size, face)
	if enumIs(face, Enum.NormalId.Front, "Front") or enumIs(face, Enum.NormalId.Back, "Back") then
		return size.X, size.Y
	end
	if enumIs(face, Enum.NormalId.Left, "Left") or enumIs(face, Enum.NormalId.Right, "Right") then
		return size.Z, size.Y
	end
	if enumIs(face, Enum.NormalId.Top, "Top") or enumIs(face, Enum.NormalId.Bottom, "Bottom") then
		return size.X, size.Z
	end
	return size.X, size.Y
end

-- Filament's decal quad lies in its local X/Z plane.
local function getFaceCFrame(cf, size, face, zOffset)
	local half = size * 0.5
	local padding = 0.005 + (zOffset or 0)
	if enumIs(face, Enum.NormalId.Front, "Front") then
		return cf * CFrame.new(0, 0, -half.Z - padding) * CFrame.Angles(math.rad(90), math.rad(180), 0)
	elseif enumIs(face, Enum.NormalId.Back, "Back") then
		return cf * CFrame.new(0, 0, half.Z + padding) * CFrame.Angles(math.rad(90), math.rad(180), 0)
	elseif enumIs(face, Enum.NormalId.Left, "Left") then
		return cf * CFrame.new(-half.X - padding, 0, 0) * CFrame.Angles(0, math.rad(-90), math.rad(90))
	elseif enumIs(face, Enum.NormalId.Right, "Right") then
		return cf * CFrame.new(half.X + padding, 0, 0) * CFrame.Angles(0, math.rad(-90), math.rad(90))
	elseif enumIs(face, Enum.NormalId.Top, "Top") then
		return cf * CFrame.new(0, half.Y + padding, 0) * CFrame.Angles(math.rad(180), 0, 0)
	elseif enumIs(face, Enum.NormalId.Bottom, "Bottom") then
		return cf * CFrame.new(0, -half.Y - padding, 0) * CFrame.Angles(math.rad(-180), 0, 0)
	end
	return cf
end

return {
	class = "SurfaceGui",
	callback = function(instance, renderer, datamodel)
		instance:SetProperties(propTable)
		if _G.IsHeadless or not renderer or not renderer.Window then
			return instance
		end

		local surface, texture, decal
		local canvasWidth, canvasHeight = 0, 0

		local function desiredCanvasSize()
			local width = instance.CanvasSize and instance.CanvasSize.X or 800
			local height = instance.CanvasSize and instance.CanvasSize.Y or 600
			if enumIs(instance.SizingMode, Enum.SurfaceGuiSizingMode.PixelsPerStud, "PixelsPerStud") then
				local adornee = getAdornee(instance)
				if adornee then
					local fw, fh = getFaceSize(adornee.Size, instance.Face)
					width, height =
						fw * math.max(1, instance.PixelsPerStud or 50), fh * math.max(1, instance.PixelsPerStud or 50)
				end
			end
			return math.max(1, math.floor(width + 0.5)), math.max(1, math.floor(height + 0.5))
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
			local width, height = desiredCanvasSize()
			if surface and width == canvasWidth and height == canvasHeight then
				return decal ~= nil
			end
			destroyResources()
			canvasWidth, canvasHeight = width, height
			instance.Size = UDim2.new(0, width, 0, height)
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
			local adornee = getAdornee(instance)
			if not adornee then
				return
			end
			local width, height = getFaceSize(adornee.Size, instance.Face)
			local faceCFrame = getFaceCFrame(adornee.CFrame, adornee.Size, instance.Face, instance.ZOffset)
			local scaleFactor = 1
			if instance.AlwaysOnTop then
				local workspace = datamodel and datamodel.Workspace
				local camera = workspace and (workspace.CurrentCamera or workspace.Camera)
				local cameraPosition = camera and camera.CFrame and camera.CFrame.Position
				if cameraPosition then
					local delta = faceCFrame.Position - cameraPosition
					local distance = delta:Magnitude()
					if distance > 0.25 then
						scaleFactor = 0.25 / distance
						faceCFrame = faceCFrame:WithPosition(cameraPosition + delta * scaleFactor)
					end
				end
			end
			argon:SetDecalTransform(
				renderer.Window,
				decal,
				faceCFrame:ToEngineMatrix(Vector3.new(width * scaleFactor, 0.01, height * scaleFactor))
			)
			argon:SetDecalTiling(renderer.Window, decal, width, height, 0, 0, 0, 0)
		end)

		instance.Destroying:Connect(function()
			renderer.Pool.Destroy(render2dId)
			renderer.Pool.Destroy(render3dId)
			destroyResources()
		end)
		instance.GetRelativeMousePosition = function()
			return nil
		end
		return instance
	end,
	inherit = function(tble)
		for prop, val in pairs(propTable) do
			tble[prop] = val
		end
	end,
}
