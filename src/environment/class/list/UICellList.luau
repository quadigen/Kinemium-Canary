-- description: "An Argon-backed list of cells organized into sections."
local GuiObject = require("@GuiObject")
local UDim2 = require("@UDim2")
local Immco = require("@Immco")

local propTable = {
	Name = "UICellList", BaseClass = "GuiObject", AbsoluteSize = nil, AbsolutePosition = nil,
	Size = UDim2.new(1, 0, 1, 0), Sections = {}, CellHeight = 70, GroupSpacing = 20, Visible = true,
}
GuiObject.inherit(propTable)

return {
	class = "UICellList",
	callback = function(instance, renderer, game)
		instance:SetProperties(propTable)
		instance.render = function(window, object, dt, currentRenderer)
			if object.Visible == false then return end
			local pos, size = GuiObject.calculatePositions(currentRenderer.Window, object, dt, currentRenderer)
			if not pos or not size then return end
			local themeService = game:GetService("StudioThemeService")
			local theme = themeService and themeService.SelectedTheme or {}
			local y = pos.Y
			for sectionName, cells in pairs(object.Sections or {}) do
				Immco.Text({ engine_window = currentRenderer.Window, theme = theme, x = pos.X, y = y + 16,
					text = tostring(sectionName), TextSize = 15, Color = theme.TextColor }, dt)
				y += 24
				for _, cell in ipairs(cells) do
					Immco.RoundedRectangle({ engine_window = currentRenderer.Window, theme = theme, x = pos.X,
						y = y, width = size.X, height = object.CellHeight, Color = theme.SecondaryColor }, dt)
					Immco.Text({ engine_window = currentRenderer.Window, theme = theme, x = pos.X + 10, y = y + 22,
						text = tostring(cell.name or cell.Name or "Cell"), TextSize = 14, Color = theme.TextColor }, dt)
					if cell.description or cell.Description then
						Immco.Text({ engine_window = currentRenderer.Window, theme = theme, x = pos.X + 10, y = y + 44,
							text = tostring(cell.description or cell.Description), TextSize = 12,
							Color = theme.SecondaryTextColor }, dt)
					end
					y += object.CellHeight + 4
				end
				y += object.GroupSpacing
			end
			return pos, size
		end
		return instance
	end,
	inherit = function(target) GuiObject.inherit(target) end,
}
