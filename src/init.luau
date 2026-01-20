--> 설정 파일과 서브모듈을 워크스페이스 루트에 설치하는 Lune 스크립트입니다.
--[[
	SetupConfigs
	bakery_project_configs.toml 템플릿 목록을 워크스페이스 루트에 적용합니다.
	템플릿에서 정의한 서브모듈을 워크스페이스 루트에 설치합니다.
]]

local FileSystem = require("@lune/fs")
local Process = require("@lune/process")
local Stdio = require("@lune/stdio")

local Config = require("@self/modules/Config")
local FileSystemUtils = require("@self/modules/FileSystemUtils")
local Installer = require("@self/modules/Installer")
local ManagedBlock = require("@self/modules/ManagedBlock")
local Submodule = require("@self/modules/Submodule")
local TomlParser = require("@self/modules/TomlParser")

local function printUsage()
	print("Usage: lune run src/init [install|init] [options]")
	print("")
	print("Commands:")
	print("  install   Apply templates and submodules (default).")
	print("  init      Create bakery_project_configs.toml.")
	print("")
	print("Options:")
	print("  -h, --help    Show this help.")
	print("  --force       Overwrite bakery_project_configs.toml when using init.")
end

local function parseArgs(args: { string })
	local commandName = nil
	local force = false
	local help = false
	local errors: { string } = {}

	for _, arg in args do
		if arg == "-h" or arg == "--help" then
			help = true
		elseif arg == "--force" then
			force = true
		elseif arg == "install" or arg == "init" then
			if commandName ~= nil and commandName ~= arg then
				table.insert(errors, `Conflicting command "{arg}".`)
			else
				commandName = arg
			end
		elseif arg:sub(1, 1) == "-" then
			table.insert(errors, `Unknown option "{arg}".`)
		else
			table.insert(errors, `Unknown argument "{arg}".`)
		end
	end

	return {
		Command = commandName or "install",
		Force = force,
		Help = help,
		Errors = errors,
	}
end

local function normalizeSourcePath(source: string): string
	if source:sub(1, 1) == "@" then
		return source:sub(2)
	end
	return source
end

local function resolveConfigRoot(configPath: string, fileSystemUtils): string
	local configDir = fileSystemUtils.GetDirectoryName(configPath)
	if configDir == "" then
		return "."
	end
	return configDir
end

local function findTemplatesRoot(
	startDir: string,
	templatesRootName: string,
	fileSystemUtils
): string?
	local current = startDir
	while current ~= "" do
		local candidate = fileSystemUtils.JoinPath(current, templatesRootName)
		if FileSystem.isDir(candidate) then
			return candidate
		end
		local parent = fileSystemUtils.GetDirectoryName(current)
		if parent == "" or parent == current then
			break
		end
		current = parent
	end
	return nil
end

local function resolvePackageTemplatesRoot(templatesRootName: string, fileSystemUtils): string?
	local source = debug.info(1, "s")
	if source == nil or source == "" then
		return nil
	end
	local scriptPath = normalizeSourcePath(source)
	local scriptDir = fileSystemUtils.GetDirectoryName(scriptPath)
	if scriptDir == "" then
		return nil
	end
	return findTemplatesRoot(scriptDir, templatesRootName, fileSystemUtils)
end

local function resolveProjectTemplatesRoot(
	configPath: string,
	templatesRootName: string,
	fileSystemUtils
): string
	local configRoot = resolveConfigRoot(configPath, fileSystemUtils)
	return fileSystemUtils.JoinPath(configRoot, templatesRootName)
end

local function listTemplateNames(templateRoots: { string }, fileSystemUtils): { string }
	local templateNameSet: { [string]: boolean } = {}
	for _, templatesRoot in templateRoots do
		if templatesRoot ~= "" and FileSystem.isDir(templatesRoot) then
			local ok, entries = pcall(FileSystem.readDir, templatesRoot)
			if ok and entries ~= nil then
				for _, entry in entries do
					local path = fileSystemUtils.JoinPath(templatesRoot, entry)
					if FileSystem.isDir(path) then
						templateNameSet[entry] = true
					end
				end
			end
		end
	end

	local templateNames: { string } = {}
	for name in templateNameSet do
		table.insert(templateNames, name)
	end

	table.sort(templateNames)
	return templateNames
end

local function collectTemplateOptions(config, fileSystemUtils): { string }
	local roots: { string } = {}

	local packageTemplatesRoot =
		resolvePackageTemplatesRoot(config.TemplatesRootName, fileSystemUtils)
	if packageTemplatesRoot ~= nil then
		table.insert(roots, packageTemplatesRoot)
	end

	local projectTemplatesRoot = resolveProjectTemplatesRoot(
		config.ProjectConfigFileName,
		config.TemplatesRootName,
		fileSystemUtils
	)
	if FileSystem.isDir(projectTemplatesRoot) then
		table.insert(roots, projectTemplatesRoot)
	end

	return listTemplateNames(roots, fileSystemUtils)
end

local function filterOptionalTemplates(
	templateNames: { string },
	baseTemplateName: string
): { string }
	local optionalTemplates: { string } = {}
	for _, name in templateNames do
		if name ~= baseTemplateName then
			table.insert(optionalTemplates, name)
		end
	end
	return optionalTemplates
