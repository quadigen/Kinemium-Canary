-- description: "A hierarchical joint that deforms vertices in a skinned MeshPart."
local CFrame = require("@CFrame")
local Attachment = require("@Attachment")

local propTable = {
	Name = "Bone",
	BaseClass = "Attachment",

	Transform = CFrame.new(),
	TransformedCFrame = CFrame.new(),
	TransformedWorldCFrame = CFrame.new(),
	BoneId = -1,
}

Attachment.inherit(propTable)
propTable.Name = "Bone"
propTable.BaseClass = "Attachment"

return {
	class = "Bone",
	callback = function(instance)
		instance:SetProperties(propTable)
		return instance
	end,
	inherit = function(tble)
		for prop, val in pairs(propTable) do
			tble[prop] = val
		end
	end,
}
