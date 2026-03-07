--[[
	템플릿 조합 테스트를 실행하는 스크립트입니다.
]]

local FileSystem = require("@lune/fs")
local Process = require("@lune/process")

local FileSystemUtils = require("../src/cores/FileSystemUtils")
local TomlParser = require("../src/cores/TomlParser")

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

local function escapeTomlString(value: string): string
	local escaped = value:gsub("\\", "\\\\")
	return escaped:gsub('"', '\\"')
end

local function normalizeTemplateEntry(entry): (boolean, { [string]: any }?, string?)
	if type(entry) == "string" then
		if entry == "" then
			return false, nil, "Template name is empty."
		end

		return true, { Name = entry }, nil
	end

	if type(entry) ~= "table" then
		return false, nil, "Template entry must be a string or table."
	end

	local name = entry.Name
	if type(name) ~= "string" or name == "" then
		return false, nil, "Template entry Name is invalid."
	end

	local normalized = { Name = name }

	local source = entry.Source
	if source ~= nil then
		if type(source) ~= "string" or source == "" then
			return false, nil, "Template entry Source is invalid."
		end
		normalized.Source = source
	end

	local enableScripts = entry.EnableScripts
	if enableScripts ~= nil then
		if type(enableScripts) ~= "boolean" then
			return false, nil, "Template entry EnableScripts is invalid."
		end
		normalized.EnableScripts = enableScripts
	end

	return true, normalized, nil
end

local function buildProjectConfigContent(templates: { [number]: any }): (boolean, string?)
	if #templates == 0 then
		return true, "Templates = []\n"
	end

	local normalizedEntries: { [number]: { [string]: any } } = {}
	local allStringEntries = true

	for _, entry in templates do
		local okNormalize, normalizedEntry, normalizeError = normalizeTemplateEntry(entry)
		if not okNormalize or normalizedEntry == nil then
			return false, normalizeError
		end

		table.insert(normalizedEntries, normalizedEntry)
		if type(entry) ~= "string" then
			allStringEntries = false
		end
	end

	if allStringEntries then
		local quotedNames: { string } = {}
		for _, entry in normalizedEntries do
			table.insert(quotedNames, `"{escapeTomlString(entry.Name)}"`)
		end
		return true, `Templates = [{table.concat(quotedNames, ", ")}]\n`
	end

	local lines: { string } = {}
	for _, entry in normalizedEntries do
		table.insert(lines, "[[Templates]]")
		table.insert(lines, `Name = "{escapeTomlString(entry.Name)}"`)

		local source = entry.Source
		if source ~= nil then
			table.insert(lines, `Source = "{escapeTomlString(source)}"`)
		end

		local enableScripts = entry.EnableScripts
		if type(enableScripts) == "boolean" then
			local value = if enableScripts then "true" else "false"
			table.insert(lines, `EnableScripts = {value}`)
		end

		table.insert(lines, "")
	end

	return true, table.concat(lines, "\n") .. "\n"
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

local function readConfiguredTemplates(configPath: string): (boolean, { [number]: any }?)
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

	return true, templates
end

local function readConfiguredTemplateNames(configPath: string): (boolean, { string }?)
	local okRead, templates = readConfiguredTemplates(configPath)
	if not okRead or templates == nil then
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

local function buildTemplateTableEntryByName(
	templates: { [number]: any }
): { [string]: { [string]: any } }
	local tableEntryByName: { [string]: { [string]: any } } = {}

	for _, entry in templates do
		if type(entry) == "table" then
			local name = entry.Name
			if type(name) == "string" and name ~= "" then
				if tableEntryByName[name] == nil then
					tableEntryByName[name] = entry
				end
			end
		end
	end

	return tableEntryByName
end

local function isAbsolutePath(path: string): boolean
	if path:sub(1, 1) == "/" then
		return true
	end
	if path:match("^[A-Za-z]:[\\/]") then
		return true
	end
	return false
end

