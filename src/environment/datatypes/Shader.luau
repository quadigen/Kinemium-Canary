local Shader = {}
Shader.__index = Shader

local argon = require("@Argon")
local zembed = require("@zembed")

local function normalizeType(shaderType)
	if shaderType == "raylib" or shaderType == "screen" then
		return "2d"
	elseif shaderType == "material" then
		return "surface"
	end
	return shaderType or "2d"
end

local function sourceFromPath(path)
	if type(path) ~= "string" or path == "" then
		return nil
	end
	local resolved = zembed.AssetPath(path)
	local ok, contents = pcall(zune.fs.readFile, resolved)
	return ok and contents or nil
end

local function uniformValues(value)
	if type(value) == "number" then
		return { value }
	end
	if type(value) ~= "table" then
		return nil
	end
	if value.__type == "Vector2" then
		return { value.X, value.Y }
	elseif value.__type == "Vector3" or value.__type == "CFrame" then
		local vector = value.__type == "CFrame" and value.Position or value
		return { vector.X, vector.Y, vector.Z }
	elseif value.__type == "Color3" then
		return { value.R, value.G, value.B }
	elseif value.__type == "Color4" then
		return { value.R, value.G, value.B, value.A }
	elseif value.__type == "UDim" then
		return { value.Scale, value.Offset }
	elseif value.__type == "UDim2" then
		return { value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset }
	end
	local result = {}
	for index = 1, math.min(#value, 4) do
		if type(value[index]) ~= "number" then
			return nil
		end
		result[index] = value[index]
	end
	return #result > 0 and result or nil
end

function Shader.fromMemory2D(sksl)
	return Shader.new({ sksl = sksl, _type = "2d" })
end

function Shader.fromMemoryRaylib(_, fragment)
	return Shader.fromMemory2D(fragment)
end

function Shader.fromMemorySurface(materialSource)
	return Shader.new({ material = materialSource, _type = "surface" })
end

function Shader.fromMemorySky(source)
	return Shader.new({ source = source, _type = "sky" })
end

function Shader.fromMemoryScreen(source)
	return Shader.fromMemory2D(source)
end

function Shader.new(source)
	assert(type(source) == "table", "Shader.new expects a source table")
	local self = setmetatable({}, Shader)
	self._type = normalizeType(source._type or source.type)
	self._class = "shader"
	self._shader = source._shader
	self._window = nil
	self._uniforms = {}
	self._compileError = nil
	self._source = source.sksl or source.material or source.source or source.glsl
	if not self._source then
		local sourcePath = if self._type == "2d" then source.fragment else source.materialPath or source.fragment
		self._source = sourceFromPath(sourcePath)
	end
	return self
end

function Shader:Compile(target)
	if self._shader then
		return true
	end
	if self._type == "sky" then
		local window = target and (target.Window or target)
		if not window then
			return false, "A rendering window is required to configure the Filament sky"
		end
		self._window = window
		self._shader = self
		return true
	end
	if not self._source or self._source == "" then
		return false, "Shader source is empty"
	end

	local handle, compileError
	if self._type == "2d" then
		handle, compileError = argon:CreateRuntimeShader(self._source)
	elseif self._type == "surface" then
		local window = target and (target.Window or target)
		if not window then
			return false, "A rendering window is required to compile a Filament material"
		end
		handle, compileError = argon:CreateMaterialShader(window, self._source)
		self._window = window
	else
		return false, `Argon does not support runtime {self._type} shaders`
	end

	if not handle then
		self._compileError = compileError or "Shader compilation failed"
		return false, self._compileError
	end
	self._shader = handle
	self._compileError = nil
	for name, values in pairs(self._uniforms) do
		self:_applyUniform(name, values)
	end
	return true
end

function Shader:_applyUniform(name, values)
	if not self._shader then
		return true
	elseif self._type == "2d" then
		return argon:SetRuntimeShaderUniform(self._shader, name, values)
	elseif self._type == "surface" then
		return argon:SetMaterialShaderUniform(self._shader, name, values)
	elseif self._type == "sky" then
		return true
	end
	return false
end

function Shader:SetUniform(name, value)
	local values = uniformValues(value)
	if type(name) ~= "string" or name == "" or not values then
		return false, "Uniforms require a name and one to four numeric values"
	end
	self._uniforms[name] = values
	if self._shader and not self:_applyUniform(name, values) then
		return false, `Uniform "{name}" does not exist or has a different type`
	end
	return true
end

function Shader:SetSampler()
	return false, "Runtime sampler binding is not implemented by the Argon shader bridge"
end

function Shader:ApplyGlobal(target)
	if self._type ~= "surface" and self._type ~= "sky" then
		return false, "Only Filament surface and sky shaders can be applied globally"
	end
	local ok, compileError = self:Compile(target)
	if not ok then
		return false, compileError
	end
	local window = target and (target.Window or target) or self._window
	if self._type == "sky" then
		local sun = self._uniforms.u_SunParams or { -0.45, 0.8, -0.35, 0 }
		local zenith = self._uniforms.u_ZenithColor or { 0.3, 0.48, 0.9 }
		local horizon = self._uniforms.u_HorizonParams or { 0.75, 0.84, 0.96, 1 }
		local ground = self._uniforms.u_GroundColor or { 0.18, 0.2, 0.24 }
		argon:SetSkyAtmosphere(
			window,
			{ X = sun[1], Y = sun[2], Z = sun[3] },
			{ R = zenith[1], G = zenith[2], B = zenith[3], A = 1 },
			{ R = horizon[1], G = horizon[2], B = horizon[3], A = 1 },
			{ R = ground[1], G = ground[2], B = ground[3], A = 1 },
			80000
		)
		return true
	end
	return argon:SetGlobalMaterialShader(window, self._shader)
end

function Shader:Unload()
	if not self._shader then
		return true
	end
	if self._type == "2d" then
		argon:DestroyRuntimeShader(self._shader)
	elseif self._type == "surface" then
		argon:DestroyMaterialShader(self._shader)
	end
	self._shader = nil
	self._window = nil
	return true
end

function Shader:GetUniformLoc()
	return false, "Argon shaders use named uniforms; integer raylib locations are not exposed"
end

return Shader
