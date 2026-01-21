--[[
	템플릿 조합 테스트를 실행하는 스크립트입니다.
]]

local FileSystem = require("@lune/fs")
local Process = require("@lune/process")

local FileSystemUtils = require("../src/modules/FileSystemUtils")

local function normalizeSourcePath(source: string): string
	local normalized = source
	if normalized:sub(1, 1) == "@" then
		normalized = normalized:sub(2)
	end
	return normalized:gsub("\\", "/")
end

local function resolveRepoRoot(fileSystemUtils): string
	local source = debug.info(1, "s")
	if source == nil or source == "" then
		return "."
	end

	local scriptPath = normalizeSourcePath(source)
	local testsDir = fileSystemUtils.GetDirectoryName(scriptPath)
	if testsDir == "" then
		return "."
	end

	local repoRoot = fileSystemUtils.GetDirectoryName(testsDir)
	if repoRoot == "" then
		return "."
	end

	return repoRoot
end

local function buildProjectConfigContent(templates: { string }): string
	local quoted: { string } = {}
	for _, name in templates do
		table.insert(quoted, `"{name}"`)
	end
	return `Templates = [{table.concat(quoted, ", ")}]\n`
end

local function writeProjectConfig(path: string, templates: { string }, fileSystemUtils): boolean
	local content = buildProjectConfigContent(templates)
	local okWrite, err = pcall(function()
		FileSystem.writeFile(path, content)
	end)
	if not okWrite then
		print(`[Error] Failed to write config: {tostring(err)}`)
		return false
	end
	return true
end

local function runTestCase(
	caseName: string,
	templates: { string },
	applyScriptPath: string,
	tmpRoot: string,
	index: number,
	fileSystemUtils
): boolean
	local runId = tostring(os.time()) .. "-" .. tostring(index)
	local caseDirName = caseName .. "-" .. runId
	local caseRoot = fileSystemUtils.JoinPath(tmpRoot, caseDirName)
	fileSystemUtils.MakeDirectoryRecursive(caseRoot)

	local configPath = fileSystemUtils.JoinPath(caseRoot, "bakery_project_configs.toml")
	local okWrite = writeProjectConfig(configPath, templates, fileSystemUtils)
	if not okWrite then
		return false
	end

	local templateLabel = table.concat(templates, ", ")
	print(`[Test] Running \"{caseName}\" with templates: {templateLabel}`)

	local okExec, resultOrErr = pcall(
		Process.exec,
		"lune",
		{ "run", applyScriptPath },
		{ capture = true, cwd = caseRoot }
	)
	if not okExec then
		print(`[Test] Failed to run lune: {tostring(resultOrErr)}`)
		return false
	end

	local result = resultOrErr
	if not result.ok then
		local stdout = result.stdout or ""
		local stderr = result.stderr or ""
		print(`[Test] Case \"{caseName}\" failed.`)
		if stdout ~= "" then
			print(`[Test] stdout: {stdout}`)
		end
		if stderr ~= "" then
			print(`[Test] stderr: {stderr}`)
		end
		return false
	end

	if result.stdout ~= nil and result.stdout ~= "" then
		print(result.stdout)
	end

	return true
end

local repoRoot = resolveRepoRoot(FileSystemUtils)
local testsRoot = FileSystemUtils.JoinPath(repoRoot, "tests")
local tmpRoot = FileSystemUtils.JoinPath(testsRoot, ".tmp")
FileSystemUtils.MakeDirectoryRecursive(tmpRoot)

local applyScriptPath = FileSystemUtils.JoinPath(testsRoot, "ApplyTemplates.luau")
if not FileSystem.isFile(applyScriptPath) then
	print(`[Error] Missing ApplyTemplates script at \"{applyScriptPath}\".`)
	Process.exit(1)
end

local testCases = {
	{
		Name = "base",
		Templates = { "base" },
	},
	{
		Name = "non-luau",
		Templates = { "base", "non-luau" },
	},
	{
		Name = "roblox-place",
		Templates = { "base", "roblox-place" },
	},
	{
		Name = "with-docs",
		Templates = { "base", "with-docs" },
	},
	{
		Name = "with-bakery-dev-handbook",
		Templates = { "base", "with-bakery-dev-handbook" },
	},
	{
		Name = "pesde-default-packages",
		Templates = { "base", "pesde-default-packages" },
	},
	{
		Name = "docs-and-handbook",
		Templates = { "base", "with-docs", "with-bakery-dev-handbook" },
	},
	{
		Name = "docs-and-pesde",
		Templates = { "base", "with-docs", "pesde-default-packages" },
	},
	{
		Name = "all-templates",
		Templates = {
			"base",
			"non-luau",
			"roblox-place",
			"with-docs",
			"with-bakery-dev-handbook",
			"pesde-default-packages",
		},
	},
}

local failed = 0
for index, case in testCases do
	local ok = runTestCase(
		case.Name,
		case.Templates,
		applyScriptPath,
		tmpRoot,
		index,
		FileSystemUtils
	)
	if not ok then
		failed += 1
	end
end

if failed > 0 then
	print(`[Test] Failed cases: {failed}`)
	Process.exit(1)
end

print("[Test] All template cases passed.")
Process.exit(0)
