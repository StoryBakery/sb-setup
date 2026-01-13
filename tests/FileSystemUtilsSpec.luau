--[[
	FileSystemUtils 모듈 테스트를 제공하는 모듈입니다.
]]

local FileSystemUtils = require("../src/modules/FileSystemUtils")

local tests = {}

table.insert(tests, {
	Name = "Joins paths consistently",
	Run = function()
		if FileSystemUtils.JoinPath("", "bar") ~= "bar" then
			return false, "Empty base path should return child."
		end
		if FileSystemUtils.JoinPath("foo", "") ~= "foo" then
			return false, "Empty child path should return base."
		end
		if FileSystemUtils.JoinPath("foo", "bar") ~= "foo/bar" then
			return false, "Basic join mismatch."
		end
		if FileSystemUtils.JoinPath("foo/", "bar") ~= "foo/bar" then
			return false, "Trailing slash join mismatch."
		end
		return true
	end,
})

table.insert(tests, {
	Name = "Gets directory name",
	Run = function()
		if FileSystemUtils.GetDirectoryName("foo/bar.txt") ~= "foo" then
			return false, "Directory name mismatch."
		end
		if FileSystemUtils.GetDirectoryName("bar.txt") ~= "" then
			return false, "Expected empty directory name."
		end
		return true
	end,
})

local FileSystemUtilsSpec = {
	Name = "FileSystemUtils",
	Tests = tests,
}

return FileSystemUtilsSpec
