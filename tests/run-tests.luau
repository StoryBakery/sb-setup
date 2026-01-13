--[[
	테스트를 실행하는 러너 스크립트입니다.
]]

local Process = require("@lune/process")

local FileSystemUtilsSpec = require("./FileSystemUtilsSpec")
local ManagedBlockSpec = require("./ManagedBlockSpec")
local TomlParserSpec = require("./TomlParserSpec")

local TEST_SUITES = {
	FileSystemUtilsSpec,
	ManagedBlockSpec,
	TomlParserSpec,
}

local function runSuite(suite)
	local passed = 0
	local failed = 0

	for _, test in suite.Tests do
		local ok, result, detail = pcall(test.Run)
		if ok and result == true then
			print(`[Pass] {suite.Name} - {test.Name}`)
			passed += 1
		else
			local message = ""
			if ok then
				message = detail or "Test failed."
			else
				message = tostring(result)
			end
			print(`[Fail] {suite.Name} - {test.Name}: {message}`)
			failed += 1
		end
	end

	return passed, failed
end

local totalPassed = 0
local totalFailed = 0

for _, suite in TEST_SUITES do
	local passed, failed = runSuite(suite)
	totalPassed += passed
	totalFailed += failed
end

print(`[Summary] Passed: {totalPassed}, Failed: {totalFailed}`)

if totalFailed > 0 then
	Process.exit(1)
end
