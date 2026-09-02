-- description: "A visible rectangular 2D world part with Box2D body properties."
local Body2D = require("@Body2D")
local Color3 = require("@Color3")

local propTable = {
	Name = "Part2D",
	BaseClass = "Body2D",
	Visible = true,
	Color = Color3.new(1, 1, 1),
	Transparency = 0,
	ZIndex = 0,
}

return {
	class = "Part2D",
	callback = function(instance, renderer, game)
		Body2D.callback(instance, renderer, game)
		instance:SetProperties(propTable)
		return instance
	end,
	inherit = function(target)
		Body2D.inherit(target)
		for key, value in pairs(propTable) do
			target[key] = value
		end
	end,
}
