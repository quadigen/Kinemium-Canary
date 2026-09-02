local Rectangle = require("./Rectangle")
local Text = require("./Text")
local TextInput = require("./TextInput")
local argon = require("@Argon")
local scroller = require("./Scroller")

local ITEM_HEIGHT = 26
local SEPARATOR_HEIGHT = 9
local PADDING = 4
local TEXT_PADDING = 9
local TEXT_SIZE = 13
local SEARCH_HEIGHT = 24
local SEARCH_GAP = 4

export type ContextMenuItem = {
	text: string?,
	shortcut: string?,
	disabled: boolean?,
	separator: boolean?,
	callback: (() -> ())?,
}

export type ContextMenuParams = {
	id: string?,
	x: number,
	y: number,
	width: number,
	MaxHeight: number?,
	RetainedStorage: any?,
	EnableSearch: boolean?,
	SearchPlaceholder: string?,

	items: { ContextMenuItem },

	visible: boolean?,
	SuppressInput: boolean?,

	Color: any?,
	HoverColor: any?,
	TextColor: any?,

	onClose: (() -> ())?,

	renderer: any,
	engine_window: any,
	theme: any,
}

return function(params: ContextMenuParams, dt: number)
	if params.visible == false then
		return
	end

	local window = params.engine_window
	local renderer = params.renderer
	local theme = params.theme
	local suppressInput = params.SuppressInput == true
	local storage = params.RetainedStorage
	local id = params.id or "ContextMenu"
	local searchEnabled = params.EnableSearch == true

	local cornerRadius = theme.CornerRadius or 4
	local font = argon:CreateFont(theme.Font)

	local field
	if storage then
		field = storage[id]
		if not field then
			field = {
				scrollY = 0,
				searchStorage = {},
				search = "",
			}
			storage[id] = field
		end
	end

	local searchText = field and field.search or ""
	local loweredSearch = string.lower(searchText)
	local visibleItems = {}

	for _, item in ipairs(params.items) do
		if
			item.separator
			or loweredSearch == ""
			or string.find(string.lower(item.text or ""), loweredSearch, 1, true)
		then
			table.insert(visibleItems, item)
		end
	end

	local searchBlockHeight = searchEnabled and (SEARCH_HEIGHT + SEARCH_GAP) or 0
	local height = PADDING * 2 + searchBlockHeight

	for _, item in ipairs(visibleItems) do
		if item.separator then
			height += SEPARATOR_HEIGHT
		else
			height += ITEM_HEIGHT
		end
	end

	local naturalHeight = height
	local maxHeight = params.MaxHeight or naturalHeight
	height = math.min(naturalHeight, maxHeight)

	local menuRect = {
		x = params.x,
		y = params.y,
		width = params.width,
		height = height,
	}

	if not suppressInput and argon:IsMouseButtonPressed(1) then
		if not renderer:isMouseInRect(menuRect) then
			if params.onClose then
				params.onClose()
			end

			return
		end
	end

	local maxScroll = math.max(0, naturalHeight - height)
	if field then
		field.scrollY = math.clamp(field.scrollY or 0, 0, maxScroll)
		if not suppressInput and maxScroll > 0 and renderer:isMouseInRect(menuRect) then
			local wheelDelta = argon:GetMouseWheelMove()
			if wheelDelta ~= 0 then
				field.scrollY = math.clamp(field.scrollY - wheelDelta * ITEM_HEIGHT * 2, 0, maxScroll)
			end
		end
	end

	argon:Save(window)

	argon:ClipRoundRect(window, menuRect, cornerRadius, cornerRadius)

	Rectangle({
		x = params.x,
		y = params.y,
		width = params.width,
		height = height,
		Color = theme.SecondaryColor,
		theme = theme,
		engine_window = window,
	}, dt)

	if searchEnabled and field then
		TextInput({
			x = params.x + PADDING,
			y = params.y + PADDING,
			width = params.width - PADDING * 2,
			height = SEARCH_HEIGHT,
			id = id .. "-search",
			RetainedStorage = field.searchStorage,
			renderer = renderer,
			theme = theme,
			Color = theme.BackgroundColor or params.Color or theme.SecondaryColor,
			FocusColor = params.HoverColor or theme.ThirdColor,
			TextColor = params.TextColor or theme.TextColor,
			PlaceholderColor = theme.SecondaryTextColor,
			placeholder = params.SearchPlaceholder or "Search...",
			padding = 7,
			TextSize = TEXT_SIZE,
			OnChange = function(text)
				if field.search ~= text then
					field.search = text
					field.scrollY = 0
				end
			end,
			engine_window = window,
		}, dt)
	end

	-- Border
	Rectangle({
		x = params.x,
		y = params.y,
		width = params.width,
		height = height,
		Color = theme.ThirdColor,
		isOutline = true,
		theme = theme,
		engine_window = window,
	}, dt)

	local listTop = params.y + PADDING + searchBlockHeight

	local textHeight = argon:GetFontLineHeight(TEXT_SIZE, font)
	local textAscent = argon:GetFontAscent(TEXT_SIZE, font)

	local listHeight = height - PADDING * 2 - searchBlockHeight

	local contentHeight = 0

	for _, item in ipairs(visibleItems) do
		contentHeight += if item.separator then SEPARATOR_HEIGHT else ITEM_HEIGHT
	end

	scroller({
		x = params.x + PADDING,
		y = listTop,

		width = params.width - PADDING * 2,
		height = listHeight,

		ContentWidth = params.width - PADDING * 2,
		ContentHeight = contentHeight,

		RetainedStorage = storage,
		id = id .. "-scroller",

		renderer = renderer,
		window = window,
		theme = theme,

		ScrollbarWidth = 4,
		ScrollSpeed = ITEM_HEIGHT * 2,
		CornerRadius = 0,

		callback = function(content)
			local y = content.y

			for _, item in ipairs(visibleItems) do
				if item.separator then
					Rectangle({
						x = content.x + 2,
						y = y + math.floor(SEPARATOR_HEIGHT / 2),

						width = content.width - 8,
						height = 1,

						Color = theme.ThirdColor,
						theme = theme,
						engine_window = window,
					}, dt)

					y += SEPARATOR_HEIGHT
					continue
				end

				local rowRect = {
					x = content.x,
					y = y,

					width = content.width - 6,
					height = ITEM_HEIGHT,
				}

				local visible = rowRect.y + rowRect.height >= content.viewportY
					and rowRect.y <= content.viewportY + content.viewportHeight

				if visible then
					local hovered = not suppressInput and not item.disabled and renderer:isMouseInRect(rowRect)

					if hovered then
						Rectangle({
							x = rowRect.x,
							y = rowRect.y,
							width = rowRect.width,
							height = rowRect.height,

							Color = params.HoverColor or theme.ThirdColor,

							theme = theme,
							engine_window = window,
						}, dt)
					end

					local textY = y + (ITEM_HEIGHT - textHeight) / 2 + textAscent

					Text({
						x = content.x + TEXT_PADDING,
						y = textY,

						TextSize = TEXT_SIZE,
						Font = font,

						text = item.text or "",

						Color = item.disabled and theme.SecondaryTextColor or params.TextColor or theme.TextColor,

						theme = theme,
						engine_window = window,
					}, dt)

					if item.shortcut then
						local shortcutWidth = argon:MeasureText(window, item.shortcut, TEXT_SIZE, font)

						Text({
							x = content.x + content.width - TEXT_PADDING - shortcutWidth - 8,

							y = textY,

							TextSize = TEXT_SIZE,
							Font = font,
							text = item.shortcut,

							Color = theme.SecondaryTextColor,

							theme = theme,
							engine_window = window,
						}, dt)
					end

					if not suppressInput and not item.disabled and renderer:HasClicked(rowRect) then
						if item.callback then
							item.callback()
						end

						if params.onClose then
							params.onClose()
						end
					end
				end

				y += ITEM_HEIGHT
			end
		end,
	}, dt)

	if maxScroll > 0 then
		local scrollbarWidth = 4
		local trackHeight = height - PADDING * 2 - searchBlockHeight
		local thumbHeight = math.max(18, trackHeight * (height / naturalHeight))
		local thumbY = listTop + ((field and field.scrollY or 0) / maxScroll) * (trackHeight - thumbHeight)

		Rectangle({
			x = params.x + params.width - scrollbarWidth - 3,
			y = thumbY,
			width = scrollbarWidth,
			height = thumbHeight,
			Color = theme.SecondaryTextColor,
			theme = theme,
			engine_window = window,
		}, dt)
	end

	argon:Restore(window)
end
