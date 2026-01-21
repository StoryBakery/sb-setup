--[[
	템플릿 설치를 테스트 환경에서 실행하는 스크립트입니다.
]]

local Process = require("@lune/process")

local Config = require("../src/modules/Config")
local FileSystemUtils = require("../src/modules/FileSystemUtils")
local Installer = require("../src/modules/Installer")
local ManagedBlock = require("../src/modules/ManagedBlock")
local TomlParser = require("../src/modules/TomlParser")

local function printInstallError(installError)
	local codeLabel = installError.Code or "Unknown"
	print(`[Error] Install failed ({codeLabel}).`)

	local pathLabel = installError.Path
	if pathLabel ~= nil and pathLabel ~= "" then
		print(`[Error] Path: {pathLabel}`)
	end

	local templateName = installError.TemplateName
	if templateName ~= nil and templateName ~= "" then
		print(`[Error] Template: {templateName}`)
	end

	local detail = installError.Detail
	if detail ~= nil and detail ~= "" then
		print(`[Error] Detail: {detail}`)
	end

	local lineLabel = installError.Line
	if lineLabel ~= nil then
		print(`[Error] Line: {lineLabel}`)
	end

	local lineText = installError.LineText
	if lineText ~= nil and lineText ~= "" then
		print(`[Error] LineText: {lineText}`)
	end
end

local function hasTemplate(templates, name: string): boolean
	if type(templates) ~= "table" then
		return false
	end

	for _, entry in templates do
		if type(entry) == "string" then
			if entry == name then
				return true
			end
		elseif type(entry) == "table" then
			if entry.Name == name then
				return true
			end
		end
	end

	return false
end

local okConfig, configData = TomlParser.ReadFile(Config.ProjectConfigFileName)
if not okConfig then
	print("[Error] Missing bakery_project_configs.toml for test run.")
	Process.exit(1)
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
print(`[Test] Templates applied: {templateLabel}`)

local pesdePackages = installResult.PesdePackages or {}
if hasTemplate(configData.Templates, "pesde-default-packages") then
	if #pesdePackages == 0 then
		print("[Error] Expected pesde packages but none were detected.")
		Process.exit(1)
	end
	print(`[Test] Pesde packages: {#pesdePackages}`)
end

local scripts = installResult.Scripts or {}
if hasTemplate(configData.Templates, "pesde-default-packages") then
	if #scripts == 0 then
		print("[Error] Expected setup scripts but none were detected.")
		Process.exit(1)
	end
	print(`[Test] Setup scripts: {#scripts}`)
end

local submodules = installResult.Submodules or {}
if hasTemplate(configData.Templates, "with-bakery-dev-handbook") then
	if #submodules == 0 then
		print("[Error] Expected submodules but none were detected.")
		Process.exit(1)
	end
	print(`[Test] Submodules: {#submodules}`)
end

Process.exit(0)