end

local function selectOptionalTemplates(optionalTemplates: { string }): { string }
	if #optionalTemplates == 0 then
		return {}
	end

	print("[Init] Base template is always included.")
	print("[Init] Optional templates:")
	for index, name in optionalTemplates do
		print(`[Init] {index}) {name}`)
	end
	print("[Init] Enter numbers separated by commas (empty for base only):")

	local input = Stdio.readLine()
	if input == nil or input == "" then
		return {}
	end

	local selectedIndexSet: { [number]: boolean } = {}
	for token in input:gmatch("[^,%s]+") do
		local index = tonumber(token)
		if index ~= nil and optionalTemplates[index] ~= nil then
			selectedIndexSet[index] = true
		end
	end

	local selected: { string } = {}
	for index, name in optionalTemplates do
		if selectedIndexSet[index] then
			table.insert(selected, name)
		end
	end

	return selected
end

local function buildProjectConfigContent(templates: { string }): string
	local quoted: { string } = {}
	for _, name in templates do
		table.insert(quoted, `"{name}"`)
	end
	return `Templates = [{table.concat(quoted, ", ")}]\n`
end

local function writeProjectConfig(
	path: string,
	content: string,
	fileSystemUtils
): (boolean, string?)
	fileSystemUtils.EnsureParentDirectory(path)
	local okWrite, err = pcall(function()
		FileSystem.writeFile(path, content)
	end)
	if not okWrite then
		return false, tostring(err)
	end
	return true, nil
end

local function initProjectConfig(config, fileSystemUtils, forceInit: boolean)
	local projectConfigPath = config.ProjectConfigFileName
	local hadExisting = FileSystem.isFile(projectConfigPath)
	if hadExisting and not forceInit then
		return true, { Status = "Exists", Path = projectConfigPath }
	end

	local templateNames = collectTemplateOptions(config, fileSystemUtils)
	local optionalTemplates = filterOptionalTemplates(templateNames, config.BaseTemplateName)
	local selectedTemplates = selectOptionalTemplates(optionalTemplates)

	local templates: { string } = { config.BaseTemplateName }
	for _, name in selectedTemplates do
		table.insert(templates, name)
	end

	local content = buildProjectConfigContent(templates)
	local okWrite, err = writeProjectConfig(projectConfigPath, content, fileSystemUtils)
	if not okWrite then
		return false, {
			Code = "WriteProjectConfigFailed",
			Detail = err or "",
		}
	end

	local status = if hadExisting then "Overwritten" else "Created"
	return true, { Status = status, Path = projectConfigPath }
end

local options = parseArgs(Process.args)
if #options.Errors > 0 then
	for _, message in options.Errors do
		print(`[Error] {message}`)
	end
	printUsage()
	Process.exit(1)
end

if options.Help then
	printUsage()
	Process.exit(0)
end

local optionName = options.Command
if optionName == "init" then
	local okInit, initResult = initProjectConfig(Config, FileSystemUtils, options.Force)
	if not okInit then
		if initResult.Code == "WriteProjectConfigFailed" then
			print(`[Error] Failed to write bakery_project_configs.toml: {initResult.Detail}`)
		else
			print("[Error] Failed to initialize bakery_project_configs.toml.")
		end
		Process.exit(1)
	end

	if initResult.Status == "Created" then
		print(`[Init] bakery_project_configs.toml created at "{initResult.Path}".`)
	elseif initResult.Status == "Overwritten" then
		print(`[Init] bakery_project_configs.toml overwritten at "{initResult.Path}".`)
	else
		print(`[Info] bakery_project_configs.toml already exists at "{initResult.Path}".`)
	end
	Process.exit(0)
end

