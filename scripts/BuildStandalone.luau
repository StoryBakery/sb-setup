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
local TEMPLATES_ROOT = "src/templates"

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

local function normalizeRelativePath(path: string): string
	return path:gsub("\\", "/")
end

local function updateTemplateDigest(digest: number, value: string): number
	local updatedDigest = digest
	local modulo = 2_147_483_647

	for index = 1, #value do
		local byte = string.byte(value, index)
		updatedDigest = (updatedDigest + (byte * ((index % 251) + 1))) % modulo
	end

	return updatedDigest
end

local function collectEmbeddedTemplateFileLiterals(): (boolean, { string }?, string?)
	if not FileSystem.isDir(TEMPLATES_ROOT) then
		return false, nil, `Missing templates root "{TEMPLATES_ROOT}".`
	end

	local files = FileSystemUtils.CollectFiles(TEMPLATES_ROOT)
	table.sort(files, function(left, right)
		return left.RelativePath < right.RelativePath
	end)

	local entries: { string } = {}
	local digest = 1
	local totalBytes = 0

	for _, item in files do
		local okRead, content = readSource(item.SourcePath)
		if not okRead or content == nil then
			return false, nil, `Failed to read template file "{item.SourcePath}".`
		end

		local relativePath = normalizeRelativePath(item.RelativePath)
		local keyLiteral = string.format("%q", relativePath)
		local contentLiteral = string.format("%q", content)
		table.insert(entries, "\t[" .. keyLiteral .. "] = " .. contentLiteral .. ",")

		digest = updateTemplateDigest(digest, relativePath)
		digest = updateTemplateDigest(digest, "\n")
		digest = updateTemplateDigest(digest, content)
		totalBytes += #content
	end

	local version = `files-{#files}-bytes-{totalBytes}-digest-{digest}`
	return true, entries, version
end

local function appendEmbeddedTemplateBootstrap(
	chunks: { string },
	embeddedTemplateEntries: { string },
	embeddedTemplatesVersion: string
)
	local versionLiteral = string.format("%q", embeddedTemplatesVersion)

	table.insert(chunks, "local STANDALONE_TEMPLATES_VERSION = " .. versionLiteral)
	table.insert(chunks, "local STANDALONE_TEMPLATE_FILES = {")
	for _, entry in embeddedTemplateEntries do
		table.insert(chunks, entry)
	end
	table.insert(chunks, "}")
	table.insert(chunks, "")
	table.insert(chunks, "local function ensureStandaloneTemplatesRoot()")
	table.insert(chunks, '\tlocal StandaloneFileSystem = require("@lune/fs")')
	table.insert(chunks, '\tlocal StandaloneProcess = require("@lune/process")')
	table.insert(chunks, "\tlocal tempPath = StandaloneProcess.env.TEMP")
	table.insert(chunks, '\tif tempPath == nil or tempPath == "" then')
	table.insert(chunks, "\t\ttempPath = StandaloneProcess.env.TMP")
	table.insert(chunks, "\tend")
	table.insert(chunks, '\tif tempPath == nil or tempPath == "" then')
	table.insert(chunks, "\t\ttempPath = StandaloneProcess.env.TMPDIR")
	table.insert(chunks, "\tend")
	table.insert(chunks, '\tif tempPath == nil or tempPath == "" then')
	table.insert(chunks, '\t\ttempPath = "."')
	table.insert(chunks, "\tend")
	table.insert(chunks, "")
	table.insert(chunks, "\tlocal fileSystemUtils = Modules.FileSystemUtils")
	table.insert(
		chunks,
		'\tlocal runtimeRoot = fileSystemUtils.JoinPath(tempPath, "sb-setup-runtime")'
	)
	table.insert(
		chunks,
		"\tlocal versionRoot = fileSystemUtils.JoinPath(runtimeRoot, STANDALONE_TEMPLATES_VERSION)"
	)
	table.insert(
		chunks,
		'\tlocal templatesRoot = fileSystemUtils.JoinPath(versionRoot, "templates")'
	)
	table.insert(chunks, "")
	table.insert(chunks, "\tif not StandaloneFileSystem.isDir(templatesRoot) then")
	table.insert(chunks, "\t\tfileSystemUtils.MakeDirectoryRecursive(templatesRoot)")
	table.insert(chunks, "\t\tfor relativePath, content in STANDALONE_TEMPLATE_FILES do")
	table.insert(
		chunks,
		"\t\t\tlocal outputPath = fileSystemUtils.JoinPath(templatesRoot, relativePath)"
	)
	table.insert(chunks, "\t\t\tfileSystemUtils.EnsureParentDirectory(outputPath)")
	table.insert(chunks, "\t\t\tStandaloneFileSystem.writeFile(outputPath, content)")
	table.insert(chunks, "\t\tend")
	table.insert(chunks, "\tend")
	table.insert(chunks, "")
	table.insert(chunks, "\treturn templatesRoot")
	table.insert(chunks, "end")
	table.insert(chunks, "")
	table.insert(chunks, "local okTemplatesRoot, templatesRootOrErr = pcall(ensureStandaloneTemplatesRoot)")
	table.insert(
		chunks,
		'if okTemplatesRoot and type(templatesRootOrErr) == "string" and templatesRootOrErr ~= "" then'
	)
	table.insert(chunks, "\tModules.TemplateRoots.SetRuntimeTemplatesRoot(templatesRootOrErr)")
	table.insert(chunks, "else")
	table.insert(chunks, "\tlocal detail = tostring(templatesRootOrErr)")
	table.insert(chunks, '\tprint(`[Warn] Failed to prepare embedded templates: {detail}`)')
	table.insert(chunks, "end")
	table.insert(chunks, "")
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

local okTemplates, embeddedTemplateEntries, embeddedTemplatesVersion =
	collectEmbeddedTemplateFileLiterals()
if not okTemplates or embeddedTemplateEntries == nil or embeddedTemplatesVersion == nil then
	local detail = embeddedTemplatesVersion or "unknown"
	print(`[Error] Failed to embed templates: {detail}`)
	Process.exit(1)
end

local okReadEntry, entrySource = readSource(ENTRY_PATH)
if not okReadEntry or entrySource == nil then
	print(`[Error] Failed to read entry script "{ENTRY_PATH}".`)
	Process.exit(1)
end

appendEmbeddedTemplateBootstrap(chunks, embeddedTemplateEntries, embeddedTemplatesVersion)

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
