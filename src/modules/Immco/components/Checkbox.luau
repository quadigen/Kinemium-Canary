local typedefs = require("../typedefs")
local argon = require("@Argon")

return function(params: typedefs.BooleanParams, dt: number)
	local window = params.engine_window
	local cornerRadius = params.theme.CornerRadius or 12

	argon:Save(window)

	argon:ClipRoundRect(window, {
		x = params.x,
		y = params.y,
		width = params.width,
		height = params.height,
	}, cornerRadius, cornerRadius)

	argon:DrawRectangle(window, {
		x = params.x,
		y = params.y,
		width = params.width,
		height = params.height,
		Color = params.Color,
		isOutline = params.isOutline,
	})

	argon:DrawRectangle(window, {
		x = params.x,
		y = params.y,
		width = params.width,
		height = params.height,
		Color = params.Color,
		isOutline = true,
	})

	if params.bool == true then
		argon:DrawRectangle(window, {
			x = params.x,
			y = params.y,
			width = params.width,
			height = params.height,
			Color = argon:RGBA(255, 255, 255),
			isOutline = params.isOutline,
		})
	end

	if params.callback then
		params.callback({
			x = params.x,
			y = params.y,
			width = params.width,
			height = params.height,
			window = window,
			theme = theme,
		})
	end

	argon:Restore(window)
end