local INSTALL_ERROR_HANDLERS = {
	MissingProjectConfig = function(err)
		print(`[Error] Missing bakery_project_configs.toml at "{err.Path}".`)
	end,
	ProjectConfigParseFailed = function(err)
		local pathLabel = err.Path or "bakery_project_configs.toml"
		print(`[Error] Failed to parse "{pathLabel}" at line {err.Line}.`)
	end,
	ProjectConfigReadFailed = function(err)
		local detail = err.Detail or ""
		print(`[Error] Failed to read bakery_project_configs.toml: {detail}`)
	end,
	MissingTemplates = function(err)
		local pathLabel = err.Path or "bakery_project_configs.toml"
		print(`[Error] Templates list is empty in "{pathLabel}".`)
	end,
	InvalidTemplateEntry = function(err)
		local pathLabel = err.Path or "bakery_project_configs.toml"
		print(`[Error] Invalid template entry at index {err.Index} in "{pathLabel}".`)
	end,
	InvalidTemplateSource = function(err)
		local pathLabel = err.Path or "bakery_project_configs.toml"
		print(`[Error] Invalid template source at index {err.Index} in "{pathLabel}".`)
	end,
	InvalidTemplateOrder = function(err)
		print(`[Error] Templates must start with "{err.BaseTemplateName}".`)
	end,
	MissingTemplateSource = function(err)
		print(
			`[Error] Template source not found for "{err.TemplateName}": {err.Source}`
		)
	end,
	DuplicateTemplateSource = function(err)
		print(`[Error] Template "{err.TemplateName}" has multiple sources.`)
	end,
	MissingTemplate = function(err)
		print(`[Error] Failed to find template "{err.TemplateName}".`)
		local availableTemplates = err.AvailableTemplates or {}
		if #availableTemplates > 0 then
			print(`[Info] Available templates: {table.concat(availableTemplates, ", ")}`)
		end
		local templateRoots = err.TemplateRoots or {}
		if #templateRoots > 0 then
			print(`[Info] Template roots: {table.concat(templateRoots, ", ")}`)
		end
	end,
	MissingTemplateConfig = function(err)
		print(`[Error] Missing template.toml at "{err.Path}".`)
	end,
	TemplateConfigParseFailed = function(err)
		print(`[Error] Failed to parse template.toml at line {err.Line}.`)
	end,
	TemplateConfigReadFailed = function(err)
		print(`[Error] Failed to read template.toml: {err.Detail}`)
	end,
	MissingTemplateName = function(err)
		print(`[Error] Missing Name in template.toml at "{err.Path}".`)
	end,
	TemplateNameMismatch = function(err)
		print(
			`[Error] Template name mismatch for "{err.TemplateName}" (found "{err.ConfigName}").`
		)
	end,
	ReadTemplateFailed = function(err)
		print(`[Error] Failed to read template file "{err.Path}".`)
	end,
	ReadDestinationFailed = function(err)
		print(`[Error] Failed to read destination file "{err.Path}".`)
	end,
	WriteDestinationFailed = function(err)
		print(`[Error] Failed to write destination file "{err.Path}".`)
	end,
	TemplateSubmoduleReadFailed = function(err)
		print(`[Error] Failed to read template gitmodules file "{err.Path}".`)
	end,
	TemplateSubmoduleParseFailed = function(err)
		local lineLabel = err.Line or "unknown"
		local lineText = err.LineText
		local pathLabel = err.Path or "template.gitmodules"
		if lineText ~= nil and lineText ~= "" then
			print(
				`[Error] Failed to parse template gitmodules file "{pathLabel}" at line {lineLabel}: {lineText}`
			)
		else
			print(
				`[Error] Failed to parse template gitmodules file "{pathLabel}" at line {lineLabel}.`
			)
		end
	end,
	InvalidTemplateSubmodule = function(err)
		local nameLabel = err.SubmoduleName or "unknown"
		print(`[Error] Invalid template gitmodules entry "{nameLabel}" in "{err.Path}".`)
	end,
	DuplicateSubmodulePath = function(err)
		print(`[Error] Duplicate submodule path "{err.Path}" in templates.`)
	end,
}

local function printInstallError(installError)
	local handler = INSTALL_ERROR_HANDLERS[installError.Code]
	if handler ~= nil then
		handler(installError)
		return
	end

	local codeLabel = installError.Code or "Unknown"
	print(`[Error] Config install failed ({codeLabel}).`)
end

local okInstall, installResult =
	Installer.Install(Config, FileSystemUtils, TomlParser, ManagedBlock)
if not okInstall then
	printInstallError(installResult)
	Process.exit(1)
end

local templateNames = installResult.TemplateNames or {}
local templateLabel = "none"
if #templateNames > 0 then
	templateLabel = table.concat(templateNames, ", ")
end
print(`[Install] Templates applied: {templateLabel} (files {installResult.TotalCount})`)

local submodules = installResult.Submodules or {}
for _, submodule in submodules do
	local submodulePath = submodule.Path
	local submoduleResult = Submodule.Ensure(submodule, FileSystemUtils)

	if not submoduleResult.IsOk then
		if submoduleResult.Status == "PathConflict" then
			print(
				`[Error] Path "{submodulePath}" already exists and cannot be used for a submodule.`
			)
		elseif submoduleResult.Status == "NotGitRepo" then
			print(`[Error] Path "{submodulePath}" is not a Git repository.`)
		elseif submoduleResult.Status == "GitFailed" then
			local action = submoduleResult.Action or "Git"
			local detail = submoduleResult.Detail or ""
			print(`[Error] Git command failed ({action}): {detail}`)
		else
			print(`[Error] Failed to process submodule "{submodulePath}".`)
		end
		Process.exit(1)
	end

	if submoduleResult.Status == "Skipped" then
		if submoduleResult.Reason == "MissingGit" then
			print("[Info] Git is not available. Skipping submodule setup.")
		elseif submoduleResult.Reason == "NotGitRepo" then
			print("[Info] Not a Git repository. Skipping submodule setup.")
		else
			print("[Info] Skipping submodule setup.")
		end
	elseif submoduleResult.Status == "Added" then
		print(`[Submodule] "{submodulePath}" added`)
	elseif submoduleResult.Status == "Updated" then
		print(`[Submodule] "{submodulePath}" updated`)
	elseif submoduleResult.Status == "Ok" then
		print(`[Submodule] "{submodulePath}" is up to date`)
	end
end
