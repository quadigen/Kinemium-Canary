local ReplicationSchema = {}

ReplicationSchema.Properties = {
	Name = 1,
	CFrame = 2,
	Size = 3,
	Color = 4,
	Transparency = 5,
	Anchored = 6,
	CanCollide = 7,
	AssemblyLinearVelocity = 8,
	AssemblyAngularVelocity = 9,
	Value = 10,
	Health = 11,
	MaxHealth = 12,
	WalkSpeed = 13,
	JumpPower = 14,
	AutoRotate = 15,
	Enabled = 16,
	Text = 17,
	Visible = 18,
	Material = 19,
	UserId = 20,
	Character = 21,
	DisplayName = 22,
	RootPart = 23,
	PrimaryPart = 24,
	Shape = 25,
	Data = 26,
}
ReplicationSchema.Names = {}
for name, id in pairs(ReplicationSchema.Properties) do
	ReplicationSchema.Names[id] = name
end
ReplicationSchema.Classes = {}

local nextPropertyId = 27

function ReplicationSchema.RegisterProperty(name, id)
	assert(type(name) == "string" and #name > 0, "property name must be a non-empty string")
	local existing = ReplicationSchema.Properties[name]
	if existing then
		assert(id == nil or id == existing, "property is already registered with a different ID")
		return existing
	end
	id = id or nextPropertyId
	assert(type(id) == "number" and id % 1 == 0 and id > 0 and id <= 65535, "invalid property ID")
	assert(ReplicationSchema.Names[id] == nil, "property ID is already registered")
	ReplicationSchema.Properties[name], ReplicationSchema.Names[id] = id, name
	nextPropertyId = math.max(nextPropertyId, id + 1)
	return id
end

function ReplicationSchema.RegisterClass(className, properties)
	assert(type(className) == "string" and #className > 0, "class name must be a non-empty string")
	assert(type(properties) == "table", "properties must be an array")
	local registered = { "Name" }
	local seen = { Name = true }
	for _, property in ipairs(properties) do
		assert(type(property) == "string", "property names must be strings")
		ReplicationSchema.RegisterProperty(property)
		if not seen[property] then
			table.insert(registered, property)
			seen[property] = true
		end
	end
	ReplicationSchema.Classes[className] = registered
	return registered
end

local function registerBuiltInClass(className, properties)
	if not ReplicationSchema.Classes[className] then
		ReplicationSchema.RegisterClass(className, properties)
	end
end

registerBuiltInClass("Attachment", { "Position", "Axis", "SecondaryAxis", "Visible" })
registerBuiltInClass("Weld", { "Part0", "Part1", "Enabled", "Visible", "Color" })
registerBuiltInClass("WeldConstraint", { "Part0", "Part1", "Enabled", "Visible", "Color" })
registerBuiltInClass("RigidConstraint", { "Attachment0", "Attachment1", "Enabled", "Visible", "Color" })
registerBuiltInClass("BallSocketConstraint", { "Attachment0", "Attachment1", "Enabled", "Visible", "Color", "Radius" })
registerBuiltInClass("RodConstraint", { "Attachment0", "Attachment1", "Enabled", "Visible", "Color", "Length" })
registerBuiltInClass("RopeConstraint", {
	"Attachment0", "Attachment1", "Enabled", "Visible", "Color", "Length", "Stiffness", "Damping", "Thickness",
})
registerBuiltInClass("PlaneConstraint", { "Attachment0", "Attachment1", "Enabled", "Visible", "Color" })
registerBuiltInClass("UniversalConstraint", {
	"Attachment0", "Attachment1", "Enabled", "Visible", "Color", "LimitsEnabled", "MaxAngle",
})
registerBuiltInClass("TorsionSpringConstraint", {
	"Attachment0", "Attachment1", "Enabled", "Visible", "Color", "Stiffness", "Damping", "MaxAngle",
})
registerBuiltInClass("CylindricalConstraint", {
	"Attachment0", "Attachment1", "Enabled", "Visible", "Color", "LimitsEnabled", "LowerLimit", "UpperLimit",
})
registerBuiltInClass("SpringConstraint", {
	"Attachment0",
	"Attachment1",
	"Enabled",
	"Visible",
	"Color",
	"Damping",
	"Stiffness",
	"Frequency",
	"SpringMode",
	"LimitsEnabled",
	"MinLength",
	"MaxLength",
})
registerBuiltInClass("HingeConstraint", {
	"Attachment0",
	"Attachment1",
	"Enabled",
	"Visible",
	"Color",
	"ActuatorType",
	"AngularVelocity",
	"MotorMaxTorque",
	"ServoMaxTorque",
	"TargetAngle",
	"LimitsEnabled",
	"LowerAngle",
	"UpperAngle",
	"Restitution",
	"Offset",
})
registerBuiltInClass("PrismaticConstraint", {
	"Attachment0",
	"Attachment1",
	"Enabled",
	"Visible",
	"Color",
	"ActuatorType",
	"Velocity",
	"MotorMaxForce",
	"ServoMaxForce",
	"TargetPosition",
	"LimitsEnabled",
	"LowerLimit",
	"UpperLimit",
})

registerBuiltInClass("Camera2D", { "Position", "Zoom", "Rotation", "ViewportSize" })
registerBuiltInClass("Body2D", {
	"Position", "Size", "Rotation", "LinearVelocity", "AngularVelocity", "Anchored", "Enabled",
})
registerBuiltInClass("Part2D", {
	"Position", "Size", "Rotation", "LinearVelocity", "AngularVelocity", "Anchored", "Enabled",
	"Visible", "Color", "Transparency", "ZIndex",
})
registerBuiltInClass("Tilemap", { "Position", "TileSize", "Tiles", "Visible", "ZIndex" })
registerBuiltInClass("Layer2D", {
	"Width", "Height", "TileSize", "Tiles", "Visible", "ZIndex", "Offset", "Parallax", "CollisionEnabled",
})
registerBuiltInClass("Attachment2D", { "Position", "Rotation" })
registerBuiltInClass("BoxCollider2D", {
	"Size", "Offset", "Rotation", "Enabled", "IsSensor", "Density", "Friction", "Restitution",
})
registerBuiltInClass("CircleCollider2D", {
	"Radius", "Offset", "Enabled", "IsSensor", "Density", "Friction", "Restitution",
})
registerBuiltInClass("PolygonCollider2D", {
	"Points", "Offset", "Rotation", "Enabled", "IsSensor", "Density", "Friction", "Restitution",
})
registerBuiltInClass("RopeConstraint2D", {
	"Attachment0", "Attachment1", "Length", "Stiffness", "Damping", "Enabled",
})
registerBuiltInClass("SpringConstraint2D", {
	"Attachment0", "Attachment1", "FreeLength", "Stiffness", "Damping", "Enabled",
})
registerBuiltInClass("HingeConstraint2D", {
	"Attachment0", "Attachment1", "LimitsEnabled", "LowerAngle", "UpperAngle", "Enabled",
})
registerBuiltInClass("WeldConstraint2D", { "Body0", "Body1", "Enabled" })
registerBuiltInClass("MovementController", {
	"Enabled", "WalkSpeed", "SprintMultiplier",
})
registerBuiltInClass("CollisionController", {
	"Enabled", "Size", "Mass", "MaxSlopeAngle", "CollisionGroup", "Padding",
})
registerBuiltInClass("RotationController", {
	"Enabled", "AutoRotate", "TurnSpeed",
})
registerBuiltInClass("JumpController", {
	"Enabled", "UseJumpPower", "JumpPower", "JumpHeight", "BufferTime", "CoyoteTime",
})
registerBuiltInClass("GravityController", {
	"Enabled", "GravityScale", "DefaultGravity", "TerminalVelocity",
})
registerBuiltInClass("PhysicsInteractionController", {
	"Enabled", "PushStrength", "MinimumImpulse", "MaximumImpulse", "VerticalLift", "PushInterval", "MinimumRelativeSpeed",
})
registerBuiltInClass("ProximityPrompt", {
	"ActionText", "Enabled", "HoldDuration", "KeyboardKeyCode", "MaxActivationDistance",
	"MaxIndicatorDistance", "ObjectText", "RequiresLineOfSight", "UIOffset",
})
ReplicationSchema.RegisterProperty("JumpQueueWindow")
ReplicationSchema.RegisterProperty("MeshId")
ReplicationSchema.RegisterProperty("MeshScale")

local BASE = { "Name" }
local PART = {
	"Name",
	"CFrame",
	"Size",
	"Color",
	"Transparency",
	"Anchored",
	"CanCollide",
	"AssemblyLinearVelocity",
	"AssemblyAngularVelocity",
	"Material",
	"Shape",
	"MeshId",
	"MeshScale",
}
local HUMANOID = {
	"Name", "Health", "MaxHealth", "WalkSpeed", "JumpPower", "AutoRotate", "DisplayName", "RootPart",
}
local CONTROLLER = {
	"Name",
	"WalkSpeed",
	"SprintMultiplier",
	"JumpPower",
	"JumpHeight",
	"UseJumpPower",
	"JumpQueueWindow",
	"CoyoteTime",
	"GravityScale",
	"TerminalVelocity",
	"AutoRotate",
	"TurnSpeed",
	"Enabled",
	"RootPart",
}
local PLAYER = { "Name", "UserId", "Character", "Health", "MaxHealth", "WalkSpeed", "JumpPower" }
local MODEL = { "Name", "PrimaryPart" }
local VALUE = { "Name", "Value" }
local REMOTE_DATA = { "Name", "Data" }

function ReplicationSchema.GetProperties(instance)
	local custom = ReplicationSchema.Classes[instance.ClassName]
	if custom then
		return custom
	end
	if instance:IsA("BasePart") then
		return PART
	end
	if instance.ClassName == "Humanoid" then
		return HUMANOID
	end
	if instance.ClassName == "CharacterController" then
		return CONTROLLER
	end
	if instance.ClassName == "Player" then
		return PLAYER
	end
	if instance.ClassName == "Model" then
		return MODEL
	end
	if instance.ClassName and instance.ClassName:match("Value$") then
		return VALUE
	end
	if instance.ClassName == "RemoteData" then
		return REMOTE_DATA
	end
	if instance.Text ~= nil then
		return { "Name", "Text", "Visible" }
	end
	if instance.Enabled ~= nil then
		return { "Name", "Enabled" }
	end
	return BASE
end

function ReplicationSchema.IsReplicated(instance, property)
	if not ReplicationSchema.Properties[property] then
		return false
	end
	for _, name in ipairs(ReplicationSchema.GetProperties(instance)) do
		if name == property then
			return true
		end
	end
	return false
end

local function finiteNumber(value)
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function ReplicationSchema.IsSafeValue(value, depth)
	depth = depth or 0
	if depth > 8 then
		return false
	end
	local kind = type(value)
	if kind == "nil" or kind == "boolean" then
		return true
	end
	if kind == "number" then
		return finiteNumber(value)
	end
	if kind == "string" then
		return #value <= 65535
	end
	if kind ~= "table" then
		return false
	end
	if value.ClassName then
		return true
	end
	if value.__type == "EnumItem" then
		return type(value.Name) == "string"
			and type(value.EnumType) == "table"
			and type(value.EnumType.Name) == "string"
	end
	if value.__type == "Vector3" then
		return finiteNumber(value.X) and finiteNumber(value.Y) and finiteNumber(value.Z)
	end
	if value.__type == "Vector2" then
		return finiteNumber(value.X) and finiteNumber(value.Y)
	end
	if value.__type == "CFrame" then
		if value.IsFinite then
			local ok, finite = pcall(value.IsFinite, value)
			return ok and finite == true
		end
		return value.Position ~= nil and ReplicationSchema.IsSafeValue(value.Position, depth + 1)
	end
	local count = 0
	for key, child in pairs(value) do
		count += 1
		if
			count > 128
			or not ReplicationSchema.IsSafeValue(key, depth + 1)
			or not ReplicationSchema.IsSafeValue(child, depth + 1)
		then
			return false
		end
	end
	return true
end

function ReplicationSchema.EncodeValue(value, world, seen)
	if type(value) ~= "table" then
		return value
	end
	if value.ClassName then
		local id = world and world:GetId(value) or nil
		return id and { __netref = id } or nil
	end
	if value.__type == "EnumItem" then
		return { __enum = value.EnumType and value.EnumType.Name, name = value.Name }
	end
	if value.__type == "Vector3" or value.__type == "Vector2" or value.__type == "CFrame"
		or value.__type == "CFrame2D" or value.__type == "Color3"
	then
		return value
	end
	seen = seen or {}
	if seen[value] then
		error("cannot replicate a circular table")
	end
	seen[value] = true
	local encoded = {}
	for key, child in pairs(value) do
		local encodedKey = ReplicationSchema.EncodeValue(key, world, seen)
		if encodedKey ~= nil then
			encoded[encodedKey] = ReplicationSchema.EncodeValue(child, world, seen)
		end
	end
	seen[value] = nil
	return encoded
end

function ReplicationSchema.DecodeValue(value, world, enum)
	if type(value) ~= "table" then
		return value
	end
	if value.__netref then
		return world and world:GetInstance(value.__netref) or nil
	end
	if value.__enum and enum and enum[value.__enum] then
		return enum[value.__enum][value.name]
	end
	if value.__type == "Vector3" then
		return require("@Vector3").FromTable(value)
	end
	if value.__type == "Vector2" then
		return require("@Vector2").FromTable(value)
	end
	if value.__type == "CFrame2D" then
		return require("@CFrame2D").FromTable(value)
	end
	if value.__type == "CFrame" then
		return require("@CFrame").FromTable(value)
	end
	if value.__type == "Color3" then
		-- Older/generic serializer paths preserve __type but Color3.FromTable
		-- historically expects the public `type` discriminator.
		if value.type ~= "Color3" then
			value = table.clone(value)
			value.type = "Color3"
		end
		return require("@Color3").FromTable(value)
	end
	local decoded = {}
	for key, child in pairs(value) do
		local decodedKey = ReplicationSchema.DecodeValue(key, world, enum)
		if decodedKey ~= nil then
			decoded[decodedKey] = ReplicationSchema.DecodeValue(child, world, enum)
		end
	end
	return decoded
end

function ReplicationSchema.Capture(instance, world)
	local state = {}
	for _, property in ipairs(ReplicationSchema.GetProperties(instance)) do
		local value = instance[property]
		if value ~= nil and ReplicationSchema.IsSafeValue(value) then
			state[ReplicationSchema.Properties[property]] = ReplicationSchema.EncodeValue(value, world)
		end
	end
	return state
end

function ReplicationSchema.Apply(instance, state, world, enum)
	local firstError = nil
	for propertyId, encoded in pairs(state or {}) do
		local name = ReplicationSchema.Names[propertyId]
		if name then
			local decoded, value = pcall(ReplicationSchema.DecodeValue, encoded, world, enum)
			if decoded and value ~= nil then
				local assigned = pcall(function()
					instance[name] = value
				end)
				if not assigned and not firstError then
					firstError = "failed to apply " .. name
				end
			elseif not decoded and not firstError then
				firstError = "failed to decode " .. name .. ": " .. tostring(value)
			end
		end
	end
	return firstError == nil, firstError
end

return ReplicationSchema
