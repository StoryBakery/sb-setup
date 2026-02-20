--[[
	템플릿 조합 테스트를 실행하는 스크립트입니다.
]]

local FileSystem = require("@lune/fs")
local Process = require("@lune/process")

local FileSystemUtils = require("../src/modules/FileSystemUtils")
local TomlParser = require("../src/modules/TomlParser")

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

local function removeDirectoryRecursive(path: string, fileSystemUtils): boolean
	if not FileSystem.isDir(path) then
		return true
	end

	local okRead, entriesOrErr = pcall(FileSystem.readDir, path)
	if not okRead or entriesOrErr == nil then
		local detail = tostring(entriesOrErr)
		print(`[Error] Failed to read directory "{path}": {detail}`)
		return false
	end

	for _, entryName in entriesOrErr do
		local entryPath = fileSystemUtils.JoinPath(path, entryName)
		if FileSystem.isDir(entryPath) then
			local okRemoveChild = removeDirectoryRecursive(entryPath, fileSystemUtils)
			if not okRemoveChild then
				return false
			end
		else
			local okRemoveFile, err = pcall(FileSystem.removeFile, entryPath)
			if not okRemoveFile then
				print(`[Error] Failed to remove file "{entryPath}": {tostring(err)}`)
				return false
			end
		end
	end

	local okRemoveDir, err = pcall(FileSystem.removeDir, path)
	if not okRemoveDir then
		print(`[Error] Failed to remove directory "{path}": {tostring(err)}`)
		return false
	end

	return true
end

local function serializeTemplateEntry(entry): (boolean, string?)
	if type(entry) == "string" then
		if entry == "" then
			return false, "Template name is empty."
		end
		return true, `"{entry}"`
	end

	if type(entry) ~= "table" then
		return false, "Template entry must be a string or table."
	end

	local name = entry.Name
	if type(name) ~= "string" or name == "" then
		return false, "Template entry Name is invalid."
	end

	local fields = { `Name = "{name}"` }
	local source = entry.Source
	if source ~= nil then
		if type(source) ~= "string" or source == "" then
			return false, "Template entry Source is invalid."
		end
		table.insert(fields, `Source = "{source}"`)
	end

	local enableScripts = entry.EnableScripts
	if enableScripts ~= nil then
		if type(enableScripts) ~= "boolean" then
			return false, "Template entry EnableScripts is invalid."
		end
		local value = if enableScripts then "true" else "false"
		table.insert(fields, `EnableScripts = {value}`)
	end

	return true, "{ " .. table.concat(fields, ", ") .. " }"
end

local function buildProjectConfigContent(templates: { [number]: any }): (boolean, string?)
	local serialized: { string } = {}
	for _, entry in templates do
		local okSerialize, valueOrErr = serializeTemplateEntry(entry)
		if not okSerialize then
			return false, valueOrErr
		end
		table.insert(serialized, valueOrErr)
	end
	return true, `Templates = [{table.concat(serialized, ", ")}]\n`
end

local function writeProjectConfig(path: string, templates: { [number]: any }, fileSystemUtils): boolean
	local okBuild, contentOrErr = buildProjectConfigContent(templates)
	if not okBuild or contentOrErr == nil then
		local detail = contentOrErr or "unknown"
		print(`[Error] Failed to build config content: {detail}`)
		return false
	end

	local content = contentOrErr
	local okWrite, err = pcall(function()
		FileSystem.writeFile(path, content)
	end)
	if not okWrite then
		print(`[Error] Failed to write config: {tostring(err)}`)
		return false
	end
	return true
end

local function buildTemplateLabel(templates: { [number]: any }): string
	local labels: { string } = {}
	for _, entry in templates do
		if type(entry) == "string" then
			table.insert(labels, entry)
		elseif type(entry) == "table" then
			local name = entry.Name
			if type(name) == "string" and name ~= "" then
				table.insert(labels, name)
			else
				table.insert(labels, "unknown")
			end
		else
			table.insert(labels, "unknown")
		end
	end

	if #labels == 0 then
		return "none"
	end

	return table.concat(labels, ", ")
end

local function countTemplateNames(templateNameSet: { [string]: boolean }): number
	local count = 0
	for _ in templateNameSet do
		count += 1
	end
	return count
end

local function buildTemplateNameSet(templateNames: { string }): { [string]: boolean }
	local templateNameSet: { [string]: boolean } = {}
	for _, name in templateNames do
		templateNameSet[name] = true
	end
	return templateNameSet
end

local function hasSameTemplateNames(actualTemplates: { string }, expectedTemplates: { string }): boolean
	local actualTemplateNameSet = buildTemplateNameSet(actualTemplates)
	local expectedTemplateNameSet = buildTemplateNameSet(expectedTemplates)

	local actualCount = countTemplateNames(actualTemplateNameSet)
	local expectedCount = countTemplateNames(expectedTemplateNameSet)
	if actualCount ~= expectedCount then
		return false
	end

	for name in expectedTemplateNameSet do
		if not actualTemplateNameSet[name] then
			return false
		end
	end

	return true
