--> 설정 파일과 서브모듈을 워크스페이스 루트에 설치하는 Lune 스크립트입니다.
--[[
	SetupConfigs
	sb_setup_configs.toml 템플릿 목록을 워크스페이스 루트에 적용합니다.
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
local TemplateRoots = require("@self/modules/TemplateRoots")
local TomlParser = require("@self/modules/TomlParser")

local function printGlobalUsage()
	print("Usage: sb-setup <command> [options]")
	print("   or: lune run src/init <command> [options]")
	print("")
	print("Commands:")
	print("  install   Apply templates and submodules.")
	print("  init      Create sb_setup_configs.toml.")
	print("  config    Interactively update sb_setup_configs.toml.")
	print("  list      Show available templates and descriptions.")
	print("")
	print("Global options:")
	print("  -h, --help    Show help.")
	print("")
	print('Run "sb-setup <command> --help" for command details.')
end

local function printInstallUsage()
	print("Usage: sb-setup install")
	print("   or: lune run src/init install")
	print("")
	print("Apply templates, submodules, pesde packages, and setup scripts.")
end

local function printInitUsage()
	print("Usage: sb-setup init [--force]")
	print("   or: lune run src/init init [--force]")
	print("")
	print("Create sb_setup_configs.toml with interactive template selection.")
	print("")
	print("Options:")
	print("  --force    Overwrite existing sb_setup_configs.toml.")
end

local function printConfigUsage()
	print("Usage: sb-setup config [--no-install]")
	print("   or: lune run src/init config [--no-install]")
	print("")
	print("Interactively edit templates in sb_setup_configs.toml.")
	print("By default, install runs automatically after save.")
	print("")
	print("Options:")
	print("  --no-install    Skip automatic install after save.")
end

local function printListUsage()
	print("Usage: sb-setup list")
	print("   or: lune run src/init list")
	print("")
	print("Show available templates and descriptions.")
end

local function printUsageForCommand(commandName: string?)
	if commandName == "install" then
		printInstallUsage()
	elseif commandName == "init" then
		printInitUsage()
	elseif commandName == "config" then
		printConfigUsage()
	elseif commandName == "list" then
		printListUsage()
	else
		printGlobalUsage()
	end
end

local function normalizeCommandName(commandName: string): string?
	if commandName == "templates" then
		return "list"
	end

	if commandName == "configure" then
		return "config"
	end

	if
		commandName == "install"
		or commandName == "init"
		or commandName == "config"
		or commandName == "list"
	then
		return commandName
	end

	return nil
end

local function parseArgs(args: { string })
	local commandName = nil
	local force = false
	local noInstall = false
	local help = false
	local errors: { string } = {}

	for _, arg in args do
		local normalizedCommand = normalizeCommandName(arg)

		if arg == "-h" or arg == "--help" then
			help = true
		elseif arg == "--force" then
			force = true
		elseif arg == "--no-install" then
			noInstall = true
		elseif normalizedCommand ~= nil then
			if commandName ~= nil and commandName ~= normalizedCommand then
				table.insert(errors, `Conflicting command "{arg}".`)
			else
				commandName = normalizedCommand
			end
		elseif arg:sub(1, 1) == "-" then
			table.insert(errors, `Unknown option "{arg}".`)
		else
			table.insert(errors, `Unknown argument "{arg}".`)
		end
	end

	if force and commandName ~= "init" then
		table.insert(errors, 'Option "--force" is only available for init.')
	end
	if noInstall and commandName ~= "config" then
		table.insert(errors, 'Option "--no-install" is only available for config.')
	end

	return {
		Command = commandName,
		Force = force,
		NoInstall = noInstall,
		Help = help,
		Errors = errors,
	}
end

local function collectTemplateOptions(config, fileSystemUtils): { string }
	local roots: { string } = {}
	local configRoot =
		TemplateRoots.ResolveConfigRoot(config.ProjectConfigFileName, fileSystemUtils)

	local packageTemplatesRoot = TemplateRoots.ResolvePackageTemplatesRoot(
		config.TemplatesRootName,
		configRoot,
		fileSystemUtils
	)
	if packageTemplatesRoot ~= nil then
		table.insert(roots, packageTemplatesRoot)
	end

	local projectTemplatesRoot = TemplateRoots.ResolveProjectTemplatesRoot(
		configRoot,
		config.TemplatesRootName,
		fileSystemUtils
	)
	if FileSystem.isDir(projectTemplatesRoot) then
		table.insert(roots, projectTemplatesRoot)
	end

	return TemplateRoots.ListTemplateNames(roots, fileSystemUtils, config.TemplateConfigFileName)
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

local function buildSelectedOptionalTemplates(
	optionalTemplates: { string },
	selectedNameSet: { [string]: boolean }
): { string }
	local selected: { string } = {}
	for _, name in optionalTemplates do
		if selectedNameSet[name] then
			table.insert(selected, name)
		end
	end
	return selected
end

local function formatTemplateNamesForPrint(templateNames: { string }): string
	if #templateNames == 0 then
		return "(none)"
	end

	return table.concat(templateNames, ", ")
end

local function printCurrentOptionalTemplateActivation(
	optionalTemplates: { string },
	selectedNameSet: { [string]: boolean }
)
	local enabledTemplates: { string } = {}
	local disabledTemplates: { string } = {}

	for _, name in optionalTemplates do
		if selectedNameSet[name] then
			table.insert(enabledTemplates, name)
		else
			table.insert(disabledTemplates, name)
		end
	end

	print(`[Config] Current enabled templates: {formatTemplateNamesForPrint(enabledTemplates)}`)
	print(`[Config] Current disabled templates: {formatTemplateNamesForPrint(disabledTemplates)}`)
end

local function buildSelectedOptionalNameSet(
	optionalTemplates: { string },
	currentTemplateNameSet: { [string]: boolean }?
): { [string]: boolean }
	local selectedNameSet: { [string]: boolean } = {}
	if currentTemplateNameSet == nil then
		return selectedNameSet
	end

	for _, name in optionalTemplates do
		if currentTemplateNameSet[name] then
			selectedNameSet[name] = true
		end
	end
	return selectedNameSet
end

local function selectOptionalTemplatesFromLineInput(
	optionalTemplates: { string },
	currentTemplateNameSet: { [string]: boolean }?
): (boolean, { string }?)
	local selectedNameSet = buildSelectedOptionalNameSet(optionalTemplates, currentTemplateNameSet)

	while true do
		printCurrentOptionalTemplateActivation(optionalTemplates, selectedNameSet)
		print("[Config] Templates:")
		for index, name in optionalTemplates do
			local statusLabel = if selectedNameSet[name] then "x" else " "
			print(`[Config] {index}) [{statusLabel}] {name}`)
		end
		print('[Config] Enter numbers to toggle, "save" to apply, or "cancel" to cancel:')

		local input = Stdio.readLine()
		if input == nil then
			return false, nil
		end

		local trimmedInput = input:match("^%s*(.-)%s*$")
		local normalizedInput = trimmedInput:lower()
		if normalizedInput == "save" then
			return true, buildSelectedOptionalTemplates(optionalTemplates, selectedNameSet)
		end
		if normalizedInput == "cancel" then
			return false, nil
		end

		for token in trimmedInput:gmatch("[^,%s]+") do
			local index = tonumber(token)
			if index ~= nil then
				local name = optionalTemplates[index]
				if name ~= nil then
					selectedNameSet[name] = not selectedNameSet[name]
				end
			end
		end
	end
end

local function selectOptionalTemplatesWithSelectPrompt(
	optionalTemplates: { string },
	selectedNameSet: { [string]: boolean }
): (boolean, { string }?, string?)
	local lastIndex = 1

	while true do
		local choices: { string } = {}
		for _, name in optionalTemplates do
			local statusLabel = if selectedNameSet[name] then "[x]" else "[ ]"
			table.insert(choices, `{statusLabel} {name}`)
		end
		table.insert(choices, "[Save]")
		table.insert(choices, "[Cancel]")

		local okPrompt, indexOrErr = pcall(function()
			return Stdio.prompt(
				"select",
				"[Config] Move cursor and press Enter to toggle. Select Save to apply.",
				choices,
				lastIndex
			)
		end)
		if not okPrompt then
			local detail = tostring(indexOrErr):lower()
			if detail:find("interrupt", 1, true) or detail:find("cancel", 1, true) then
				return false, nil, "Cancelled"
			end
			if detail:find("argument", 1, true) or detail:find("parameter", 1, true) then
				okPrompt, indexOrErr = pcall(function()
					return Stdio.prompt(
						"select",
						"[Config] Move cursor and press Enter to toggle. Select Save to apply.",
						choices
					)
				end)
			end

			if not okPrompt then
				return false, nil, "Fallback"
			end
		end

		local index = indexOrErr
		if index == nil then
			return false, nil, "Cancelled"
		end

		lastIndex = index

		local saveIndex = #optionalTemplates + 1
		local cancelIndex = #optionalTemplates + 2
		if index == saveIndex then
			return true, buildSelectedOptionalTemplates(optionalTemplates, selectedNameSet), nil
		end
		if index == cancelIndex then
			return false, nil, "Cancelled"
		end

		local name = optionalTemplates[index]
		if name ~= nil then
			selectedNameSet[name] = not selectedNameSet[name]
		end
	end
end

local function selectOptionalTemplatesWithPrompt(
	optionalTemplates: { string },
	currentTemplateNameSet: { [string]: boolean }?
): (boolean, { string }?, string?)
	local selectedNameSet = buildSelectedOptionalNameSet(optionalTemplates, currentTemplateNameSet)
	return selectOptionalTemplatesWithSelectPrompt(optionalTemplates, selectedNameSet)
end

local function selectOptionalTemplates(
	optionalTemplates: { string },
	currentTemplateNameSet: { [string]: boolean }?
): (boolean, { string }?)
	if #optionalTemplates == 0 then
		return true, {}
	end

	local okPrompt, selectedTemplates, reason =
		selectOptionalTemplatesWithPrompt(optionalTemplates, currentTemplateNameSet)
	if okPrompt and selectedTemplates ~= nil then
		return true, selectedTemplates
	end
	if reason == "Cancelled" then
		return false, nil
	end

	return selectOptionalTemplatesFromLineInput(optionalTemplates, currentTemplateNameSet)
end

local function mergeOptionalTemplates(
	availableOptionalTemplates: { string },
	configuredOptionalTemplatesInOrder: { string }
): { string }
	local mergedOptionalTemplates: { string } = {}
	local mergedNameSet: { [string]: boolean } = {}

	for _, name in availableOptionalTemplates do
		if not mergedNameSet[name] then
			mergedNameSet[name] = true
			table.insert(mergedOptionalTemplates, name)
		end
	end

	for _, name in configuredOptionalTemplatesInOrder do
		if not mergedNameSet[name] then
			mergedNameSet[name] = true
			table.insert(mergedOptionalTemplates, name)
		end
	end

	return mergedOptionalTemplates
end

local function cloneConfiguredTemplateEntry(entry): any
	if type(entry) ~= "table" then
		return nil
	end

	local name = entry.Name
	if type(name) ~= "string" or name == "" then
		return nil
	end

	local clonedEntry = {
		Name = name,
	}

	local source = entry.Source
	if type(source) == "string" and source ~= "" then
		clonedEntry.Source = source
	end

	local enableScripts = entry.EnableScripts
	if type(enableScripts) == "boolean" then
		clonedEntry.EnableScripts = enableScripts
	end

	return clonedEntry
end

local function buildTemplatesForConfig(
	selectedTemplates: { string },
	configuredTemplateEntryByName: { [string]: any }?
): { [number]: any }
	local templatesForConfig: { [number]: any } = {}

	for _, name in selectedTemplates do
		local configuredEntry = nil
		if configuredTemplateEntryByName ~= nil then
			configuredEntry = configuredTemplateEntryByName[name]
		end

		local preservedEntry = cloneConfiguredTemplateEntry(configuredEntry)
		if preservedEntry ~= nil then
			table.insert(templatesForConfig, preservedEntry)
		else
			table.insert(templatesForConfig, name)
		end
	end

	return templatesForConfig
end

local function buildProjectConfigContent(templates: { [number]: any }): string
	local function escapeTomlString(value: string): string
		local escaped = value:gsub("\\", "\\\\")
		return escaped:gsub('"', '\\"')
	end

	if #templates == 0 then
		return "Templates = []\n"
	end

	local canUseStringArray = true
	local stringTemplates: { string } = {}
	for _, entry in templates do
		if type(entry) == "string" and entry ~= "" then
			table.insert(stringTemplates, entry)
		else
			canUseStringArray = false
			break
		end
	end

	if canUseStringArray then
		local quoted: { string } = {}
		for _, name in stringTemplates do
			table.insert(quoted, `"{escapeTomlString(name)}"`)
		end
		return `Templates = [{table.concat(quoted, ", ")}]\n`
	end

	local lines: { string } = {}
	for _, entry in templates do
		local name = nil
		local source = nil
		local enableScripts = nil

		if type(entry) == "string" then
			if entry ~= "" then
				name = entry
			end
		elseif type(entry) == "table" then
			local entryName = entry.Name
			if type(entryName) == "string" and entryName ~= "" then
				name = entryName
			end

			local entrySource = entry.Source
			if type(entrySource) == "string" and entrySource ~= "" then
				source = entrySource
			end

			if type(entry.EnableScripts) == "boolean" then
				enableScripts = entry.EnableScripts
			end
		end

		if name ~= nil then
			table.insert(lines, "[[Templates]]")
			table.insert(lines, `Name = "{escapeTomlString(name)}"`)
			if source ~= nil then
				table.insert(lines, `Source = "{escapeTomlString(source)}"`)
			end
			if enableScripts ~= nil then
				local enabledLabel = if enableScripts then "true" else "false"
				table.insert(lines, `EnableScripts = {enabledLabel}`)
			end
			table.insert(lines, "")
		end
	end

	if #lines == 0 then
		return "Templates = []\n"
	end

	return table.concat(lines, "\n") .. "\n"
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
	local okSelect, selectedTemplates = selectOptionalTemplates(optionalTemplates)
	if not okSelect or selectedTemplates == nil then
		return false, { Code = "SelectionCancelled" }
	end

	local templatesForConfig = buildTemplatesForConfig(selectedTemplates, nil)
	local activeTemplates: { string } = { config.BaseTemplateName }
	for _, name in selectedTemplates do
		table.insert(activeTemplates, name)
	end

	local content = buildProjectConfigContent(templatesForConfig)
	local okWrite, err = writeProjectConfig(projectConfigPath, content, fileSystemUtils)
	if not okWrite then
		return false, {
			Code = "WriteProjectConfigFailed",
			Detail = err or "",
		}
	end

	local status = if hadExisting then "Overwritten" else "Created"
	return true, {
		Status = status,
		Path = projectConfigPath,
		Templates = activeTemplates,
	}
end

local function extractConfiguredTemplateData(
	configPath: string,
	baseTemplateName: string
): ({ [string]: boolean }, { [string]: any }, { string })
	local templateNameSet: { [string]: boolean } = {}
	local templateEntryByName: { [string]: any } = {}
	local configuredOptionalTemplatesInOrder: { string } = {}
	local configuredOptionalTemplateSet: { [string]: boolean } = {}
	templateNameSet[baseTemplateName] = true

	local okRead, configData = TomlParser.ReadFile(configPath)
	if not okRead then
		return templateNameSet, templateEntryByName, configuredOptionalTemplatesInOrder
	end

	local templates = configData.Templates
	if type(templates) ~= "table" then
		return templateNameSet, templateEntryByName, configuredOptionalTemplatesInOrder
	end

	for _, entry in templates do
		local name = nil
		if type(entry) == "string" then
			if entry ~= "" then
				name = entry
				if templateEntryByName[entry] == nil then
					templateEntryByName[entry] = entry
				end
			end
		elseif type(entry) == "table" then
			local entryName = entry.Name
			if type(entryName) == "string" and entryName ~= "" then
				name = entryName
				if templateEntryByName[entryName] == nil then
					templateEntryByName[entryName] = cloneConfiguredTemplateEntry(entry)
				end
			end
		end

		if name ~= nil then
			templateNameSet[name] = true
			if name ~= baseTemplateName and not configuredOptionalTemplateSet[name] then
				configuredOptionalTemplateSet[name] = true
				table.insert(configuredOptionalTemplatesInOrder, name)
			end
		end
	end

	templateNameSet[baseTemplateName] = true
	return templateNameSet, templateEntryByName, configuredOptionalTemplatesInOrder
end

local function configureProjectConfig(config, fileSystemUtils)
	local projectConfigPath = config.ProjectConfigFileName
	local hadExisting = FileSystem.isFile(projectConfigPath)

	local templateNames = collectTemplateOptions(config, fileSystemUtils)
	local availableOptionalTemplates = filterOptionalTemplates(templateNames, config.BaseTemplateName)
	local configuredTemplateNameSet, configuredTemplateEntryByName, configuredOptionalTemplatesInOrder =
		extractConfiguredTemplateData(projectConfigPath, config.BaseTemplateName)
	local optionalTemplates =
		mergeOptionalTemplates(availableOptionalTemplates, configuredOptionalTemplatesInOrder)
	local okSelect, selectedTemplates =
		selectOptionalTemplates(optionalTemplates, configuredTemplateNameSet)
	if not okSelect or selectedTemplates == nil then
		return false, { Code = "SelectionCancelled" }
	end

	local templatesForConfig =
		buildTemplatesForConfig(selectedTemplates, configuredTemplateEntryByName)
	local activeTemplates: { string } = { config.BaseTemplateName }
	for _, name in selectedTemplates do
		table.insert(activeTemplates, name)
	end

	local content = buildProjectConfigContent(templatesForConfig)
	local okWrite, err = writeProjectConfig(projectConfigPath, content, fileSystemUtils)
	if not okWrite then
		return false, {
			Code = "WriteProjectConfigFailed",
			Detail = err or "",
		}
	end

	local status = if hadExisting then "Updated" else "Created"
	return true, {
		Status = status,
		Path = projectConfigPath,
		Templates = activeTemplates,
	}
end

local options = parseArgs(Process.args)
if #options.Errors > 0 then
	for _, message in options.Errors do
		print(`[Error] {message}`)
	end
	printUsageForCommand(options.Command)
	Process.exit(1)
end

if options.Help then
	printUsageForCommand(options.Command)
	Process.exit(0)
end

if #Process.args == 0 then
	printGlobalUsage()
	Process.exit(0)
end

local optionName = options.Command
if optionName == nil then
	printGlobalUsage()
	Process.exit(1)
end

if optionName == "init" then
	local okInit, initResult = initProjectConfig(Config, FileSystemUtils, options.Force)
	if not okInit then
		if initResult.Code == "SelectionCancelled" then
			print("[Info] Template selection cancelled. No changes were written.")
			Process.exit(0)
		elseif initResult.Code == "WriteProjectConfigFailed" then
			print(`[Error] Failed to write sb_setup_configs.toml: {initResult.Detail}`)
		else
			print("[Error] Failed to initialize sb_setup_configs.toml.")
		end
		Process.exit(1)
	end

	if initResult.Status == "Created" then
		print(`[Init] sb_setup_configs.toml created at "{initResult.Path}".`)
	elseif initResult.Status == "Overwritten" then
		print(`[Init] sb_setup_configs.toml overwritten at "{initResult.Path}".`)
	else
		print(`[Info] sb_setup_configs.toml already exists at "{initResult.Path}".`)
	end

	if initResult.Templates ~= nil then
		print(`[Init] Active templates: {formatTemplateNamesForPrint(initResult.Templates)}`)
	end
	Process.exit(0)
end

if optionName == "config" then
	local okConfig, configResult = configureProjectConfig(Config, FileSystemUtils)
	if not okConfig then
		if configResult.Code == "SelectionCancelled" then
			print("[Info] Template selection cancelled. No changes were written.")
			Process.exit(0)
		elseif configResult.Code == "WriteProjectConfigFailed" then
			print(`[Error] Failed to write sb_setup_configs.toml: {configResult.Detail}`)
		else
			print("[Error] Failed to update sb_setup_configs.toml.")
		end
		Process.exit(1)
	end

	if configResult.Status == "Created" then
		print(`[Config] sb_setup_configs.toml created at "{configResult.Path}".`)
	else
		print(`[Config] sb_setup_configs.toml updated at "{configResult.Path}".`)
	end

	if configResult.Templates ~= nil then
		print(`[Config] Active templates: {formatTemplateNamesForPrint(configResult.Templates)}`)
	end

	if options.NoInstall then
		print("[Config] Skipping install (--no-install).")
		Process.exit(0)
	end

	print("[Config] Running install with updated templates.")
end

local INSTALL_ERROR_HANDLERS = {
	MissingProjectConfig = function(err)
		print(`[Error] Missing sb_setup_configs.toml at "{err.Path}".`)
	end,
	ProjectConfigParseFailed = function(err)
		local pathLabel = err.Path or "sb_setup_configs.toml"
		print(`[Error] Failed to parse "{pathLabel}" at line {err.Line}.`)
	end,
	ProjectConfigReadFailed = function(err)
		local detail = err.Detail or ""
		print(`[Error] Failed to read sb_setup_configs.toml: {detail}`)
	end,
	MissingTemplates = function(err)
		local pathLabel = err.Path or "sb_setup_configs.toml"
		print(`[Error] Templates list is empty in "{pathLabel}".`)
	end,
	InvalidTemplateEntry = function(err)
		local pathLabel = err.Path or "sb_setup_configs.toml"
		print(`[Error] Invalid template entry at index {err.Index} in "{pathLabel}".`)
	end,
	InvalidTemplateSource = function(err)
		local pathLabel = err.Path or "sb_setup_configs.toml"
		print(`[Error] Invalid template source at index {err.Index} in "{pathLabel}".`)
	end,
	InvalidTemplateEnableScripts = function(err)
		local pathLabel = err.Path or "sb_setup_configs.toml"
		print(`[Error] Invalid template EnableScripts value at index {err.Index} in "{pathLabel}".`)
	end,
	InvalidTemplateOrder = function(err)
		print(`[Error] Templates must start with "{err.BaseTemplateName}".`)
	end,
	MissingTemplateSource = function(err)
		print(`[Error] Template source not found for "{err.TemplateName}": {err.Source}`)
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
		print(`[Error] Template name mismatch for "{err.TemplateName}" (found "{err.ConfigName}").`)
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
	TemplatePesdeReadFailed = function(err)
		local detail = err.Detail or ""
		print(`[Error] Failed to read template pesde file "{err.Path}": {detail}`)
	end,
	TemplatePesdeParseFailed = function(err)
		local lineLabel = err.Line or "unknown"
		local lineText = err.LineText
		local pathLabel = err.Path or "pesde-packages.toml"
		if lineText ~= nil and lineText ~= "" then
			print(
				`[Error] Failed to parse template pesde file "{pathLabel}" at line {lineLabel}: {lineText}`
			)
		else
			print(`[Error] Failed to parse template pesde file "{pathLabel}" at line {lineLabel}.`)
		end
	end,
	InvalidTemplatePesde = function(err)
		print(`[Error] Invalid template pesde file "{err.Path}".`)
	end,
	InvalidTemplatePesdeEntry = function(err)
		print(`[Error] Invalid template pesde entry at index {err.Index} in "{err.Path}".`)
	end,
	TemplateScriptsReadFailed = function(err)
		local detail = err.Detail or ""
		print(`[Error] Failed to read setup scripts file "{err.Path}": {detail}`)
	end,
	TemplateScriptsParseFailed = function(err)
		local lineLabel = err.Line or "unknown"
		local lineText = err.LineText
		local pathLabel = err.Path or "setup-scripts.toml"
		if lineText ~= nil and lineText ~= "" then
			print(
				`[Error] Failed to parse setup scripts file "{pathLabel}" at line {lineLabel}: {lineText}`
			)
		else
			print(`[Error] Failed to parse setup scripts file "{pathLabel}" at line {lineLabel}.`)
		end
	end,
	InvalidTemplateScripts = function(err)
		print(`[Error] Invalid setup scripts file "{err.Path}".`)
	end,
	InvalidTemplateScriptEntry = function(err)
		print(`[Error] Invalid setup script entry at index {err.Index} in "{err.Path}".`)
	end,
	MissingTemplateScriptType = function(err)
		print(`[Error] Missing setup script type at index {err.Index} in "{err.Path}".`)
	end,
	InvalidTemplateScriptType = function(err)
		local typeLabel = err.Type or "unknown"
		print(
			`[Error] Invalid setup script type "{typeLabel}" at index {err.Index} in "{err.Path}".`
		)
	end,
	MissingTemplateScriptCommand = function(err)
		print(`[Error] Missing setup script command at index {err.Index} in "{err.Path}".`)
	end,
	MissingTemplateScriptPath = function(err)
		print(`[Error] Missing setup script path at index {err.Index} in "{err.Path}".`)
	end,
	InvalidTemplateScriptArgs = function(err)
		print(`[Error] Invalid setup script args at index {err.Index} in "{err.Path}".`)
	end,
	InvalidTemplateScriptArg = function(err)
		print(`[Error] Invalid setup script arg at index {err.Index} in "{err.Path}".`)
	end,
	InvalidTemplateScriptRoot = function(err)
		local rootLabel = err.Root or "unknown"
		print(
			`[Error] Invalid setup script root "{rootLabel}" at index {err.Index} in "{err.Path}".`
		)
	end,
	InvalidTemplateScriptOrder = function(err)
		print(`[Error] Invalid setup script order at index {err.Index} in "{err.Path}".`)
	end,
	InvalidTemplateScriptName = function(err)
		print(`[Error] Invalid setup script name at index {err.Index} in "{err.Path}".`)
	end,
	InvalidTemplateScriptCwd = function(err)
		print(`[Error] Invalid setup script cwd at index {err.Index} in "{err.Path}".`)
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

local function addPesdePackage(packageEntry, configRoot: string): (boolean, string?)
	local packageSpec = packageEntry
	local isDev = false
	local isPeer = false
	if type(packageEntry) == "table" then
		packageSpec = packageEntry.Spec
		isDev = packageEntry.Dev == true
		isPeer = packageEntry.Peer == true
	end

	if type(packageSpec) ~= "string" or packageSpec == "" then
		return false, "Invalid package spec."
	end

	local args = { "add", packageSpec }
	if isDev then
		table.insert(args, "--dev")
	end
	if isPeer then
		table.insert(args, "--peer")
	end
	if type(packageEntry) == "table" then
		local target = packageEntry.Target
		if type(target) == "string" and target ~= "" then
			table.insert(args, "--target")
			table.insert(args, target)
		end
	end

	local okExec, resultOrErr =
		pcall(Process.exec, "pesde", args, { capture = true, cwd = configRoot })
	if not okExec then
		return false, tostring(resultOrErr)
	end

	local result = resultOrErr
	if not result.ok then
		return false, result.stderr or ""
	end

	return true, nil
end

local function resolveScriptRoot(script, configRoot, fileSystemUtils): string
	local rootType = script.Root
	if rootType == "Template" then
		local templateRoot = script.TemplateRoot
		if templateRoot ~= nil and templateRoot ~= "" then
			return templateRoot
		end
	end
	return configRoot
end

local function resolveScriptPathRoot(script, configRoot, fileSystemUtils): string
	local rootType = script.ScriptRoot
	if rootType == "Template" then
		local templateRoot = script.TemplateRoot
		if templateRoot ~= nil and templateRoot ~= "" then
			return templateRoot
		end
	end
	return configRoot
end

local function resolveScriptPath(scriptPath: string, rootPath: string, fileSystemUtils): string
	if TemplateRoots.IsAbsolutePath(scriptPath) then
		return scriptPath
	end
	return fileSystemUtils.JoinPath(rootPath, scriptPath)
end

local function buildScriptCommand(script, configRoot, fileSystemUtils): (string, { string })
	local runRoot = resolveScriptRoot(script, configRoot, fileSystemUtils)
	local args: { string } = {}
	if script.Type == "Lune" then
		local scriptRoot = resolveScriptPathRoot(script, configRoot, fileSystemUtils)
		local scriptPath = resolveScriptPath(script.Script, scriptRoot, fileSystemUtils)
		table.insert(args, "run")
		table.insert(args, scriptPath)
		for _, arg in script.Args do
			table.insert(args, arg)
		end
		return "lune", args
	end

	local command = script.Command
	for _, arg in script.Args do
		table.insert(args, arg)
	end
	return command, args
end

local function resolveScriptCwd(script, configRoot, fileSystemUtils): string
	local rootPath = resolveScriptRoot(script, configRoot, fileSystemUtils)
	local cwd = script.Cwd
	if cwd == nil or cwd == "" then
		return rootPath
	end
	if TemplateRoots.IsAbsolutePath(cwd) then
		return cwd
	end
	return fileSystemUtils.JoinPath(rootPath, cwd)
end

local function printTemplateList(listResult)
	local templates = listResult.Templates or {}
	print(`[Template] Available templates: {#templates}`)
	for _, templateInfo in templates do
		local templateName = templateInfo.Name or "unknown"
		local description = templateInfo.Description
		if description == nil or description == "" then
			description = "No description."
		end

		local extends = templateInfo.Extends
		local extendsLabel = "none"
		if type(extends) == "table" and #extends > 0 then
			extendsLabel = table.concat(extends, ", ")
		end

		local sourceLabel = templateInfo.Source or "unknown"
		local pathLabel = templateInfo.Path or ""

		print(`[Template] {templateName}`)
		print(`  Description: {description}`)
		print(`  Extends: {extendsLabel}`)
		print(`  Source: {sourceLabel}`)
		print(`  Path: {pathLabel}`)
	end

	local roots = listResult.TemplateRoots or {}
	if #roots > 0 then
		print(`[Template] Roots: {table.concat(roots, ", ")}`)
	end
end

if optionName == "list" then
	local okList, listResult = Installer.ListTemplates(Config, FileSystemUtils, TomlParser)
	if not okList then
		printInstallError(listResult)
		Process.exit(1)
	end

	printTemplateList(listResult)
	Process.exit(0)
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

local configRoot = TemplateRoots.ResolveConfigRoot(Config.ProjectConfigFileName, FileSystemUtils)
local submodules = installResult.Submodules or {}
for _, submodule in submodules do
	local submodulePath = submodule.Path
	local submoduleResult = Submodule.Ensure(submodule, FileSystemUtils, configRoot)

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

local pesdePackages = installResult.PesdePackages or {}
for _, packageEntry in pesdePackages do
	local packageSpec = packageEntry
	if type(packageEntry) == "table" then
		packageSpec = packageEntry.Spec
	end

	local okAdd, err = addPesdePackage(packageEntry, configRoot)
	if not okAdd then
		local label = packageSpec or "unknown"
		print(`[Error] Failed to add pesde package "{label}": {err}`)
		Process.exit(1)
	end

	if packageSpec == nil then
		packageSpec = "unknown"
	end
	print(`[Pesde] "{packageSpec}" added`)
end

if #pesdePackages > 0 then
	local okInstall, installResult = pcall(
		Process.exec,
		"pesde",
		{ "install" },
		{ capture = true, cwd = configRoot }
	)
	if not okInstall then
		print(`[Error] Failed to run pesde install: {tostring(installResult)}`)
		Process.exit(1)
	end

	local result = installResult
	if not result.ok then
		local stderr = result.stderr or ""
		print(`[Error] pesde install failed: {stderr}`)
		Process.exit(1)
	end
	print("[Pesde] install completed")
end

local scripts = installResult.Scripts or {}
for _, script in scripts do
	local displayName = script.Name or script.Script or script.Command or "script"
	local templateLabel = script.TemplateName or "unknown"
	print(`[Script] Running "{displayName}" for template "{templateLabel}".`)

	local command, args = buildScriptCommand(script, configRoot, FileSystemUtils)
	local cwd = resolveScriptCwd(script, configRoot, FileSystemUtils)
	local okExec, resultOrErr = pcall(Process.exec, command, args, { capture = true, cwd = cwd })
	if not okExec then
		print(`[Error] Script failed to execute "{displayName}": {tostring(resultOrErr)}`)
		Process.exit(1)
	end

	local result = resultOrErr
	if not result.ok then
		local stderr = result.stderr or ""
		local stdout = result.stdout or ""
		print(`[Error] Script failed "{displayName}".`)
		if stdout ~= "" then
			print(`[Error] stdout: {stdout}`)
		end
		if stderr ~= "" then
			print(`[Error] stderr: {stderr}`)
		end
		Process.exit(1)
	end

	if result.stdout ~= nil and result.stdout ~= "" then
		print(result.stdout)
	end
end
