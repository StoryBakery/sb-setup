--> 설정 파일과 서브모듈을 워크스페이스 루트에 설치하는 Lune 스크립트입니다.
--[[
	SetupConfigs
	setup_configs.toml 템플릿 목록을 워크스페이스 루트에 적용합니다.
	bakery-dev-handbook 서브모듈을 libs 경로에 유지합니다.
]]

local FileSystem = require("@lune/fs")
local Process = require("@lune/process")

local function loadModule(name: string)
	local modulePath = "./src/modules/" .. name
	local ok, moduleOrErr = pcall(require, modulePath)
	if not ok then
		print(`[Error] Failed to load module "{name}".`)
		print(tostring(moduleOrErr))
		Process.exit(1)
	end
	return moduleOrErr
end

local Config = loadModule("Config")
local FileSystemUtils = loadModule("FileSystemUtils")
local Installer = loadModule("Installer")
local ManagedBlock = loadModule("ManagedBlock")
local ParseOption = loadModule("ParseOption")
local Submodule = loadModule("Submodule")
local TomlParser = loadModule("TomlParser")

local function findDefaultProjectConfigPath(config, fileSystemUtils)
	local projectConfigFileName = config.ProjectConfigFileName
	for _, candidate in config.SourceCandidates do
		local path = fileSystemUtils.JoinPath(candidate, projectConfigFileName)
		if FileSystem.isFile(path) then
			return path
		end
	end
	return nil
end

local function initProjectConfig(config, fileSystemUtils)
	local projectConfigPath = config.ProjectConfigFileName
	if FileSystem.isFile(projectConfigPath) then
		return true, { Status = "Exists", Path = projectConfigPath }
	end

	local defaultPath = findDefaultProjectConfigPath(config, fileSystemUtils)
	if defaultPath == nil then
		return false, { Code = "MissingDefaultProjectConfig" }
	end

	local okCopy, err = pcall(function()
		fileSystemUtils.CopyFile(defaultPath, projectConfigPath)
	end)
	if not okCopy then
		return false, {
			Code = "WriteProjectConfigFailed",
			Detail = tostring(err),
		}
	end

	return true, { Status = "Created", Path = projectConfigPath }
end

local optionName = ParseOption("install")
if optionName == "init" then
	local okInit, initResult = initProjectConfig(Config, FileSystemUtils)
	if not okInit then
		if initResult.Code == "MissingDefaultProjectConfig" then
			print("[Error] Failed to locate default setup_configs.toml.")
		elseif initResult.Code == "WriteProjectConfigFailed" then
			print(`[Error] Failed to write setup_configs.toml: {initResult.Detail}`)
		else
			print("[Error] Failed to initialize setup_configs.toml.")
		end
		Process.exit(1)
	end

	if initResult.Status == "Created" then
		print(`[Init] setup_configs.toml created at "{initResult.Path}".`)
	else
		print(`[Info] setup_configs.toml already exists at "{initResult.Path}".`)
	end
	Process.exit(0)
end

local okInstall, installResult = Installer.Install(Config, FileSystemUtils, TomlParser, ManagedBlock)
if not okInstall then
	if installResult.Code == "MissingSourceRoot" then
		print("[Error] Failed to locate setup_configs source root.")
	elseif installResult.Code == "MissingProjectConfig" then
		print(`[Error] Missing setup_configs.toml at "{installResult.Path}".`)
	elseif installResult.Code == "ProjectConfigParseFailed" then
		print(`[Error] Failed to parse setup_configs.toml at line {installResult.Line}.`)
	elseif installResult.Code == "ProjectConfigReadFailed" then
		print(`[Error] Failed to read setup_configs.toml: {installResult.Detail}`)
	elseif installResult.Code == "MissingTemplates" then
		print("[Error] Templates list is empty in setup_configs.toml.")
	elseif installResult.Code == "InvalidTemplateEntry" then
		print(`[Error] Invalid template entry at index {installResult.Index} in setup_configs.toml.`)
	elseif installResult.Code == "InvalidTemplateSource" then
		print(`[Error] Invalid template source at index {installResult.Index} in setup_configs.toml.`)
	elseif installResult.Code == "InvalidTemplateOrder" then
		print(`[Error] Templates must start with "{installResult.BaseTemplateName}".`)
	elseif installResult.Code == "MissingTemplateSource" then
		print(`[Error] Template source not found for "{installResult.TemplateName}": {installResult.Source}`)
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
		print(`[Error] Template name mismatch for "{installResult.TemplateName}" (found "{installResult.ConfigName}").`)
	elseif installResult.Code == "ReadTemplateFailed" then
		print(`[Error] Failed to read template file "{installResult.Path}".`)
	elseif installResult.Code == "ReadDestinationFailed" then
		print(`[Error] Failed to read destination file "{installResult.Path}".`)
	elseif installResult.Code == "WriteDestinationFailed" then
		print(`[Error] Failed to write destination file "{installResult.Path}".`)
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

local submoduleResult = Submodule.Ensure(Config.Submodule, FileSystemUtils)
local submodulePath = Config.Submodule.Path

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