end

local function readConfiguredTemplateNames(configPath: string): (boolean, { string }?)
	local okRead, configDataOrErr = TomlParser.ReadFile(configPath)
	if not okRead then
		local code = configDataOrErr.Code or "unknown"
		local detail = configDataOrErr.Detail or ""
		print(`[Error] Failed to read config "{configPath}" ({code}): {detail}`)
		return false, nil
	end

	local templates = configDataOrErr.Templates
	if type(templates) ~= "table" then
		print(`[Error] Templates field is missing in "{configPath}".`)
		return false, nil
	end

	local templateNames: { string } = {}
	for _, entry in templates do
		if type(entry) == "string" then
			if entry ~= "" then
				table.insert(templateNames, entry)
			end
		elseif type(entry) == "table" then
			local name = entry.Name
			if type(name) == "string" and name ~= "" then
				table.insert(templateNames, name)
			end
		end
	end

	return true, templateNames
end

local function runTestCase(
	caseName: string,
	templates: { [number]: any },
	applyScriptPath: string,
	tmpRoot: string,
	index: number,
	fileSystemUtils
): boolean
	local runId = tostring(os.time()) .. "-" .. tostring(index)
	local caseDirName = caseName .. "-" .. runId
	local caseRoot = fileSystemUtils.JoinPath(tmpRoot, caseDirName)
	fileSystemUtils.MakeDirectoryRecursive(caseRoot)

	local configPath = fileSystemUtils.JoinPath(caseRoot, "sb_setup_configs.toml")
	local okWrite = writeProjectConfig(configPath, templates, fileSystemUtils)
	if not okWrite then
		return false
	end

	local templateLabel = buildTemplateLabel(templates)
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

	local okCleanup = removeDirectoryRecursive(caseRoot, fileSystemUtils)
	if not okCleanup then
		return false
	end

	return true
end

local function runConfigCommandTestCase(
	caseName: string,
	initialTemplates: { [number]: any },
	input: string,
	expectedTemplates: { string },
	initScriptPath: string,
	tmpRoot: string,
	index: number,
	fileSystemUtils
): boolean
	local runId = tostring(os.time()) .. "-config-" .. tostring(index)
	local caseDirName = caseName .. "-" .. runId
	local caseRoot = fileSystemUtils.JoinPath(tmpRoot, caseDirName)
	fileSystemUtils.MakeDirectoryRecursive(caseRoot)

	local configPath = fileSystemUtils.JoinPath(caseRoot, "sb_setup_configs.toml")
	local okWrite = writeProjectConfig(configPath, initialTemplates, fileSystemUtils)
	if not okWrite then
		return false
	end

	print(`[Test] Running "{caseName}" config command test.`)

	local okExec, resultOrErr = pcall(
		Process.exec,
		"lune",
		{ "run", initScriptPath, "config" },
		{
			capture = true,
			cwd = caseRoot,
			stdio = { stdin = input },
		}
	)
	if not okExec then
		print(`[Test] Failed to run config command: {tostring(resultOrErr)}`)
		return false
	end

	local result = resultOrErr
	if not result.ok then
		local stdout = result.stdout or ""
		local stderr = result.stderr or ""
		print(`[Test] Config case "{caseName}" failed.`)
		if stdout ~= "" then
			print(`[Test] stdout: {stdout}`)
		end
		if stderr ~= "" then
			print(`[Test] stderr: {stderr}`)
		end
		return false
	end

	local okRead, configuredTemplates = readConfiguredTemplateNames(configPath)
	if not okRead or configuredTemplates == nil then
		return false
	end

	local hasSame = hasSameTemplateNames(configuredTemplates, expectedTemplates)
	if not hasSame then
		local expectedLabel = table.concat(expectedTemplates, ", ")
		local actualLabel = table.concat(configuredTemplates, ", ")
		print(`[Test] Config case "{caseName}" template mismatch.`)
		print(`[Test] expected: {expectedLabel}`)
		print(`[Test] actual: {actualLabel}`)
		return false
	end

	local okCleanup = removeDirectoryRecursive(caseRoot, fileSystemUtils)
	if not okCleanup then
		return false
	end

	return true
end

