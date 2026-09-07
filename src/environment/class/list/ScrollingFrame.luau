-- description: "A container that displays a scrollable area of content."
local Color3 = require("@Color3")
local GuiObject = require("@GuiObject")
local UDim = require("@UDim")
local argon = require("@Argon")

local propTable = {
	Name = "ScrollingFrame",

	-- layout
	AbsoluteSize = nil,
	AbsolutePosition = nil,

	-- appearance
	ScrollBarTransparency = 0,
	ScrollBarColor3 = Color3.new(0.5, 0.5, 0.5),
	ScrollBarCornerRadius = UDim.new(0, 0),
	ScrollBarBackgroundTransparency = 1,
	ScrollBarBackgroundColor3 = Color3.new(1, 1, 1),
	ScrollBarHoverColor3 = Color3.new(0.6, 0.6, 0.6),

	-- scrolling state
	Scroll = 0, -- normalized 0–1 (thumb position)
	ScrollOffset = 0.08, -- wheel step

	-- lerping
	ScrollTarget = 0, -- where input writes to
	ScrollLerpSpeed = 18, -- higher = snappier

	-- content
	ContentSize = 0, -- total content height (pixels)
	CanvasPosition = 0, -- pixel offset derived from Scroll
	AutoScrollSize = true,
	CanvasSize = 0,

	-- behavior
	ScrollBarThickness = 8,
	ScrollBarVisible = true,
	ScrollBarAutoHide = true, -- auto-hide when not scrolling
	ScrollBarFadeSpeed = 4, -- fade speed
	ScrollBarPadding = 2, -- padding from edge

	ElasticEnabled = true,
	ElasticStrength = 0.8, -- how far you can overscroll (0-1, relative to viewport)
	ElasticSnapSpeed = 12, -- how fast it snaps back

	-- momentum scrolling
	MomentumEnabled = true,
	MomentumFriction = 0.92, -- 0-1, higher = scrolls longer
	MomentumMinVelocity = 0.001, -- minimum velocity before stopping

	-- track clicking
	TrackClickEnabled = true, -- click scrollbar track to jump
	TrackClickSmooth = true, -- smooth scroll to position instead of instant

	_draggingThumb = false,
	_dragOffsetY = 0,
	_scrollBarAlpha = 0, -- for fade in/out
	_timeSinceLastScroll = 999, -- accumulated dt since last scroll
	_velocity = 0, -- for momentum
	_isOverscrolled = false,
	_lastScroll = 0, -- for velocity calculation
	_isHoveringThumb = false,
	_isHoveringTrack = false,
}

GuiObject.inherit(propTable)

return {
	class = "ScrollingFrame",

	callback = function(instance, renderer, game)
		instance:SetProperties(propTable)
		return instance
	end,
	inherit = function(tble)
		GuiObject.inherit(tble)
	end,
}
