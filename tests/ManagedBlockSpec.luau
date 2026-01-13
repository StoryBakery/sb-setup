--[[
	ManagedBlock 모듈 테스트를 제공하는 모듈입니다.
]]

local ManagedBlock = require("../src/modules/ManagedBlock")

local tests = {}

table.insert(tests, {
	Name = "Replaces block content",
	Run = function()
		local template = [[
-- BEGIN STORY BAKERY MANAGED BLOCK: sb.replace
New Line
-- END STORY BAKERY MANAGED BLOCK: sb.replace
]]
		local destination = [[
-- BEGIN STORY BAKERY MANAGED BLOCK: sb.replace
Old Line
-- END STORY BAKERY MANAGED BLOCK: sb.replace
]]
		local info = ManagedBlock.ParseTemplate(template)
		local merged = ManagedBlock.Merge(destination, info)
		if not merged:find("New Line", 1, true) then
			return false, "Expected new line to exist."
		end
		if merged:find("Old Line", 1, true) then
			return false, "Old line should be replaced."
		end
		return true
	end,
})

table.insert(tests, {
	Name = "Appends block content",
	Run = function()
		local template = [[
-- BEGIN STORY BAKERY MANAGED BLOCK: sb.append [mode=append]
Appended Line
-- END STORY BAKERY MANAGED BLOCK: sb.append
]]
		local destination = [[
-- BEGIN STORY BAKERY MANAGED BLOCK: sb.append
Base Line
-- END STORY BAKERY MANAGED BLOCK: sb.append
]]
		local info = ManagedBlock.ParseTemplate(template)
		local merged = ManagedBlock.Merge(destination, info)
		if not merged:find("Base Line", 1, true) then
			return false, "Expected base line to exist."
		end
		if not merged:find("Appended Line", 1, true) then
			return false, "Expected appended line to exist."
		end
		return true
	end,
})

table.insert(tests, {
	Name = "Removes block content",
	Run = function()
		local template = [[
-- BEGIN STORY BAKERY MANAGED BLOCK: sb.remove [mode=remove]
Removed Line
-- END STORY BAKERY MANAGED BLOCK: sb.remove
]]
		local destination = [[
-- BEGIN STORY BAKERY MANAGED BLOCK: sb.remove
Removed Line
-- END STORY BAKERY MANAGED BLOCK: sb.remove
]]
		local info = ManagedBlock.ParseTemplate(template)
		local merged = ManagedBlock.Merge(destination, info)
		if merged:find("sb.remove", 1, true) then
			return false, "Expected block markers to be removed."
		end
		return true
	end,
})

table.insert(tests, {
	Name = "Inserts missing block",
	Run = function()
		local template = [[
-- BEGIN STORY BAKERY MANAGED BLOCK: sb.insert
Inserted Line
-- END STORY BAKERY MANAGED BLOCK: sb.insert
]]
		local destination = "Plain content"
		local info = ManagedBlock.ParseTemplate(template)
		local merged = ManagedBlock.Merge(destination, info)
		if not merged:find("sb.insert", 1, true) then
			return false, "Expected inserted block to exist."
		end
		if not merged:find("Inserted Line", 1, true) then
			return false, "Expected inserted line to exist."
		end
		return true
	end,
})

local ManagedBlockSpec = {
	Name = "ManagedBlock",
	Tests = tests,
}

return ManagedBlockSpec
