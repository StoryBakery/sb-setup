--[[
	템플릿 기반 설정 파일을 설치하는 모듈입니다.
]]

local FileSystem = require("@lune/fs")

local TemplateRoots = require("@self/modules/TemplateRoots")

local function trim(value: string): string
	return value:match("^%s*(.-)%s*$")
end

local function stripInlineComment(line: string): string
	local cleaned = line
	local commentIndex = cleaned:find("#", 1, true)
	if commentIndex then
		cleaned = cleaned:sub(1, commentIndex - 1)
	end

	commentIndex = cleaned:find(";", 1, true)
	if commentIndex then
		cleaned = cleaned:sub(1, commentIndex - 1)
	end

	return cleaned
end

local function splitLines(text: string): { string }
	local normalized = text:gsub("\r\n", "\n")
	normalized = normalized:gsub("\r", "\n")
	local lines: { string } = {}
	local startIndex = 1

	while true do
		local nextIndex = normalized:find("\n", startIndex, true)
		if not nextIndex then
			table.insert(lines, normalized:sub(startIndex))
			break
		end

		table.insert(lines, normalized:sub(startIndex, nextIndex - 1))
		startIndex = nextIndex + 1
	end

	return lines
end

local function stripQuotes(value: string): string
	local quoted = value:match('^"(.*)"$')
	if quoted ~= nil then
		return quoted
	end
	return value
end

local function readProjectConfig(configPath: string, tomlParser)
	local okRead, result = tomlParser.ReadFile(configPath)
	if not okRead then
		if result.Code == "MissingFile" then
			return false, { Code = "MissingProjectConfig", Path = configPath }
		end
		if result.Code == "ParseError" then
			return false, {
				Code = "ProjectConfigParseFailed",
				Path = configPath,
				Line = result.Line,
				LineText = result.LineText,
			}
		end
		return false, {
			Code = "ProjectConfigReadFailed",
			Path = configPath,
			Detail = result.Detail or "",
		}
	end

	local templates = result.Templates
	if type(templates) ~= "table" or #templates == 0 then
		return false, { Code = "MissingTemplates", Path = configPath }
	end

	local templateRefs: { [number]: { [string]: any } } = {}
	local firstEntry = templates[1]
	local firstType = type(firstEntry)

	if firstType == "string" then
		for index, name in templates do
			if type(name) ~= "string" or name == "" then
				return false, { Code = "InvalidTemplateEntry", Index = index, Path = configPath }
			end
			table.insert(templateRefs, { Name = name })
		end
	elseif firstType == "table" then
		for index, entry in templates do
			if type(entry) ~= "table" then
				return false, { Code = "InvalidTemplateEntry", Index = index, Path = configPath }
			end

			local name = entry.Name
			if type(name) ~= "string" or name == "" then
				return false, { Code = "InvalidTemplateEntry", Index = index, Path = configPath }
			end

			local source = entry.Source
			if source ~= nil and (type(source) ~= "string" or source == "") then
				return false, { Code = "InvalidTemplateSource", Index = index, Path = configPath }
			end

			table.insert(templateRefs, { Name = name, Source = source })
		end
	else
		return false, { Code = "InvalidTemplateEntry", Index = 1, Path = configPath }
	end

	return true, { Templates = templateRefs }
end

