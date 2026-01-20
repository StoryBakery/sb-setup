--[[
	프로젝트 루트에서 Selene 문법 검사를 실행하는 스크립트입니다.
]]

local Process = require("@lune/process")

local okExec, resultOrErr = pcall(Process.exec, "selene", { "." }, { capture = true })
if not okExec then
	print(`[Error] Failed to run selene: {resultOrErr}`)
	Process.exit(1)
end

local result = resultOrErr
local stdout = result.stdout or ""
local stderr = result.stderr or ""
if stdout ~= "" then
	print(stdout)
end
if stderr ~= "" then
	print(stderr)
end

if not result.ok then
	print("[Error] Selene reported issues.")
	Process.exit(result.exitCode or 1)
end