local function runStandaloneTemplateDiscoveryTest(
	repoRoot: string,
	tmpRoot: string,
	fileSystemUtils
): boolean
	local buildScriptPath = fileSystemUtils.JoinPath(repoRoot, "scripts/BuildStandalone.luau")
	local standaloneEntryPath = fileSystemUtils.JoinPath(repoRoot, "build/init.standalone.luau")
	local runId = tostring(os.time()) .. "-standalone"
	local caseRoot = fileSystemUtils.JoinPath(tmpRoot, "standalone-" .. runId)
	fileSystemUtils.MakeDirectoryRecursive(caseRoot)

	print("[Test] Running standalone template discovery test.")

	local okBuildExec, buildResultOrErr =
		pcall(Process.exec, "lune", { "run", buildScriptPath }, { capture = true, cwd = repoRoot })
	if not okBuildExec then
		print(`[Test] Failed to run BuildStandalone: {tostring(buildResultOrErr)}`)
		return false
	end

	local buildResult = buildResultOrErr
	if not buildResult.ok then
		local stdout = buildResult.stdout or ""
		local stderr = buildResult.stderr or ""
		print("[Test] BuildStandalone command failed.")
		if stdout ~= "" then
			print(`[Test] stdout: {stdout}`)
		end
		if stderr ~= "" then
			print(`[Test] stderr: {stderr}`)
		end
		return false
	end

	local okListExec, listResultOrErr = pcall(
		Process.exec,
		"lune",
		{ "run", standaloneEntryPath, "list" },
		{ capture = true, cwd = caseRoot }
	)
	if not okListExec then
		print(`[Test] Failed to run standalone list command: {tostring(listResultOrErr)}`)
		return false
	end

	local listResult = listResultOrErr
	if not listResult.ok then
		local stdout = listResult.stdout or ""
		local stderr = listResult.stderr or ""
		print("[Test] Standalone list command failed.")
		if stdout ~= "" then
			print(`[Test] stdout: {stdout}`)
		end
		if stderr ~= "" then
			print(`[Test] stderr: {stderr}`)
		end
		return false
	end

	local output = (listResult.stdout or "") .. "\n" .. (listResult.stderr or "")
	local availableCountText = output:match("%[Template%] Available templates:%s*(%d+)")
	if availableCountText == nil then
		print("[Test] Failed to read template count from standalone list output.")
		print(`[Test] output: {output}`)
		return false
	end

	local availableCount = tonumber(availableCountText)
	if availableCount == nil or availableCount <= 0 then
		print(`[Test] Standalone list returned invalid template count: {availableCountText}`)
		return false
	end

	local okCleanup = removeDirectoryRecursive(caseRoot, fileSystemUtils)
	if not okCleanup then
		return false
	end

	return true
end

local repoRoot = resolveRepoRoot(FileSystemUtils)
local testsRoot = FileSystemUtils.JoinPath(repoRoot, "tests")
local tmpRoot = FileSystemUtils.JoinPath(testsRoot, ".tmp")
if FileSystem.isDir(tmpRoot) then
	local okCleanup = removeDirectoryRecursive(tmpRoot, FileSystemUtils)
	if not okCleanup then
		Process.exit(1)
	end
end
FileSystemUtils.MakeDirectoryRecursive(tmpRoot)

local applyScriptPath = FileSystemUtils.JoinPath(testsRoot, "ApplyTemplates.luau")
if not FileSystem.isFile(applyScriptPath) then
	print(`[Error] Missing ApplyTemplates script at \"{applyScriptPath}\".`)
	Process.exit(1)
end

local initScriptPath = FileSystemUtils.JoinPath(repoRoot, "src/init.luau")
if not FileSystem.isFile(initScriptPath) then
	print(`[Error] Missing init script at "{initScriptPath}".`)
	Process.exit(1)
end

local testCases = {
	{
		Name = "base",
		Templates = {},
	},
	{
		Name = "base-disable-scripts",
		Templates = { { Name = "base", EnableScripts = false } },
	},
	{
		Name = "base-disable-scripts-and-non-luau",
		Templates = { { Name = "base", EnableScripts = false }, "non-luau" },
	},
	{
		Name = "non-luau",
		Templates = { "non-luau" },
	},
	{
		Name = "roblox-place",
		Templates = { "roblox-place" },
	},
	{
		Name = "with-bakerywave",
		Templates = { "with-bakerywave" },
	},
	{
		Name = "with-bakery-dev-handbook",
		Templates = { "with-bakery-dev-handbook" },
	},
	{
		Name = "pesde-default-packages",
		Templates = { "pesde-default-packages" },
	},
	{
		Name = "bakerywave-and-handbook",
		Templates = { "with-bakerywave", "with-bakery-dev-handbook" },
	},
	{
		Name = "bakerywave-and-pesde",
		Templates = { "with-bakerywave", "pesde-default-packages" },
	},
	{
		Name = "all-templates",
		Templates = {
			"non-luau",
			"roblox-place",
			"with-bakerywave",
			"with-bakery-dev-handbook",
			"pesde-default-packages",
		},
	},
}

local failed = 0
local okStandalone = runStandaloneTemplateDiscoveryTest(repoRoot, tmpRoot, FileSystemUtils)
if not okStandalone then
	failed += 1
end

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

local configCommandTestCases = {
	{
		Name = "config-toggle-non-luau",
		InitialTemplates = { "pesde-default-packages" },
		Input = "1\nsave\n",
		ExpectedTemplates = { "non-luau", "pesde-default-packages" },
	},
	{
		Name = "config-cancel",
		InitialTemplates = { "with-bakerywave" },
		Input = "cancel\n",
		ExpectedTemplates = { "with-bakerywave" },
	},
}

for index, case in configCommandTestCases do
	local ok = runConfigCommandTestCase(
		case.Name,
		case.InitialTemplates,
		case.Input,
		case.ExpectedTemplates,
		initScriptPath,
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