local function loadTemplateConfig(
	templateName: string,
	sourcePath: string?,
	configRoot: string,
	projectTemplatesRoot: string?,
	packageTemplatesRoot: string?,
	templateConfigFileName: string,
	tomlParser,
	fileSystemUtils
)
	local templateRoot = nil
	if sourcePath ~= nil then
		local resolvedSourcePath = TemplateRoots.ResolvePathFromConfig(
			sourcePath,
			configRoot,
			fileSystemUtils
		)
		if FileSystem.isDir(resolvedSourcePath) then
			templateRoot = resolvedSourcePath
		else
			return false, {
				Code = "MissingTemplateSource",
				TemplateName = templateName,
				Source = resolvedSourcePath,
			}
		end
	else
		if projectTemplatesRoot ~= nil then
			local projectRoot = fileSystemUtils.JoinPath(projectTemplatesRoot, templateName)
			if FileSystem.isDir(projectRoot) then
				templateRoot = projectRoot
			end
		end

		if templateRoot == nil and packageTemplatesRoot ~= nil then
			local packageRoot = fileSystemUtils.JoinPath(packageTemplatesRoot, templateName)
			if FileSystem.isDir(packageRoot) then
				templateRoot = packageRoot
			end
		end
	end

	if templateRoot == nil then
		local roots: { string } = {}
		if projectTemplatesRoot ~= nil then
			table.insert(roots, projectTemplatesRoot)
		end
		if packageTemplatesRoot ~= nil then
			table.insert(roots, packageTemplatesRoot)
		end
		local availableTemplates = TemplateRoots.ListTemplateNames(roots, fileSystemUtils)
		return false, {
			Code = "MissingTemplate",
			TemplateName = templateName,
			AvailableTemplates = availableTemplates,
			TemplateRoots = roots,
		}
	end

	local configPath = fileSystemUtils.JoinPath(templateRoot, templateConfigFileName)
	local okRead, result = tomlParser.ReadFile(configPath)
	if not okRead then
		if result.Code == "MissingFile" then
			return false, { Code = "MissingTemplateConfig", Path = configPath }
		end
		if result.Code == "ParseError" then
			return false, {
				Code = "TemplateConfigParseFailed",
				Path = configPath,
				Line = result.Line,
				LineText = result.LineText,
			}
		end
		return false, {
			Code = "TemplateConfigReadFailed",
			Path = configPath,
			Detail = result.Detail or "",
		}
	end

	local name = result.Name
	if name == nil or name == "" then
		return false, { Code = "MissingTemplateName", Path = configPath }
	end
	if name ~= templateName then
		return false, {
			Code = "TemplateNameMismatch",
			TemplateName = templateName,
			ConfigName = name,
			Path = configPath,
		}
	end

	local extends = result.Extends
	if type(extends) ~= "table" then
		extends = {}
	end

	return true, {
		Name = name,
		Extends = extends,
		Path = templateRoot,
	}
end

local function resolveTemplates(
	requestedTemplates: { [number]: { [string]: any } },
	configRoot: string,
	projectTemplatesRoot: string?,
	packageTemplatesRoot: string?,
	templateConfigFileName: string,
	tomlParser,
	fileSystemUtils
)
	local resolved: { string } = {}
	local visited: { [string]: boolean } = {}
	local cache: { [string]: any } = {}
	local sourceByName: { [string]: string } = {}

	for _, ref in requestedTemplates do
		local name = ref.Name
		local source = ref.Source
		if source ~= nil then
			if sourceByName[name] ~= nil and sourceByName[name] ~= source then
				return false, { Code = "DuplicateTemplateSource", TemplateName = name }
			end
			sourceByName[name] = source
		end
	end

	local function loadTemplate(name: string)
		if cache[name] ~= nil then
			return true, cache[name]
		end
		local sourcePath = sourceByName[name]
		local ok, result = loadTemplateConfig(
			name,
			sourcePath,
			configRoot,
			projectTemplatesRoot,
			packageTemplatesRoot,
			templateConfigFileName,
			tomlParser,
			fileSystemUtils
		)
		if not ok then
			return false, result
		end
		cache[name] = result
		return true, result
	end

	local function addTemplate(name: string)
		if visited[name] then
			return true, nil
		end
		local ok, templateInfo = loadTemplate(name)
		if not ok then
			return false, templateInfo
		end
		visited[name] = true

		for _, parentName in templateInfo.Extends do
			local okAdd, err = addTemplate(parentName)
			if not okAdd then
				return false, err
			end
		end

		table.insert(resolved, name)
		return true, nil
	end

	for _, ref in requestedTemplates do
		local okAdd, err = addTemplate(ref.Name)
		if not okAdd then
			return false, err
		end
	end

	return true, { Order = resolved, Infos = cache }
end

