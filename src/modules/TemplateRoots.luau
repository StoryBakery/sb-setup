--[[
	템플릿 루트와 경로 해석을 제공하는 모듈입니다.
]]

local FileSystem = require("@lune/fs")

local function normalizeSourcePath(source: string): string
	local normalized = source
	if normalized:sub(1, 1) == "@" then
		normalized = normalized:sub(2)
	end
	return normalized:gsub("\\", "/")
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

local function resolveConfigRoot(configPath: string, fileSystemUtils): string
	local configDir = fileSystemUtils.GetDirectoryName(configPath)
	if configDir == "" then
		return "."
	end
	return configDir
end

local function resolvePathFromConfig(path: string, configRoot: string, fileSystemUtils): string
	if isAbsolutePath(path) then
		return path
	end
	return fileSystemUtils.JoinPath(configRoot, path)
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

local function resolveTemplatesRootFromBase(
	baseDir: string,
	templatesRootName: string,
	fileSystemUtils
): string?
	if baseDir == "" then
		return nil
	end

	local direct = fileSystemUtils.JoinPath(baseDir, templatesRootName)
	if FileSystem.isDir(direct) then
		return direct
	end

	local srcRoot = fileSystemUtils.JoinPath(baseDir, "src")
	local srcTemplates = fileSystemUtils.JoinPath(srcRoot, templatesRootName)
	if FileSystem.isDir(srcTemplates) then
		return srcTemplates
	end

	return nil
end

local function findTemplatesRootInPackages(
	parentDir: string,
	templatesRootName: string,
	fileSystemUtils
): string?
	if parentDir == "" or not FileSystem.isDir(parentDir) then
		return nil
	end

	local ok, entries = pcall(FileSystem.readDir, parentDir)
	if not ok or entries == nil then
		return nil
	end

	table.sort(entries)

	for _, entry in entries do
		local entryPath = fileSystemUtils.JoinPath(parentDir, entry)
		if FileSystem.isDir(entryPath) then
			local resolved =
				resolveTemplatesRootFromBase(entryPath, templatesRootName, fileSystemUtils)
			if resolved ~= nil then
				return resolved
			end
		end
	end

	return nil
end

local function resolveProjectTemplatesRoot(
	configRoot: string,
	templatesRootName: string,
	fileSystemUtils
): string
	return fileSystemUtils.JoinPath(configRoot, templatesRootName)
end

local function resolvePackageTemplatesRoot(
	templatesRootName: string,
	configRoot: string,
	fileSystemUtils
): string?
	local source = debug.info(1, "s")
	if source ~= nil and source ~= "" then
		local scriptPath = normalizeSourcePath(source)
		local scriptDir = fileSystemUtils.GetDirectoryName(scriptPath)
		if scriptDir ~= "" then
			local fromScript =
				findTemplatesRoot(scriptDir, templatesRootName, fileSystemUtils)
			if fromScript ~= nil then
				return fromScript
			end
		end
	end

	local fromConfig = resolveTemplatesRootFromBase(
		configRoot,
		templatesRootName,
		fileSystemUtils
	)
	if fromConfig ~= nil then
		return fromConfig
	end

	local fromPesde = findTemplatesRootInPackages(
		fileSystemUtils.JoinPath(configRoot, ".pesde"),
		templatesRootName,
		fileSystemUtils
	)
	if fromPesde ~= nil then
		return fromPesde
	end

	local fromPkgs = findTemplatesRootInPackages(
		fileSystemUtils.JoinPath(configRoot, "pkgs"),
		templatesRootName,
		fileSystemUtils
	)
	if fromPkgs ~= nil then
		return fromPkgs
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

local TemplateRoots = {
	ResolveConfigRoot = resolveConfigRoot,
	ResolveProjectTemplatesRoot = resolveProjectTemplatesRoot,
	ResolvePathFromConfig = resolvePathFromConfig,
	ResolvePackageTemplatesRoot = resolvePackageTemplatesRoot,
	ListTemplateNames = listTemplateNames,
	IsAbsolutePath = isAbsolutePath,
}

return TemplateRoots
