-- Shared Argon-backed geometry helpers for UI layouts and constraints.
local Vector2 = require("@Vector2")
local argon = require("@Argon")

local UILayout = {}

local function enumName(value)
	return type(value) == "table" and value.Name or value
end

function UILayout.ConstrainSize(object, size)
	local width, height = size.X, size.Y
	local sizeConstraint = object:FindFirstChildOfClass("UISizeConstraint")
	if sizeConstraint then
		local minSize = sizeConstraint.MinSize or Vector2.Zero
		local maxSize = sizeConstraint.MaxSize or Vector2.new(math.huge, math.huge)
		width = math.clamp(width, minSize.X or 0, maxSize.X or math.huge)
		height = math.clamp(height, minSize.Y or 0, maxSize.Y or math.huge)
	end

	local aspect = object:FindFirstChildOfClass("UIAspectRatioConstraint")
	local ratio = aspect and tonumber(aspect.AspectRatio)
	if ratio and ratio > 0 and width > 0 and height > 0 then
		local aspectType = enumName(aspect.AspectType)
		if aspectType == "FitWithinMaxSize" or aspectType == 0 then
			if width / height > ratio then
				width = height * ratio
			else
				height = width / ratio
			end
		else
			local dominantAxis = enumName(aspect.DominantAxis)
			if dominantAxis == "Height" or dominantAxis == 1 then
				width = height * ratio
			else
				height = width / ratio
			end
		end
	end

	return Vector2.new(width, height)
end

function UILayout.GetSize(object, parentSize)
	if object.Size and object.Size.ToPixels then
		return UILayout.ConstrainSize(object, object.Size:ToPixels(parentSize))
	end
	return Vector2.new(0, 0)
end

local function surfaceSize(surface)
	if not surface then
		return Vector2.new(0, 0)
	end

	-- Off-screen Argon surfaces expose pixel dimensions directly.
	if surface.width and surface.height then
		return Vector2.new(surface.width, surface.height)
	end

	-- Windows expose drawable dimensions. UI coordinates are DPI-independent.
	local width = surface.Width or 0
	local height = surface.Height or 0
	if argon.GetDPIScale and surface._handle then
		local scale = argon:GetDPIScale(surface)
		if scale and scale > 0 then
			width /= scale
			height /= scale
		end
	end
	return Vector2.new(width, height)
end

function UILayout.GetAbsoluteSize(object, surface)
	if not object then
		return surfaceSize(surface)
	end
	if object.AbsoluteSize then
		return Vector2.new(object.AbsoluteSize.X, object.AbsoluteSize.Y)
	end
	if object.BaseClass == "UIContainer" then
		if object.Size and object.Size.X and object.Size.Y then
			return Vector2.new(object.Size.X.Offset or 0, object.Size.Y.Offset or 0)
		end
		return surfaceSize(surface)
	end

	local parentSize = UILayout.GetAbsoluteSize(object.Parent, surface)
	return UILayout.GetSize(object, parentSize)
end

function UILayout.GetPadding(object, size)
	local left, right, top, bottom = 0, 0, 0, 0
	for _, child in ipairs(object:GetChildren()) do
		if child.ClassName == "UIPadding" then
			if child.GetResolvedPadding then
				local padding = child:GetResolvedPadding(size)
				left += padding.Left or 0
				right += padding.Right or 0
				top += padding.Top or 0
				bottom += padding.Bottom or 0
			elseif child.Padding and child.Padding.ToPixels then
				local padding = child.Padding:ToPixels(size)
				left += padding.X
				right += padding.X
				top += padding.Y
				bottom += padding.Y
			end
		end
	end
	return left, right, top, bottom
end

return UILayout