local function collectTemplateFiles(
	root: string,
	templateConfigFileName: string,
	templateSubmoduleFileName: string,
	fileSystemUtils
)
	local files = fileSystemUtils.CollectFiles(root)
	local filtered: { any } = {}
	for _, item in files do
		if item.RelativePath ~= templateConfigFileName
			and item.RelativePath ~= templateSubmoduleFileName then
			table.insert(filtered, item)
		end
	end
	return filtered
end

local function readFile(path: string): (boolean, string?)
	local okRead, contentOrErr = pcall(FileSystem.readFile, path)
	if not okRead then
		return false, tostring(contentOrErr)
	end
	return true, contentOrErr
end

local function writeFile(path: string, content: string, fileSystemUtils): (boolean, string?)
	fileSystemUtils.EnsureParentDirectory(path)
	local okWrite, err = pcall(function()
		FileSystem.writeFile(path, content)
	end)
	if not okWrite then
		return false, tostring(err)
	end
	return true, nil
end

local function parseTemplateGitmodules(content: string)
	local entries: { [number]: { [string]: any } } = {}
	local current = nil
	local lines = splitLines(content)

	for lineNumber, line in lines do
		local stripped = trim(stripInlineComment(line))
		if stripped ~= "" then
			local name = stripped:match("^%[submodule%s+\"(.-)\"%]$")
			if name then
				current = { Name = name }
				table.insert(entries, current)
			else
				local key, value = stripped:match("^(%w+)%s*=%s*(.+)$")
				if key == nil or value == nil then
					return false, {
						Code = "TemplateSubmoduleParseFailed",
						Line = lineNumber,
						LineText = line,
					}
				end
				if current == nil then
					return false, {
						Code = "TemplateSubmoduleParseFailed",
						Line = lineNumber,
						LineText = line,
					}
				end

				value = trim(stripQuotes(value))
				if key == "path" then
					current.Path = value
				elseif key == "url" then
					current.Url = value
				end
			end
		end
	end

	local results: { [number]: { [string]: string } } = {}
	for _, entry in entries do
		if entry.Path == nil or entry.Url == nil then
			return false, {
				Code = "InvalidTemplateSubmodule",
				SubmoduleName = entry.Name or "",
			}
		end
		table.insert(results, {
			Path = entry.Path,
			Url = entry.Url,
		})
	end

	return true, results
end

local function collectTemplateSubmodules(
	templateRoot: string,
	templateSubmoduleFileName: string,
	fileSystemUtils
)
	if templateSubmoduleFileName == "" then
		return true, {}
	end

	local submodulePath = fileSystemUtils.JoinPath(templateRoot, templateSubmoduleFileName)
	if not FileSystem.isFile(submodulePath) then
		return true, {}
	end

	local okRead, content = readFile(submodulePath)
	if not okRead or content == nil then
		return false, { Code = "TemplateSubmoduleReadFailed", Path = submodulePath }
	end

	local okParse, parseResult = parseTemplateGitmodules(content)
	if not okParse then
		if parseResult.Code == "TemplateSubmoduleParseFailed" then
			return false, {
				Code = "TemplateSubmoduleParseFailed",
				Path = submodulePath,
				Line = parseResult.Line,
				LineText = parseResult.LineText,
			}
		end
		if parseResult.Code == "InvalidTemplateSubmodule" then
			return false, {
				Code = "InvalidTemplateSubmodule",
				Path = submodulePath,
				SubmoduleName = parseResult.SubmoduleName,
			}
		end
		return false, { Code = "TemplateSubmoduleParseFailed", Path = submodulePath }
	end

	return true, parseResult
end

