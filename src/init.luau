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

local function resolveSourceRoot(
	candidates: { string },
	templatesRootName: string,
	fileSystemUtils
): string?
	for _, candidate in candidates do
		local templatesRoot = fileSystemUtils.JoinPath(candidate, templatesRootName)
		if FileSystem.isDir(templatesRoot) then
			return candidate
		end
	end
	return nil
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
	local srcRoot =
		resolveSourceRoot(config.SourceCandidates, config.TemplatesRootName, fileSystemUtils)
	if srcRoot ~= nil then
		table.insert(roots, fileSystemUtils.JoinPath(srcRoot, config.TemplatesRootName))
	end

	if FileSystem.isDir(config.ProjectTemplatesRootPath) then
		table.insert(roots, config.ProjectTemplatesRootPath)
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

local function initProjectConfig(config, fileSystemUtils)
	local projectConfigPath = config.ProjectConfigFileName
	if FileSystem.isFile(projectConfigPath) then
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

	return true, { Status = "Created", Path = projectConfigPath }
end

local optionName = Process.args[1] or "install"
if optionName == "init" then
	local okInit, initResult = initProjectConfig(Config, FileSystemUtils)
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
	else
		print(`[Info] bakery_project_configs.toml already exists at "{initResult.Path}".`)
	end
	Process.exit(0)
end

local okInstall, installResult =
	Installer.Install(Config, FileSystemUtils, TomlParser, ManagedBlock)
if not okInstall then
	if installResult.Code == "MissingSourceRoot" then
		print("[Error] Failed to locate setup_configs source root.")
	elseif installResult.Code == "MissingProjectConfig" then
		print(`[Error] Missing bakery_project_configs.toml at "{installResult.Path}".`)
	elseif installResult.Code == "ProjectConfigParseFailed" then
		print(`[Error] Failed to parse bakery_project_configs.toml at line {installResult.Line}.`)
	elseif installResult.Code == "ProjectConfigReadFailed" then
		print(`[Error] Failed to read bakery_project_configs.toml: {installResult.Detail}`)
	elseif installResult.Code == "MissingTemplates" then
		print("[Error] Templates list is empty in bakery_project_configs.toml.")
	elseif installResult.Code == "InvalidTemplateEntry" then
		print(
			`[Error] Invalid template entry at index {installResult.Index} in bakery_project_configs.toml.`
		)
	elseif installResult.Code == "InvalidTemplateSource" then
		print(
			`[Error] Invalid template source at index {installResult.Index} in bakery_project_configs.toml.`
		)
	elseif installResult.Code == "InvalidTemplateOrder" then
		print(`[Error] Templates must start with "{installResult.BaseTemplateName}".`)
	elseif installResult.Code == "MissingTemplateSource" then
		print(
			`[Error] Template source not found for "{installResult.TemplateName}": {installResult.Source}`
		)
	elseif installResult.Code == "DuplicateTemplateSource" then
		print(`[Error] Template "{installResult.TemplateName}" has multiple sources.`)
	elseif installResult.Code == "MissingTemplate" then
		print(`[Error] Failed to find template "{installResult.TemplateName}".`)
		local availableTemplates = installResult.AvailableTemplates or {}
		if #availableTemplates > 0 then
			print(`[Info] Available templates: {table.concat(availableTemplates, ", ")}`)
		end
	elseif installResult.Code == "MissingTemplateConfig" then
		print(`[Error] Missing template.toml at "{installResult.Path}".`)
	elseif installResult.Code == "TemplateConfigParseFailed" then
		print(`[Error] Failed to parse template.toml at line {installResult.Line}.`)
	elseif installResult.Code == "TemplateConfigReadFailed" then
		print(`[Error] Failed to read template.toml: {installResult.Detail}`)
	elseif installResult.Code == "MissingTemplateName" then
		print(`[Error] Missing Name in template.toml at "{installResult.Path}".`)
	elseif installResult.Code == "TemplateNameMismatch" then
		print(
			`[Error] Template name mismatch for "{installResult.TemplateName}" (found "{installResult.ConfigName}").`
		)
	elseif installResult.Code == "ReadTemplateFailed" then
		print(`[Error] Failed to read template file "{installResult.Path}".`)
	elseif installResult.Code == "ReadDestinationFailed" then
		print(`[Error] Failed to read destination file "{installResult.Path}".`)
	elseif installResult.Code == "WriteDestinationFailed" then
		print(`[Error] Failed to write destination file "{installResult.Path}".`)
	elseif installResult.Code == "TemplateSubmoduleReadFailed" then
		print(`[Error] Failed to read template gitmodules file "{installResult.Path}".`)
	elseif installResult.Code == "TemplateSubmoduleParseFailed" then
		local lineLabel = installResult.Line or "unknown"
		print(`[Error] Failed to parse template gitmodules file "{installResult.Path}" at line {lineLabel}.`)
	elseif installResult.Code == "InvalidTemplateSubmodule" then
		local nameLabel = installResult.SubmoduleName or "unknown"
		print(`[Error] Invalid template gitmodules entry "{nameLabel}" in "{installResult.Path}".`)
	elseif installResult.Code == "DuplicateSubmodulePath" then
		print(`[Error] Duplicate submodule path "{installResult.Path}" in templates.`)
	else
		print("[Error] Config install failed.")
	end
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
			print(`[Error] Path "{submodulePath}" already exists and cannot be used for a submodule.`)
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