local function ensureTemplateSourcesForConfigCase(
	initialTemplates: { [number]: any },
	caseRoot: string,
	fileSystemUtils
): boolean
	for _, entry in initialTemplates do
		if type(entry) == "table" then
			local name = entry.Name
			local source = entry.Source
			if type(name) == "string" and name ~= "" and type(source) == "string" and source ~= "" then
				local sourceRoot = source
				if not isAbsolutePath(sourceRoot) then
					sourceRoot = fileSystemUtils.JoinPath(caseRoot, sourceRoot)
				end

				fileSystemUtils.MakeDirectoryRecursive(sourceRoot)
				local templateConfigPath = fileSystemUtils.JoinPath(sourceRoot, "template.toml")
				local templateConfigContent = table.concat({
					`Name = "{escapeTomlString(name)}"`,
					'Description = "Config command test template."',
					"",
				}, "\n")

				local okWrite, writeErr = pcall(function()
					FileSystem.writeFile(templateConfigPath, templateConfigContent)
				end)
				if not okWrite then
					print(
						`[Error] Failed to create config test template "{templateConfigPath}": {tostring(writeErr)}`
					)
					return false
				end
			end
		end
	end

	return true
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
		{ "run", applyScriptPath, "--worker" },
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
	expectedSourceByTemplateName: { [string]: string }?,
	shouldRunInstall: boolean,
	useNoInstallOption: boolean?,
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

	if expectedSourceByTemplateName ~= nil then
		local okEnsureSources =
			ensureTemplateSourcesForConfigCase(initialTemplates, caseRoot, fileSystemUtils)
		if not okEnsureSources then
			return false
		end
	end

	print(`[Test] Running "{caseName}" config command test.`)

	local commandArgs = { "run", initScriptPath, "config" }
	if useNoInstallOption == true then
		table.insert(commandArgs, "--no-install")
	end

	local okExec, resultOrErr = pcall(
		Process.exec,
		"lune",
		commandArgs,
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

	if expectedSourceByTemplateName ~= nil then
		local okReadConfigured, configuredEntries = readConfiguredTemplates(configPath)
		if not okReadConfigured or configuredEntries == nil then
			return false
		end

		local tableEntryByName = buildTemplateTableEntryByName(configuredEntries)
		for templateName, expectedSource in expectedSourceByTemplateName do
			local templateEntry = tableEntryByName[templateName]
			if templateEntry == nil then
				print(`[Test] Config case "{caseName}" missing table entry for "{templateName}".`)
				return false
			end

			local actualSource = templateEntry.Source
			if actualSource ~= expectedSource then
				print(`[Test] Config case "{caseName}" source mismatch for "{templateName}".`)
				print(`[Test] expected: {expectedSource}`)
				print(`[Test] actual: {tostring(actualSource)}`)
				return false
			end
		end
	end

	local gitignorePath = fileSystemUtils.JoinPath(caseRoot, ".gitignore")
	if shouldRunInstall then
		if not FileSystem.isFile(gitignorePath) then
			print(`[Test] Config case "{caseName}" expected install to run.`)
			return false
		end
	else
		if FileSystem.isFile(gitignorePath) then
			print(`[Test] Config case "{caseName}" expected install to be skipped.`)
			return false
		end
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

local function listOptionalTemplatesInRepo(
	repoRoot: string,
	fileSystemUtils
): { string }
	local templatesRoot = fileSystemUtils.JoinPath(repoRoot, "src/templates")
	if not FileSystem.isDir(templatesRoot) then
		return {}
	end

	local okRead, entries = pcall(FileSystem.readDir, templatesRoot)
	if not okRead or entries == nil then
		return {}
	end

	local optionalTemplates: { string } = {}
	for _, entry in entries do
		if entry ~= "base" then
			local templatePath = fileSystemUtils.JoinPath(templatesRoot, entry)
			local templateConfigPath = fileSystemUtils.JoinPath(templatePath, "template.toml")
			if FileSystem.isDir(templatePath) and FileSystem.isFile(templateConfigPath) then
				table.insert(optionalTemplates, entry)
			end
		end
	end

	table.sort(optionalTemplates)
	return optionalTemplates
end

local function buildConfigOptionalTemplateOrder(
	repoRoot: string,
	optionalTemplates: { string },
	fileSystemUtils,
	tomlParser
): { string }
	local optionalTemplateNameSet: { [string]: boolean } = {}
	for _, name in optionalTemplates do
		optionalTemplateNameSet[name] = true
	end

	local parentByName: { [string]: string } = {}
	local childrenByName: { [string]: { string } } = {}

	for _, name in optionalTemplates do
		local templateConfigPath =
			fileSystemUtils.JoinPath(repoRoot, `src/templates/{name}/template.toml`)
		local okRead, templateConfigOrErr = tomlParser.ReadFile(templateConfigPath)
		if okRead and type(templateConfigOrErr) == "table" then
			local parentName = templateConfigOrErr.Parent
			if type(parentName) == "string" and parentName ~= "" then
				if parentName ~= name and optionalTemplateNameSet[parentName] then
					parentByName[name] = parentName
					if childrenByName[parentName] == nil then
						childrenByName[parentName] = {}
					end
					table.insert(childrenByName[parentName], name)
				end
			end
		end
	end

	local orderedOptionalTemplates: { string } = {}
	local emittedNameSet: { [string]: boolean } = {}

	local function appendTemplate(name: string)
		if emittedNameSet[name] then
			return
		end

		emittedNameSet[name] = true
		table.insert(orderedOptionalTemplates, name)

		local children = childrenByName[name]
		if type(children) == "table" then
			for _, childName in children do
				appendTemplate(childName)
			end
		end
	end

	for _, name in optionalTemplates do
		if parentByName[name] == nil then
			appendTemplate(name)
		end
	end

	for _, name in optionalTemplates do
		if not emittedNameSet[name] then
			appendTemplate(name)
		end
	end

	return orderedOptionalTemplates
end

local function findTemplateIndex(templateNames: { string }, targetName: string): number?
	for index, templateName in templateNames do
		if templateName == targetName then
			return index
		end
	end

	return nil
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

local optionalTemplatesInRepo = listOptionalTemplatesInRepo(repoRoot, FileSystemUtils)
local configOptionalTemplatesInRepo = buildConfigOptionalTemplateOrder(
	repoRoot,
	optionalTemplatesInRepo,
	FileSystemUtils,
	TomlParser
)

local testCases = {
	{
		Name = "base",
		Templates = {},
	},
	{
		Name = "base-disable-scripts",
		Templates = { { Name = "base", EnableScripts = false } },
	},
}

for _, templateName in optionalTemplatesInRepo do
	table.insert(testCases, {
		Name = `only-{templateName}`,
		Templates = { templateName },
	})
end

if #optionalTemplatesInRepo >= 2 then
	table.insert(testCases, {
		Name = "first-two-optional-templates",
		Templates = {
			optionalTemplatesInRepo[1],
			optionalTemplatesInRepo[2],
		},
	})
end

if #optionalTemplatesInRepo > 0 then
	local allOptionalTemplates: { string } = {}
	for _, templateName in optionalTemplatesInRepo do
		table.insert(allOptionalTemplates, templateName)
	end

	table.insert(testCases, {
		Name = "all-optional-templates",
		Templates = allOptionalTemplates,
	})
end

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

local configCommandTestCases = {}

local firstOptionalTemplate = configOptionalTemplatesInRepo[1]
if firstOptionalTemplate ~= nil then
	table.insert(configCommandTestCases, {
		Name = "config-toggle-first-optional-template",
		InitialTemplates = {},
		Input = "1\nsave\n",
		ExpectedTemplates = { firstOptionalTemplate },
		ExpectedSourceByTemplateName = nil,
		ShouldRunInstall = true,
		UseNoInstallOption = nil,
	})

	table.insert(configCommandTestCases, {
		Name = "config-cancel",
		InitialTemplates = { firstOptionalTemplate },
		Input = "cancel\n",
		ExpectedTemplates = { firstOptionalTemplate },
		ExpectedSourceByTemplateName = nil,
		ShouldRunInstall = false,
		UseNoInstallOption = nil,
	})

	table.insert(configCommandTestCases, {
		Name = "config-save-no-install-option",
		InitialTemplates = {},
		Input = "1\nsave\n",
		ExpectedTemplates = { firstOptionalTemplate },
		ExpectedSourceByTemplateName = nil,
		ShouldRunInstall = false,
		UseNoInstallOption = true,
	})
end

local bakerywaveIndex = findTemplateIndex(configOptionalTemplatesInRepo, "bakerywave")
local bakerywaveParentIndex = findTemplateIndex(configOptionalTemplatesInRepo, "markdown-style")
if bakerywaveIndex ~= nil and bakerywaveParentIndex ~= nil then
	table.insert(configCommandTestCases, {
		Name = "config-toggle-child-enables-parent",
		InitialTemplates = {},
		Input = tostring(bakerywaveIndex) .. "\nsave\n",
		ExpectedTemplates = { "markdown-style", "bakerywave" },
		ExpectedSourceByTemplateName = nil,
		ShouldRunInstall = true,
		UseNoInstallOption = nil,
	})

	table.insert(configCommandTestCases, {
		Name = "config-toggle-child-then-disable-parent",
		InitialTemplates = {},
		Input = tostring(bakerywaveIndex) .. "\n" .. tostring(bakerywaveParentIndex) .. "\nsave\n",
		ExpectedTemplates = { "bakerywave" },
		ExpectedSourceByTemplateName = nil,
		ShouldRunInstall = true,
		UseNoInstallOption = nil,
	})
end

local customTemplateName = "custom-template"
local customTemplateSource = "./templates/custom-template"
local initialTemplatesWithCustom = { { Name = customTemplateName, Source = customTemplateSource } }
if firstOptionalTemplate ~= nil then
	table.insert(initialTemplatesWithCustom, 1, firstOptionalTemplate)
end

local expectedTemplatesWithCustom = { customTemplateName }
if firstOptionalTemplate ~= nil then
	table.insert(expectedTemplatesWithCustom, 1, firstOptionalTemplate)
end

table.insert(configCommandTestCases, {
	Name = "config-preserve-custom-template-source",
	InitialTemplates = initialTemplatesWithCustom,
	Input = "save\n",
	ExpectedTemplates = expectedTemplatesWithCustom,
	ExpectedSourceByTemplateName = {
		["custom-template"] = "./templates/custom-template",
	},
	ShouldRunInstall = true,
	UseNoInstallOption = nil,
})

local expectedTemplatesWithoutCustom: { string } = {}
if firstOptionalTemplate ~= nil then
	table.insert(expectedTemplatesWithoutCustom, firstOptionalTemplate)
end

local customTemplateToggleIndex = #configOptionalTemplatesInRepo + 1
table.insert(configCommandTestCases, {
	Name = "config-toggle-custom-template-off",
	InitialTemplates = initialTemplatesWithCustom,
	Input = tostring(customTemplateToggleIndex) .. "\nsave\n",
	ExpectedTemplates = expectedTemplatesWithoutCustom,
	ExpectedSourceByTemplateName = nil,
	ShouldRunInstall = true,
	UseNoInstallOption = nil,
})

for index, case in configCommandTestCases do
	local ok = runConfigCommandTestCase(
		case.Name,
		case.InitialTemplates,
		case.Input,
		case.ExpectedTemplates,
		case.ExpectedSourceByTemplateName,
		case.ShouldRunInstall,
		case.UseNoInstallOption,
		initScriptPath,
		tmpRoot,
		index,
		FileSystemUtils
	)
	if not ok then
		failed += 1
	end
end

local okCleanupTmp = removeDirectoryRecursive(tmpRoot, FileSystemUtils)
if not okCleanupTmp then
	Process.exit(1)
end

if failed > 0 then
	print(`[Test] Failed cases: {failed}`)
	Process.exit(1)
end

print("[Test] All template cases passed.")
Process.exit(0)