local function applyTemplate(
	templateRoot: string,
	templateConfigFileName: string,
	templateSubmoduleFileName: string,
	fileSystemUtils,
	managedBlock
)
	local files = collectTemplateFiles(
		templateRoot,
		templateConfigFileName,
		templateSubmoduleFileName,
		fileSystemUtils
	)
	local appliedCount = 0

	for _, item in files do
		local okRead, templateContent = readFile(item.SourcePath)
		if not okRead or templateContent == nil then
			return false, { Code = "ReadTemplateFailed", Path = item.SourcePath }
		end

		local templateInfo = managedBlock.ParseTemplate(templateContent)
		local destinationPath = item.RelativePath

		if not templateInfo.HasBlocks or not FileSystem.isFile(destinationPath) then
			fileSystemUtils.CopyFile(item.SourcePath, destinationPath)
			appliedCount += 1
		else
			local okDest, destinationContent = readFile(destinationPath)
			if not okDest or destinationContent == nil then
				return false, { Code = "ReadDestinationFailed", Path = destinationPath }
			end

			local merged = managedBlock.Merge(destinationContent, templateInfo)
			local okWrite = writeFile(destinationPath, merged, fileSystemUtils)
			if not okWrite then
				return false, { Code = "WriteDestinationFailed", Path = destinationPath }
			end
			appliedCount += 1
		end
	end

	return true, appliedCount
end

local function install(config, fileSystemUtils, tomlParser, managedBlock)
	local projectConfigPath = config.ProjectConfigFileName
	local configRoot = TemplateRoots.ResolveConfigRoot(projectConfigPath, fileSystemUtils)
	local okProject, projectResult = readProjectConfig(projectConfigPath, tomlParser)
	if not okProject then
		return false, projectResult
	end

	local requestedTemplates = projectResult.Templates
	if requestedTemplates[1].Name ~= config.BaseTemplateName then
		return false, {
			Code = "InvalidTemplateOrder",
			BaseTemplateName = config.BaseTemplateName,
		}
	end

	local packageTemplatesRoot = TemplateRoots.ResolvePackageTemplatesRoot(
		config.TemplatesRootName,
		configRoot,
		fileSystemUtils
	)
	local projectTemplatesRoot = TemplateRoots.ResolveProjectTemplatesRoot(
		configRoot,
		config.TemplatesRootName,
		fileSystemUtils
	)
	local hasProjectTemplatesRoot = FileSystem.isDir(projectTemplatesRoot)

	local okResolved, resolvedResult = resolveTemplates(
		requestedTemplates,
		configRoot,
		if hasProjectTemplatesRoot then projectTemplatesRoot else nil,
		packageTemplatesRoot,
		config.TemplateConfigFileName,
		tomlParser,
		fileSystemUtils
	)
	if not okResolved then
		return false, resolvedResult
	end

	local totalCount = 0
	local templateCounts: { [string]: number } = {}
	local submodules: { [number]: { [string]: string } } = {}
	local submoduleUrlByPath: { [string]: string } = {}
	local order = resolvedResult.Order
	local infos = resolvedResult.Infos

	for _, templateName in order do
		local templateInfo = infos[templateName]
		if templateInfo == nil then
			return false, { Code = "MissingTemplateInfo", TemplateName = templateName }
		end

		local okApply, countOrErr = applyTemplate(
			templateInfo.Path,
			config.TemplateConfigFileName,
			config.TemplateSubmoduleFileName,
			fileSystemUtils,
			managedBlock
		)
		if not okApply then
			return false, countOrErr
		end

		local okSubmodules, submoduleResult = collectTemplateSubmodules(
			templateInfo.Path,
			config.TemplateSubmoduleFileName,
			fileSystemUtils
		)
		if not okSubmodules then
			return false, submoduleResult
		end

		for _, submodule in submoduleResult do
			local existingUrl = submoduleUrlByPath[submodule.Path]
			if existingUrl ~= nil then
				if existingUrl ~= submodule.Url then
					return false, {
						Code = "DuplicateSubmodulePath",
						Path = submodule.Path,
					}
				end
			else
				submoduleUrlByPath[submodule.Path] = submodule.Url
				table.insert(submodules, submodule)
			end
		end

		templateCounts[templateName] = countOrErr
		totalCount += countOrErr
	end

	return true, {
		TemplateNames = order,
		TemplateCounts = templateCounts,
		TotalCount = totalCount,
		Submodules = submodules,
	}
end

local Installer = {
	Install = install,
}

return Installer
