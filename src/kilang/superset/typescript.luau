local CONTROL_KEYWORDS = {
	["if"] = true,
	["for"] = true,
	["while"] = true,
	["switch"] = true,
	["catch"] = true,
}

local function escapeLuaString(value)
	value = value:gsub("\\", "\\\\")
	value = value:gsub('"', '\\"')
	value = value:gsub("\r", "\\r")
	value = value:gsub("\n", "\\n")
	return value
end

local function trim(value)
	return value:match("^%s*(.-)%s*$")
end

local function stripParamTypes(params)
	params = params:gsub("%.%.%.([%w_]+)", "...")
	params = params:gsub("([%w_]+)%s*%?%s*:%s*[%w%.%[%]| ]+", "%1")
	params = params:gsub("([%w_]+)%s*:%s*[%w%.%[%]| ]+", "%1")
	params = params:gsub("([%w_]+)%s*%?", "%1")
	return params
end

local function convertClassBlock(className, baseName, body)
	local inner = body:sub(2, -2)

	inner = "\n" .. inner
	inner = inner:gsub("\n%s*constructor%s*%((.-)%)%s*{", function(params)
		return "\nfunction " .. className .. ":constructor(" .. stripParamTypes(params) .. ")"
	end)
	inner = inner:gsub("\n%s*([%w_]+)%s*%((.-)%)%s*{", function(methodName, params)
		if CONTROL_KEYWORDS[methodName] then
			return "\n" .. methodName .. "(" .. params .. ") {"
		end
		if methodName == "constructor" then
			return "\nfunction " .. className .. ":constructor(" .. stripParamTypes(params) .. ")"
		end
		return "\nfunction " .. className .. ":" .. methodName .. "(" .. stripParamTypes(params) .. ")"
	end)
	inner = inner:gsub("%f[%w]this%.", "self.")

	if baseName then
		inner = inner:gsub("%f[%w]super%.([%w_]+)%s*%(", baseName .. ".%1(self, ")
		inner = inner:gsub("%f[%w]super%s*%((.-)%)", function(args)
			local call = baseName .. ".constructor(self"
			if args:match("%S") then
				call = call .. ", " .. args
			end
			call = call .. ")"
			return "if " .. baseName .. ".constructor then " .. call .. " end"
		end)
	else
		inner = inner:gsub("%f[%w]super%.([%w_]+)%s*%(", "self.%1(")
		inner = inner:gsub("%f[%w]super%s*%((.-)%)", "")
	end

	inner = inner:sub(2)

	local lines = {
		"local " .. className .. " = {}",
		className .. ".__index = " .. className,
	}

	if baseName then
		table.insert(lines, "setmetatable(" .. className .. ", { __index = " .. baseName .. " })")
	end

	table.insert(lines, "function " .. className .. ".new(...)")
	table.insert(lines, "\tlocal self = setmetatable({}, " .. className .. ")")
	table.insert(lines, "\tif self.constructor then")
	table.insert(lines, "\t\tself:constructor(...)")
	table.insert(lines, "\tend")
	table.insert(lines, "\treturn self")
	table.insert(lines, "end")

	if inner:match("%S") then
		table.insert(lines, inner)
	end

	return table.concat(lines, "\n")
end

local function convertClasses(code)
	code = code:gsub("class%s+([%w_]+)%s+extends%s+([%w_]+)%s*(%b{})", function(className, baseName, body)
		return convertClassBlock(className, baseName, body)
	end)
	code = code:gsub("class%s+([%w_]+)%s*(%b{})", function(className, body)
		return convertClassBlock(className, nil, body)
	end)
	return code
end

