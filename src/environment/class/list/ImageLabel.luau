-- description: "A 2D GUI object that displays an image."
local Vector2 = require("@Vector2")
local Color3 = require("@Color3")
local UDim2 = require("@UDim2")
local Rect = require("@Rect")
local _Enum = require("@EnumMap")
local GuiObject = require("@GuiObject")
local argon = require("@Argon")

local cached = {}
local engine_renderer

local propTable = {
	Position = UDim2.new(0, 0, 0, 0),
	Size = UDim2.new(0, 100, 0, 100),
	AnchorPoint = Vector2.new(0, 0),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BackgroundTransparency = 0,
	Image = "./src/assets/images/placeholder.png",
	ImageColor3 = Color3.new(1, 1, 1),
	ImageTransparency = 0,
	ImageOutlineColor3 = Color3.new(0, 0, 0),
	ImageOutlineTransparency = 1,
	ImageOutlineThickness = 0,
	Shader = nil,
	ScaleType = _Enum.ScaleType.Stretch,
	SliceCenter = Rect.new(0, 0, 0, 0),
	SliceScale = 1,
	Name = "ImageLabel",
	Visible = true,
	ZIndex = 1,

	_cached = nil,
	_suppressGuiBg = true,
	_suppressGuiStroke = true,
}

propTable.render = function(lib, object, dt, _)
	local framePos, frameSize = GuiObject.render(lib, object, dt)
	if not framePos or not frameSize then
		return
	end
	if type(object.Image) ~= "string" then
		return
	end
	if not engine_renderer then
		return
	end
	if not cached[object.Image] then
		cached[object.Image] = argon:CreateImageFromPath(object.Image)
	end

	local rect = {
		Color = argon:RGBA(255, 255, 255, 0),
		width = frameSize.X,
		height = frameSize.Y,
		isOutline = false,
		x = framePos.X,
		y = framePos.Y,
	}

	local UICorner = object:FindFirstChildOfClass("UICorner")
	local UISquircle = object:FindFirstChildOfClass("UISquircle")
	local UIStroke = object:FindFirstChildOfClass("UIStroke")
	local didClip = false
	if UICorner or UISquircle then
		argon:Save(engine_renderer.Window)
		if UISquircle then
			local radius = UISquircle.CornerRadius and UISquircle.CornerRadius.Offset or 0
			local exponent = if (UISquircle.Exponent or 0) > 0 then UISquircle.Exponent else 4
			argon:ClipSquircle(engine_renderer.Window, rect, radius, exponent)
		else
			local radius = UICorner.CornerRadius and UICorner.CornerRadius.Offset or 0
			argon:ClipRoundRect(engine_renderer.Window, rect, radius, radius)
		end
		didClip = true
	end

	local outlineThickness = object.ImageOutlineThickness or 0
	local outlineTransparency = object.ImageOutlineTransparency or 1
	local outlineColor = object.ImageOutlineColor3
	if UIStroke and UIStroke.Thickness > 0 and UIStroke.Transparency < 1 then
		outlineThickness = UIStroke.Thickness
		outlineTransparency = UIStroke.Transparency
		outlineColor = UIStroke.Color
	end

	if outlineThickness > 0 and outlineTransparency < 1 then
		argon:DrawImageOutlineSized(
			engine_renderer.Window,
			cached[object.Image],
			rect,
			{ R = outlineColor.R, G = outlineColor.G, B = outlineColor.B, A = 1 - outlineTransparency },
			outlineThickness,
			1 - object.ImageTransparency
		)
	else
		argon:DrawImageSized(engine_renderer.Window, cached[object.Image], rect, 1 - object.ImageTransparency)
	end

	if didClip then
		argon:Restore(engine_renderer.Window)
	end
	GuiObject.renderChildren(lib, object, dt)
	table.clear(rect)
	rect = nil

	return framePos, frameSize, object._cached
end

GuiObject.inherit(propTable)

return {
	class = "ImageLabel",
	render = propTable.render,
	callback = function(instance, renderer)
		engine_renderer = renderer
		instance:SetProperties(propTable)

		return instance
	end,

	inherit = function(tble)
		for prop, val in pairs(propTable) do
			tble[prop] = val
		end
	end,
}
