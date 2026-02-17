--[[
	standalone 바이너리 빌드용 단일 엔트리 파일을 생성하는 스크립트입니다.
]]

local FileSystem = require("@lune/fs")
local Process = require("@lune/process")

local FileSystemUtils = require("../src/modules/FileSystemUtils")

type ModuleEntry = {
	Name: string,
	Path: string,
}

local MODULES: { ModuleEntry } = {
	{ Name = "Config", Path = "src/modules/Config.luau" },
	{ Name = "FileSystemUtils", Path = "src/modules/FileSystemUtils.luau" },
	{ Name = "TemplateRoots", Path = "src/modules/TemplateRoots.luau" },
	{ Name = "ManagedBlock", Path = "src/modules/ManagedBlock.luau" },
	{ Name = "TomlParser", Path = "src/modules/TomlParser.luau" },
	{ Name = "Submodule", Path = "src/modules/Submodule.luau" },
	{ Name = "Installer", Path = "src/modules/Installer.luau" },
}

local MODULE_NAME_SET: { [string]: boolean } = {}
for _, module in MODULES do
	MODULE_NAME_SET[module.Name] = true
end

local ENTRY_PATH = "src/init.luau"
local OUTPUT_PATH = "build/init.standalone.luau"

local function normalizeLineEndings(content: string): string
	local normalized = content:gsub("\r\n", "\n")
	return normalized:gsub("\r", "\n")
end

local function stripBom(content: string): string
	if content:sub(1, 3) == "\239\187\191" then
		return content:sub(4)
	end
	return content
end

local function readSource(path: string): (boolean, string?)
	local okRead, contentOrErr = pcall(FileSystem.readFile, path)
	if not okRead then
		return false, tostring(contentOrErr)
	end

	local content = stripBom(normalizeLineEndings(contentOrErr))
	return true, content
end

local function replaceModuleRequires(source: string): string
	return source:gsub(
		'(local%s+([%a_][%w_]*)%s*=%s*require%("%./([%w_]+)"%))',
		function(fullLine: string, variableName: string, moduleName: string): string
			if MODULE_NAME_SET[moduleName] then
				return `local {variableName} = Modules.{moduleName}`
			end
			return fullLine
		end
	)
end

local function replaceEntryRequires(source: string): string
	return source:gsub(
		'(local%s+([%a_][%w_]*)%s*=%s*require%("@self/modules/([%w_]+)"%))',
		function(fullLine: string, variableName: string, moduleName: string): string
			if MODULE_NAME_SET[moduleName] then
				return `local {variableName} = Modules.{moduleName}`
			end
			return fullLine
		end
	)
end

local function appendModuleChunk(
	chunks: { string },
	module: ModuleEntry,
	moduleSource: string
)
	table.insert(chunks, `local function load{module.Name}Module()`)
	table.insert(chunks, moduleSource)
	table.insert(chunks, "end")
	table.insert(chunks, `Modules.{module.Name} = load{module.Name}Module()`)
	table.insert(chunks, "")
end

local chunks: { string } = {
	"--[[",
	"\t자동 생성된 standalone 엔트리 파일입니다.",
	"\t직접 수정하지 말고 scripts/BuildStandalone.luau 를 실행해 갱신합니다.",
	"]]",
	"",
	"local Modules = {}",
	"",
}

for _, module in MODULES do
	local okRead, source = readSource(module.Path)
	if not okRead or source == nil then
		print(`[Error] Failed to read module "{module.Path}".`)
		Process.exit(1)
	end

	local moduleSource = replaceModuleRequires(source)
	appendModuleChunk(chunks, module, moduleSource)
end

local okReadEntry, entrySource = readSource(ENTRY_PATH)
if not okReadEntry or entrySource == nil then
	print(`[Error] Failed to read entry script "{ENTRY_PATH}".`)
	Process.exit(1)
end

entrySource = replaceEntryRequires(entrySource)
table.insert(chunks, entrySource)
table.insert(chunks, "")

local outputContent = table.concat(chunks, "\n")
FileSystemUtils.EnsureParentDirectory(OUTPUT_PATH)

local okWrite, writeErr = pcall(function()
	FileSystem.writeFile(OUTPUT_PATH, outputContent)
end)
if not okWrite then
	print(`[Error] Failed to write standalone entry "{OUTPUT_PATH}": {tostring(writeErr)}`)
	Process.exit(1)
end

print(`[Build] Standalone entry generated: {OUTPUT_PATH}`)
Process.exit(0)