return {
	process = function(code)
		return {
			{
				name = "comments",
				gsub = function(source)
					source = source:gsub("//(.-)%s*\n", "--%1\n")
					source = source:gsub("/%*(.-)%*/", "--[[%1]]")
					return source
				end,
			},
			{
				name = "templateLiterals",
				gsub = function(source)
					source = source:gsub("`([^`]*)`", function(body)
						local parts = {}
						local cursor = 1
						while cursor <= #body do
							local s, e, expr = body:find("%${(.-)}", cursor)
							if s then
								local staticPart = body:sub(cursor, s - 1)
								if staticPart ~= "" then
									table.insert(parts, '"' .. escapeLuaString(staticPart) .. '"')
								end
								table.insert(parts, "tostring(" .. expr .. ")")
								cursor = e + 1
							else
								local tail = body:sub(cursor)
								if tail ~= "" then
									table.insert(parts, '"' .. escapeLuaString(tail) .. '"')
								end
								break
							end
						end
						if #parts == 0 then
							return '""'
						end
						return table.concat(parts, " .. ")
					end)
					return source
				end,
			},
			{
				name = "importsAndExports",
				gsub = function(source)
					source = source:gsub("import%s+type%s+.-%s*;?%s*\n?", "")

					-- import Foo, { Bar as Baz } from "pkg"
					source = source:gsub(
						"import%s+([%w_]+)%s*,%s*{%s*(.-)%s*}%s+from%s+[\"'][^\"']+[\"']%s*;?%s*\n?",
						function(defaultName, named)
							local lines = { ('local %s = game:GetService("%s")'):format(defaultName, defaultName) }
							for part in named:gmatch("[^,]+") do
								part = trim(part)
								if part ~= "" then
									local imported, alias = part:match("^([%w_]+)%s+as%s+([%w_]+)$")
									if imported and alias then
										table.insert(
											lines,
											('local %s = game:GetService("%s")'):format(alias, imported)
										)
									else
										local name = part:match("^([%w_]+)$")
										if name then
											table.insert(lines, ('local %s = game:GetService("%s")'):format(name, name))
										end
									end
								end
							end
							return table.concat(lines, "\n") .. "\n"
						end
					)

					-- import { Foo, Bar as Baz } from "pkg"
					source = source:gsub(
						"import%s+{%s*(.-)%s*}%s+from%s+[\"'][^\"']+[\"']%s*;?%s*\n?",
						function(bindings)
							local lines = {}
							for part in bindings:gmatch("[^,]+") do
								part = trim(part)
								if part ~= "" then
									local imported, alias = part:match("^([%w_]+)%s+as%s+([%w_]+)$")
									if imported and alias then
										table.insert(
											lines,
											('local %s = game:GetService("%s")'):format(alias, imported)
										)
									else
										local name = part:match("^([%w_]+)$")
										if name then
											table.insert(lines, ('local %s = game:GetService("%s")'):format(name, name))
										end
									end
								end
							end
							if #lines == 0 then
								return ""
							end
							return table.concat(lines, "\n") .. "\n"
						end
					)

					-- import * as Foo from "pkg"
					source = source:gsub(
						"import%s+%*%s+as%s+([%w_]+)%s+from%s+[\"'][^\"']+[\"']%s*;?%s*\n?",
						function(name)
							return ('local %s = game:GetService("%s")\n'):format(name, name)
						end
					)

					-- import Foo from "pkg"
					source = source:gsub("import%s+([%w_]+)%s+from%s+[\"'][^\"']+[\"']%s*;?%s*\n?", function(name)
						return ('local %s = game:GetService("%s")\n'):format(name, name)
					end)

					source = source:gsub("import%s+[\"'][^\"']+[\"']%s*;?%s*\n?", "")
					source = source:gsub("export%s+default%s+", "")
					source = source:gsub("export%s+type%s+.-%s*;?%s*\n?", "")
					source = source:gsub("export%s+", "")
					return source
				end,
			},
			{
				name = "typeDeclarations",
				gsub = function(source)
					source = source:gsub("interface%s+[%w_]+%s*%b{}", "")
					source = source:gsub("type%s+[%w_]+%s*=%s*[^;\n]+;?", "")
					return source
				end,
			},
			{
				name = "enums",
				gsub = function(source)
					source = source:gsub("enum%s+([%w_]+)%s*(%b{})", function(name, body)
						local entries = {}
						local idx = 0
						for entry in (body:sub(2, -2) .. "\n"):gmatch("([^\n,]+)[,\n]") do
							entry = entry:match("^%s*(.-)%s*$")
							if entry ~= "" then
								local k, v = entry:match("([%w_]+)%s*=%s*(.+)")
								if k then
									v = v:match("^%s*(.-)%s*$")
									table.insert(entries, k .. " = " .. v)
									local numericValue = tonumber(v)
									idx = numericValue and (numericValue + 1) or (idx + 1)
								else
									table.insert(entries, entry .. " = " .. idx)
									idx = idx + 1
								end
							end
						end
						return "local " .. name .. " = { " .. table.concat(entries, ", ") .. " }"
					end)
					return source
				end,
			},
			{
				name = "modifiersAndGenerics",
				gsub = function(source)
					for _, kw in ipairs({
						"public",
						"private",
						"protected",
						"readonly",
						"override",
						"abstract",
						"declare",
						"static",
					}) do
						source = source:gsub("%f[%w]" .. kw .. "%f[%W]%s*", "")
					end
					for _ = 1, 3 do
						source = source:gsub("([%w_%.]+)<([^<>%(%)={}\n]-)>", "%1")
					end
					return source
				end,
			},
			{
				name = "typeAnnotations",
				gsub = function(source)
					source = source:gsub("%)%s*:%s*[%w%[%]|%s%.]+%s*{", ") {")
					source = source:gsub(":%s*%b{}", "")
					source = source:gsub("function%s+([%w_%.:]+)%s*%((.-)%)", function(name, params)
						return "function " .. name .. "(" .. stripParamTypes(params) .. ")"
					end)
					source = source:gsub("function%s*%((.-)%)", function(params)
						return "function(" .. stripParamTypes(params) .. ")"
					end)
					source = source:gsub("%((.-)%)%s*=>", function(params)
						return "(" .. stripParamTypes(params) .. ") =>"
					end)
					source = source:gsub("([%w_]+)%s*%?%s*:%s*[%w%.%[%]| ]+%s*=>", "%1 =>")
					source = source:gsub("([%w_]+)%s*:%s*[%w%.%[%]| ]+%s*=>", "%1 =>")
					for _, decl in ipairs({ "const", "let", "var" }) do
						source =
							source:gsub("(%f[%w]" .. decl .. "%f[%W]%s+[%w_]+)%s*%?%s*:%s*[%w%.%[%]| ]+%s*=", "%1 =")
						source = source:gsub("(%f[%w]" .. decl .. "%f[%W]%s+[%w_]+)%s*:%s*[%w%.%[%]| ]+%s*=", "%1 =")
					end
					source = source:gsub("(\n%s*[%w_]+)%s*%?%s*:%s*[%w%.%[%]| ]+%s*=", "%1 =")
					source = source:gsub("(\n%s*[%w_]+)%s*:%s*[%w%.%[%]| ]+%s*=", "%1 =")
					source = source:gsub("^(%s*[%w_]+)%s*%?%s*:%s*[%w%.%[%]| ]+%s*=", "%1 =")
					source = source:gsub("^(%s*[%w_]+)%s*:%s*[%w%.%[%]| ]+%s*=", "%1 =")
					source = source:gsub("(local%s+[%w_]+)%s*%?%s*:%s*[%w%.%[%]| ]+", "%1")
					source = source:gsub("(local%s+[%w_]+)%s*:%s*[%w%.%[%]| ]+", "%1")
					return source
				end,
			},
			{
				name = "assertionsAndNonNull",
				gsub = function(source)
					source = source:gsub("%s+as%s+const", "")
					source = source:gsub("%((.-)%s+as%s+[%w_%.%[%]| ,]+%)", "(%1)")
					for _ = 1, 2 do
						source = source:gsub("([%w_%.%]%)]%s*)as%s+[%w_%.%[%]| ,]+([,%);\n])", "%1%2")
						source = source:gsub("([%w_%.%]%)]%s*)satisfies%s+[%w_%.%[%]| ,]+([,%);\n])", "%1%2")
					end
					source = source:gsub("<[%w_%.%[%]| ,]+>%s*(%b())", "%1")
					source = source:gsub("([%w_%.%]%)]%s*)!%s*([%.,;%)%]%}])", "%1%2")
					source = source:gsub("([%w_%.%]%)]%s*)!%s*\n", "%1\n")
					source = source:gsub("([%w_%.%]%)]%s*)!%s*$", "%1")
					return source
				end,
			},
			{
				name = "arrayLiterals",
				gsub = function(source)
					source = source:gsub("([=,(]%s*)%[%s*%]", "%1{}")
					source = source:gsub("([=,(]%s*)%[([^%[%]\n]-)%]", function(prefix, values)
						return prefix .. "{" .. values .. "}"
					end)
					return source
				end,
			},
			{
				name = "classes",
				gsub = function(source)
					return convertClasses(source)
				end,
			},
			{
				name = "arrowFunctions",
				gsub = function(source)
					for _, kw in ipairs({ "const", "let", "var" }) do
						source = source:gsub(kw .. "%s+([%w_]+)%s*=%s*%((.-)%)%s*=>%s*{", "local %1 = function(%2)")
						source = source:gsub(
							kw .. "%s+([%w_]+)%s*=%s*%((.-)%)%s*=>%s*([^{\n;][^\n;]*)",
							"local %1 = function(%2) return %3 end"
						)
						source = source:gsub(
							kw .. "%s+([%w_]+)%s*=%s*([%w_]+)%s*=>%s*([^{\n;][^\n;]*)",
							"local %1 = function(%2) return %3 end"
						)
					end
					source = source:gsub("%(([%w_%s,]*)%)%s*=>%s*([^{\n;][^\n;]*)", "function(%1) return %2 end")
					source = source:gsub("([%w_]+)%s*=>%s*([^{\n;][^\n;]*)", "function(%1) return %2 end")
					return source
				end,
			},
			{
				name = "variablesAndFunctions",
				gsub = function(source)
					source = source:gsub("%f[%w]const%f[%W]%s+", "local ")
					source = source:gsub("%f[%w]let%f[%W]%s+", "local ")
					source = source:gsub("%f[%w]var%f[%W]%s+", "local ")
					source = source:gsub("async%s+function%s+", "function ")
					source = source:gsub("%f[%w]async%f[%W]%s+", "")
					source = source:gsub("function%s+([%w_%.:]+)%s*%((.-)%)%s*{", "function %1(%2)")
					return source
				end,
			},
			{
				name = "operators",
				gsub = function(source)
					source = source:gsub("===", "==")
					source = source:gsub("!==", "~=")
					source = source:gsub("!=", "~=")
					source = source:gsub("([%w_%.%[%]]+)%s*%?%?=%s*(.-)%s*;", "if %1 == nil then %1 = %2 end")
					source = source:gsub("([%w_%.%[%]]+)%s*&&=%s*(.-)%s*;", "if %1 then %1 = %2 end")
					source = source:gsub("([%w_%.%[%]]+)%s*||=%s*(.-)%s*;", "if not %1 then %1 = %2 end")
					source = source:gsub("&&", " and ")
					source = source:gsub("||", " or ")
					source = source:gsub("^!%s*([%w_%(])", "not %1")
					source = source:gsub("([^~<>!=])!%s*([%w_%(])", "%1not %2")
					source = source:gsub("([%w_%.%[%]%(%)]+)%s*%?%?%s*([%w_%.%[%]%(%)\"']+)", "%1 ~= nil and %1 or %2")
					source = source:gsub("([%w_%.%[%]%(%)]+)%?%.([%w_]+)", "%1 and %1.%2")
					source = source:gsub("([%w_%.%[%]%(%)]+)%?%.([%w_]+)%s*%(", "%1 and %1.%2(")
					source = source:gsub("delete%s+([%w_%.]+)%[([^%]]+)%]%s*;", "%1[%2] = nil;")
					source = source:gsub("delete%s+([%w_%.]+)%s*;", "%1 = nil;")
					source = source:gsub("([%w_%.%[%]\"']+)%s+in%s+([%w_%.%[%]]+)", "%2[%1] ~= nil")
					source = source:gsub("([%w_%.%[%]]+)%s+instanceof%s+([%w_%.]+)", "getmetatable(%1) == %2")
					source = source:gsub("%.%.%.([%w_]+)", "table.unpack(%1)")
					source = source:gsub("%*%*", "^")
					source = source:gsub("([%w_%.%[%]]+)%s*%+=%s*(.-)%s*;", "%1 = %1 + %2")
					source = source:gsub("([%w_%.%[%]]+)%s*%-=%s*(.-)%s*;", "%1 = %1 - %2")
					source = source:gsub("([%w_%.%[%]]+)%s*%*=%s*(.-)%s*;", "%1 = %1 * %2")
					source = source:gsub("([%w_%.%[%]]+)%s*/=%s*(.-)%s*;", "%1 = %1 / %2")
					source = source:gsub("([%w_%.%[%]]+)%s*%%=%s*(.-)%s*;", "%1 = %1 %% %2")
					source = source:gsub("([%w_%.%[%]]+)%+%+%s*;", "%1 = %1 + 1")
					source = source:gsub("([%w_%.%[%]]+)%-%-%s*;", "%1 = %1 - 1")
					return source
				end,
			},
			{
				name = "controlFlow",
				gsub = function(source)
					source = source:gsub(
						"for%s*%(%s*%w*%s*([%w_]+)%s*=%s*(.-)%s*;%s*%1%s*<%s*(.-)%s*;%s*%1%+%+%s*%)%s*{?",
						"for %1 = %2, (%3) - 1 do"
					)
					source = source:gsub(
						"for%s*%(%s*%w*%s*([%w_]+)%s*=%s*(.-)%s*;%s*%1%s*<=%s*(.-)%s*;%s*%1%+%+%s*%)%s*{?",
						"for %1 = %2, %3 do"
					)
					source = source:gsub(
						"for%s*%(%s*%w*%s*([%w_]+)%s*=%s*(.-)%s*;%s*%1%s*>=%s*(.-)%s*;%s*%1%-%-%s*%)%s*{?",
						"for %1 = %2, %3, -1 do"
					)
					source = source:gsub(
						"for%s*%(%s*%w*%s*([%w_]+)%s*=%s*(.-)%s*;%s*%1%s*>%s*([^=].-)%s*;%s*%1%-%-%s*%)%s*{?",
						"for %1 = %2, (%3) + 1, -1 do"
					)
					source = source:gsub(
						"for%s+await%s*%(%s*%w+%s+([%w_]+)%s+of%s+([%w_%.]+)%s*%)%s*{?",
						"for _, %1 in ipairs(%2) do"
					)
					source = source:gsub(
						"for%s*%(%s*%w+%s+([%w_]+)%s+of%s+([%w_%.]+)%s*%)%s*{?",
						"for _, %1 in ipairs(%2) do"
					)
					source = source:gsub(
						"for%s*%(%s*%w+%s+([%w_]+)%s+in%s+([%w_%.]+)%s*%)%s*{?",
						"for %1, _ in pairs(%2) do"
					)
					source = source:gsub("%f[%w]do%f[%W]%s*{", "repeat")
					source = source:gsub("}%s*while%s*%((.-)%)%s*;?", "until not (%1)")
					source = source:gsub("while%s*%((.-)%)%s*{", "while %1 do")
					source = source:gsub("while%s*%((.-)%)", "while %1 do")
					source = source:gsub("else%s+if%s*%((.-)%)%s*{", "elseif %1 then")
					source = source:gsub("else%s+if%s*%((.-)%)", "elseif %1 then")
					source = source:gsub("if%s*%((.-)%)%s*{", "if %1 then")
					source = source:gsub("if%s*%((.-)%)", "if %1 then")
					source = source:gsub("else%s*{", "else")
					source = source:gsub("try%s*{", "local __tryOk, __tryErr = pcall(function()")
					source =
						source:gsub("}%s*catch%s*%(([%w_]+)%)%s*{", "end)\nif not __tryOk then\nlocal %1 = __tryErr\n")
					source = source:gsub("%f[%w]finally%f[%W]%s*{", "-- finally")
					source = source:gsub("switch%s*%((.-)%)%s*{", "-- switch (%1) not converted\ndo")
					source = source:gsub("case%s+(.-)%s*:", "-- case %1:")
					source = source:gsub("%f[%w]default%f[%W]%s*:", "-- default:")
					source = source:gsub("%f[%w]break%f[%W]%s*;?", "")
					source = source:gsub("%f[%w]continue%f[%W]%s*;?", "-- continue not supported in Luau")
					source = source:gsub("%f[%w]throw%f[%W]%s+new%s+[%w_]+%s*%((.-)%)%s*;?", "error(%1)")
					source = source:gsub("%f[%w]throw%f[%W]%s*(.-)%s*;", "error(%1)")
					return source
				end,
			},
			{
				name = "builtins",
				gsub = function(source)
					source = source:gsub("console%.[%w_]+%(", "print(")
					source = source:gsub("Math%.floor%(", "math.floor(")
					source = source:gsub("Math%.ceil%(", "math.ceil(")
					source = source:gsub("Math%.round%(", "math.round(")
					source = source:gsub("Math%.abs%(", "math.abs(")
					source = source:gsub("Math%.sqrt%(", "math.sqrt(")
					source = source:gsub("Math%.pow%(", "math.pow(")
					source = source:gsub("Math%.max%(", "math.max(")
					source = source:gsub("Math%.min%(", "math.min(")
					source = source:gsub("Math%.random%(%)", "math.random()")
					source = source:gsub("Math%.PI", "math.pi")
					source = source:gsub("Array%.isArray%((.-)%)", 'type(%1) == "table"')
					source = source:gsub("Boolean%((.-)%)", "not not (%1)")
					source = source:gsub("Date%.now%(%)", "os.clock()")
					source = source:gsub("([%w_]+)%.push%(", "table.insert(%1, ")
					source = source:gsub("([%w_]+)%.pop%(%)", "table.remove(%1)")
					source = source:gsub("([%w_]+)%.length", "#%1")
					source = source:gsub("([%w_]+)%.shift%(%)", "table.remove(%1, 1)")
					source = source:gsub("([%w_]+)%.unshift%(", "table.insert(%1, 1, ")
					source = source:gsub("([%w_]+)%.includes%(", "table.find(%1, ")
					source = source:gsub("([%w_]+)%.indexOf%(", "table.find(%1, ")
					source = source:gsub("([%w_]+)%.join%((.-)%)", "table.concat(%1, %2)")
					source = source:gsub("([%w_]+)%.toString%(%)", "tostring(%1)")
					source = source:gsub("([%w_]+)%.toLowerCase%(%)", "string.lower(%1)")
					source = source:gsub("([%w_]+)%.toUpperCase%(%)", "string.upper(%1)")
					source = source:gsub("([%w_]+)%.trim%(%)", "string.match(%1, '^%s*(.-)%s*$')")
					source = source:gsub("([%w_]+)%.split%((.-)%)", "string.split(%1, %2)")
					source = source:gsub("([%w_]+)%.substring%(", "string.sub(%1, ")
					source = source:gsub("([%w_]+)%.slice%(", "string.sub(%1, ")
					source = source:gsub("([%w_]+)%.replace%((.-),%s*(.-)%)", "string.gsub(%1, %2, %3)")
					source = source:gsub("([%w_]+)%.startsWith%((.-)%)", "string.sub(%1, 1, #%2) == %2")
					source = source:gsub("([%w_]+)%.endsWith%((.-)%)", "string.sub(%1, -#%2) == %2")
					source = source:gsub("Number%((.-)%)", "tonumber(%1)")
					source = source:gsub("String%((.-)%)", "tostring(%1)")
					source = source:gsub("parseInt%((.-)%)", "math.floor(tonumber(%1))")
					source = source:gsub("parseFloat%((.-)%)", "tonumber(%1)")
					source = source:gsub("isNaN%((.-)%)", "(%1 ~= %1)")
					source = source:gsub("Object%.hasOwn%((.-),%s*(.-)%)", "(%1[%2] ~= nil)")
					source = source:gsub("typeof%s+([%w_%.]+)", "type(%1)")
					source = source:gsub("typeof%((.-)%)", "type(%1)")
					source = source:gsub("%f[%w]undefined%f[%W]", "nil")
					source = source:gsub("%f[%w]null%f[%W]", "nil")
					source = source:gsub("void%s+0", "nil")
					source = source:gsub("%f[%w]await%f[%W]%s+", "")
					source = source:gsub("new%s+([%w_%.]+)%s*%((.-)%)", "%1.new(%2)")
					source = source:gsub("%.then%(", ":andThen(")
					source = source:gsub("%.catch%(", ":catch(")
					source = source:gsub("%.finally%(", ":finally(")
					return source
				end,
			},
			{
				name = "destructuring",
				gsub = function(source)
					source = source:gsub("local%s*{([^}]+)}%s*=%s*([%w_%.]+)", function(keys, obj)
						local lines = {}
						for part in keys:gmatch("[^,]+") do
							part = trim(part)
							if part ~= "" then
								local srcKey, alias, fallback = part:match("^([%w_]+)%s*:%s*([%w_]+)%s*=%s*(.+)$")
								if srcKey then
									table.insert(
										lines,
										("local %s = (%s.%s ~= nil) and %s.%s or %s"):format(
											alias,
											obj,
											srcKey,
											obj,
											srcKey,
											fallback
										)
									)
								else
									srcKey, alias = part:match("^([%w_]+)%s*:%s*([%w_]+)$")
									if srcKey then
										table.insert(lines, "local " .. alias .. " = " .. obj .. "." .. srcKey)
									else
										srcKey, fallback = part:match("^([%w_]+)%s*=%s*(.+)$")
										if srcKey then
											table.insert(
												lines,
												("local %s = (%s.%s ~= nil) and %s.%s or %s"):format(
													srcKey,
													obj,
													srcKey,
													obj,
													srcKey,
													fallback
												)
											)
										else
											local key = part:match("^([%w_]+)$")
											if key then
												table.insert(lines, "local " .. key .. " = " .. obj .. "." .. key)
											end
										end
									end
								end
							end
						end
						return table.concat(lines, "\n")
					end)
					source = source:gsub("local%s*%[([^%]]+)%]%s*=%s*([%w_%.]+)", function(keys, arr)
						local lines = {}
						local idx = 1
						for part in (keys .. ","):gmatch("([^,]*),") do
							part = trim(part)
							if part ~= "" then
								local key, fallback = part:match("^([%w_]+)%s*=%s*(.+)$")
								if key then
									table.insert(
										lines,
										("local %s = (%s[%d] ~= nil) and %s[%d] or %s"):format(
											key,
											arr,
											idx,
											arr,
											idx,
											fallback
										)
									)
								else
									key = part:match("^([%w_]+)$")
									if key then
										table.insert(lines, ("local %s = %s[%d]"):format(key, arr, idx))
									end
								end
							end
							idx = idx + 1
						end
						return table.concat(lines, "\n")
					end)
					return source
				end,
			},
			{
				name = "objectLiterals",
				gsub = function(source)
					-- Convert JS object fields to Lua table fields inside literal contexts.
					for _ = 1, 3 do
						source = source:gsub("([,{]%s*)([%a_][%w_]*)%s*:%s*", "%1%2 = ")
						source = source:gsub('({%s*)"([^"]+)"%s*:%s*', '%1["%2"] = ')
						source = source:gsub('(,%s*)"([^"]+)"%s*:%s*', '%1["%2"] = ')
						source = source:gsub("({%s*)'([^']+)'%s*:%s*", "%1['%2'] = ")
						source = source:gsub("(,%s*)'([^']+)'%s*:%s*", "%1['%2'] = ")
					end
					return source
				end,
			},
			{
				name = "ternary",
				gsub = function(source)
					source = source:gsub(
						"([%w_%.%(%)%[%]\"']+)%s*%?%s*([%w_%.%(%)%[%]\"']+)%s*:%s*([%w_%.%(%)%[%]\"']+)",
						"(%1 and %2 or %3)"
					)
					return source
				end,
			},
			{
				name = "bracesAndSemicolons",
				gsub = function(source)
					source = source:gsub("%)%s*{", ")")
					source = source:gsub("then%s*{", "then")
					source = source:gsub("do%s*{", "do")
					source = source:gsub("else%s*{", "else")
					source = source:gsub("}%s*else", "\nelse")
					source = source:gsub("}%s*elseif", "\nelseif")
					source = source:gsub(";%s*}%s*", ";\nend\n")
					source = source:gsub("\n%s*}%s*;?%s*\n", "\nend\n")
					source = source:gsub("\n%s*}%s*;?%s*$", "\nend")
					source = source:gsub("([%w_%)]%s*)}%s*$", "%1end")
					source = source:gsub(";%s*", "\n")
					return source
				end,
			},
			{
				name = "cleanup",
				gsub = function(source)
					-- Normalize method calls to obj:method(...)
					source = source:gsub(":%s+([%w_]+)%s*%(", ":%1(")
					source = source:gsub("\n\n\n+", "\n\n")
					source = source:gsub("([^\n]*) +\n", "%1\n")
					return source
				end,
			},
		}, {}
	end,
}
