local Instance = require("@Instance")
local Enum = require("@EnumMap")

local KinemiumShaderService = Instance.new("KinemiumShaderService")
KinemiumShaderService.ExplorerHidden = true
KinemiumShaderService._Intents = Enum.PluginIntents.Graphics

KinemiumShaderService.InitRenderer = function(renderer, renderer_signal, datamodel)
	if IsHeadless == true then
		return KinemiumShaderService:SetProperties({})
	end

	task.spawn(function()
		repeat
			task.wait()
		until datamodel.Loaded == true

		KinemiumShaderService:SetProperties({
			LoadShader = function(ShaderObject)
				if typeof(ShaderObject) ~= "table" or ShaderObject._class ~= "shader" then
					return false, "Invalid shader type"
				end
				local compiled, compileError = ShaderObject:Compile(renderer.Window)
				if not compiled then
					return false, compileError
				end
				if ShaderObject._type == "surface" or ShaderObject._type == "sky" then
					return ShaderObject:ApplyGlobal(renderer.Window)
				end
				return true
			end,

			UnloadShader = function(ShaderObject)
				if typeof(ShaderObject) == "table" and ShaderObject._class == "shader" then
					return ShaderObject:Unload()
				end
				return false, "Invalid shader type"
			end,

			LoadShaderPipeline = function(...)
				local args = { ... }
				local shaders = args

				if #args == 1 and type(args[1]) == "table" and not args[1]._class then
					shaders = args[1]
				end

				local count = #shaders
				if count == 0 then
					return true
				end

				for i = 1, count do
					local shaderobj = shaders[i]
					if typeof(shaderobj) ~= "table" or shaderobj._class ~= "shader" or shaderobj._type ~= "2d" then
						return false, "Invalid shader in pipeline: expected a 2D SkSL shader"
					end
					local compiled, compileError = shaderobj:Compile(renderer.Window)
					if not compiled then
						return false, compileError
					end
				end

				return {
					Shaders = shaders,
					Unload = function()
						for _, shader in ipairs(shaders) do
							shader:Unload()
						end
					end,
				}
			end,
		})

		return true
	end)
	return true
end

return KinemiumShaderService
