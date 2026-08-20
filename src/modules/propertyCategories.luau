local PropertyCategories = {
	Name = "Object",
	Parent = "Object",
	Archivable = "Object",
	ClassName = "Object",
	BaseClass = "Object",

	Transparency = "Appearance",
	Color = "Appearance",
	Material = "Appearance",
	IconColor = "Appearance",
	Shape = "Appearance",
	Reflectance = "Appearance",
	CastsShadow = "Appearance",
	IconTransparency = "Appearance",
	IconSize = "Appearance",

	AssemblyAngularVelocity = "Behavior",
	AssemblyCenterOfMass = "Behavior",
	AssemblyLinearVelocity = "Behavior",
	AssemblyMass = "Behavior",
	AssemblyRootPart = "Behavior",
	Anchored = "Behavior",
	CanCollide = "Behavior",

	NetworkOwnerType = "Network",

	Position = "Transform",
	CFrame = "Transform",
	Size = "Transform",
	Rotation = "Transform",
	Orientation = "Transform",

	BottomLeftRadius = "Appearance",
	BottomRightRadius = "Appearance",
	TopLeftRadius = "Appearance",
	TopRightRadius = "Appearance",

	ScrollBarTransparency = "Appearance",
	ScrollBarColor3 = "Appearance",
	ScrollBarCornerRadius = "Appearance",
	ScrollBarBackgroundTransparency = "Appearance",
	ScrollBarBackgroundColor3 = "Appearance",
	ScrollBarHoverColor3 = "Appearance",

	SoundId = "Behavior",
	Volume = "Behavior",
	Pitch = "Behavior",
	Looped = "Behavior",
	Playing = "Behavior",
	TimePosition = "Behavior",
	PlayOnRemove = "Behavior",
	IsLoaded = "Behavior",
	AudioBackend = "Behavior",

	Velocity = "Behavior",
	Direction = "Behavior",
	Up = "Behavior",
	MinDistance = "Behavior",
	MaxDistance = "Behavior",
	ConeInsideAngle = "Behavior",
	ConeOutsideAngle = "Behavior",
	ConeOutsideVolume = "Behavior",
	Is3D = "Behavior",

	Shader = "Shader",

	BackgroundColor3 = "Appearance",
	BackgroundTransparency = "Appearance",
	Visible = "Appearance",
	BorderSize = "Appearance",
	GroupColor3 = "Appearance",
	GroupTransparency = "Appearance",

	BorderColor = "Appearance",
	BorderTransparency = "Appearance",
	AbsolutePosition = "Transform",
	AbsoluteSize = "Transform",
	ClipsDescendants = "Behavior",
	ZIndex = "Behavior",
	AnchorPoint = "Transform",
}

local CategoryProperties = {}

for prop, category in pairs(PropertyCategories) do
	local list = CategoryProperties[category]
	if not list then
		list = {}
		CategoryProperties[category] = list
	end

	list[#list + 1] = prop
end

return {
	categories = PropertyCategories,

	getPropertyCategory = function(prop)
		return PropertyCategories[prop]
	end,

	getCategoryProperties = function(category)
		return CategoryProperties[category] or {}
	end,
}
