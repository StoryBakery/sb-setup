--[[
	TomlParser 모듈 테스트를 제공하는 모듈입니다.
]]

local TomlParser = require("../src/modules/TomlParser")

local tests = {}

table.insert(tests, {
	Name = "Parses string and array values",
	Run = function()
		local ok, result = TomlParser.Parse([[
Name = "base"
Templates = ["base", "non-luau"]
]])
		if not ok then
			return false, "Parse failed."
		end
		if result.Name ~= "base" then
			return false, "Name mismatch."
		end
		local templates = result.Templates
		if type(templates) ~= "table" then
			return false, "Templates is not a table."
		end
		if #templates ~= 2 then
			return false, "Templates count mismatch."
		end
		if templates[1] ~= "base" or templates[2] ~= "non-luau" then
			return false, "Templates values mismatch."
		end
		return true
	end,
})

table.insert(tests, {
	Name = "Parses array table entries",
	Run = function()
		local ok, result = TomlParser.Parse([=[
[[Templates]]
Name = "base"

[[Templates]]
Name = "custom"
Source = "setup_configs/templates/custom"
]=])
		if not ok then
			return false, "Parse failed."
		end
		local templates = result.Templates
		if type(templates) ~= "table" then
			return false, "Templates is not a table."
		end
		if #templates ~= 2 then
			return false, "Templates count mismatch."
		end
		if templates[1].Name ~= "base" then
			return false, "First template name mismatch."
		end
		if templates[2].Name ~= "custom" then
			return false, "Second template name mismatch."
		end
		if templates[2].Source ~= "setup_configs/templates/custom" then
			return false, "Template source mismatch."
		end
		return true
	end,
})

table.insert(tests, {
	Name = "Keeps hash inside strings",
	Run = function()
		local ok, result = TomlParser.Parse([[
Name = "hash # inside"
# comment line
]])
		if not ok then
			return false, "Parse failed."
		end
		if result.Name ~= "hash # inside" then
			return false, "Hash string mismatch."
		end
		return true
	end,
})

table.insert(tests, {
	Name = "Fails on invalid line",
	Run = function()
		local ok = TomlParser.Parse("InvalidLine")
		if ok then
			return false, "Expected parse failure."
		end
		return true
	end,
})

local TomlParserSpec = {
	Name = "TomlParser",
	Tests = tests,
}

return TomlParserSpec
