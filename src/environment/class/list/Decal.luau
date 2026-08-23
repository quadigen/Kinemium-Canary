-- description: "Renders a 2D image in 3D space, Supports editable images, Parented under a BasePart."
local Vector3 = require("@Vector3")
local Color3 = require("@Color3")
local CFrame = require("@CFrame")
local Enum = require("@EnumMap")
local argon = require("@Argon")

local propTable = {
	Transparency = 0,
	Color3 = Color3.new(1, 1, 1),
	Texture = "./src/assets/images/placeholder.png",
	ColorMapContent = "./src/assets/images/placeholder.png",
	Face = Enum.NormalId.Top,

	Adornee = nil,
	Position = Vector3.new(0, 0, 0),
	Wrap = false,
	Depth = 0.1,
	NormalThreshold = 0,
	FadeWidth = 0,
}

local function getFaceSize(size, face)
	if face == Enum.NormalId.Front or face == Enum.NormalId.Back then
		return size.X, size.Y
	elseif face == Enum.NormalId.Left or face == Enum.NormalId.Right then
		return size.Z, size.Y
	elseif face == Enum.NormalId.Top or face == Enum.NormalId.Bottom then
		return size.X, size.Z
	end
end

local function getFaceCFrame(cf, size, face)
	local half = size * 0.5
	local padding = 0.005 -- offset to prevent Z-fighting

	if face == Enum.NormalId.Front then
		return cf * CFrame.new(0, 0, -half.Z - padding) * CFrame.Angles(math.rad(90), math.rad(180), 0)
	elseif face == Enum.NormalId.Back then
		return cf * CFrame.new(0, 0, half.Z + padding) * CFrame.Angles(math.rad(90), math.rad(180), 0)
	elseif face == Enum.NormalId.Left then
		return cf * CFrame.new(-half.X - padding, 0, 0) * CFrame.Angles(0, math.rad(-90), math.rad(90))
	elseif face == Enum.NormalId.Right then
		return cf * CFrame.new(half.X + padding, 0, 0) * CFrame.Angles(0, math.rad(-90), math.rad(90))
	elseif face == Enum.NormalId.Top then
		return cf * CFrame.new(0, half.Y + padding, 0) * CFrame.Angles(math.rad(180), 0, 0)
	elseif face == Enum.NormalId.Bottom then
		return cf * CFrame.new(0, -half.Y - padding, 0) * CFrame.Angles(math.rad(-180), 0, 0)
	end
	return cf
end

local function applyFaceOffset(cf, offset)
	if type(offset) ~= "table" or not offset.__type then
		return cf
	end

	if offset.__type == "Vector3" then
		return cf * CFrame.new(offset.X, offset.Y, offset.Z)
	elseif offset.__type == "Vector2" then
		return cf * CFrame.new(offset.X, offset.Y, 0)
	end

	return cf
end

return {
	class = "Decal",

	callback = function(instance, renderer)
		instance:SetProperties(propTable)

		local activeDecal = nil

		local function removeActiveDecal()
			if activeDecal and renderer and renderer.Window then
				argon:RemoveDecal(renderer.Window, activeDecal)
				activeDecal = nil
			end
		end

		local function getTexturePath()
			if instance.Texture and instance.Texture ~= "" then
				return instance.Texture
			end
			return instance.ColorMapContent
		end

		local function load()
			removeActiveDecal()
			if not renderer or not renderer.Window then
				return
			end
			local tex = argon:CreateDecalTexture(renderer.Window, getTexturePath())
			if tex then
				activeDecal = argon:CreateDecal(renderer.Window, 1, 1, tex, 0, 0, 0, 0)
			end
		end

		load()

		local renderId
		if renderer then
			renderId = renderer.Pool.new("3d", function()
				if not activeDecal or instance.Transparency >= 1 then
					return
				end

				local adornee = instance.Adornee
				if not adornee or not adornee.CFrame or not adornee.Size then
					adornee = instance.Parent
				end
				if not adornee or not adornee.CFrame or not adornee.Size then
					return
				end

				local face = instance.Face
				local depth = math.max(0.001, instance.Depth or 0.1)
				local cf
				local scale
				local width, height

				if instance.Wrap == true then
					cf = adornee.CFrame
					width, height = adornee.Size.X, adornee.Size.Z
					scale = Vector3.new(adornee.Size.X + depth, adornee.Size.Y + depth, adornee.Size.Z + depth)
				else
					width, height = getFaceSize(adornee.Size, face)
					if not width or not height then
						return
					end
					cf = getFaceCFrame(adornee.CFrame, adornee.Size, face)
					if not cf then
						return
					end
					scale = Vector3.new(width, depth, height)
				end

				cf = applyFaceOffset(cf, instance.Position)
				local matrix = cf:ToEngineMatrix(scale)

				argon:SetDecalTransform(renderer.Window, activeDecal, matrix)
				argon:SetDecalTiling(
					renderer.Window,
					activeDecal,
					width,
					height,
					0,
					0,
					0,
					0
				)
			end)
		end

		instance.Changed:Connect(function(property)
			if property == "Texture" or property == "ColorMapContent" then
				load()
			end
		end)

		instance.Destroying:Connect(function()
			if renderId and renderer and renderer.Pool then
				renderer.Pool.Destroy(renderId)
			end
			removeActiveDecal()
		end)

		return instance
	end,

	inherit = function(tble)
		for prop, val in pairs(propTable) do
			tble[prop] = val
		end
	end,
}
