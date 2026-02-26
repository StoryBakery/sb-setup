--[[
	템플릿 기반 설정 파일을 설치하는 모듈입니다.
]]

local FileSystem = require("@lune/fs")

local TemplateRoots = require("./TemplateRoots")

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

local function normalizePath(path: string): string
	return path:gsub("\\", "/")
end

local function isPathInsideRoot(path: string, root: string): boolean
	local normalizedPath = normalizePath(path):gsub("/+$", "")
	local normalizedRoot = normalizePath(root):gsub("/+$", "")
	if normalizedPath == normalizedRoot then
		return true
	end
	return normalizedPath:sub(1, #normalizedRoot + 1) == normalizedRoot .. "/"
end

local function normalizeSubmoduleRootPath(value: any): string?
	if type(value) ~= "string" or value == "" then
		return nil
	end

	local normalized = normalizePath(value)
	normalized = normalized:gsub("/+$", "")
	if normalized == "" then
		return nil
	end

	return normalized
end

local function resolveSubmoduleRootPath(value: any, configRoot: string): string?
	local normalized = normalizeSubmoduleRootPath(value)
	if normalized == nil then
		return nil
	end

	if TemplateRoots.IsAbsolutePath(normalized) then
		local configRootNormalized = normalizePath(configRoot)
		configRootNormalized = configRootNormalized:gsub("/+$", "")
		if configRootNormalized == "" then
			return nil
		end
		if normalized:sub(1, #configRootNormalized) == configRootNormalized then
			local remainder = normalized:sub(#configRootNormalized + 1)
			remainder = remainder:gsub("^/+", "")
			if remainder == "" then
				return nil
			end
			return remainder
		end
		return nil
	end

	return normalized
end

local function applySubmoduleRootPath(path: string, rootPath: string?): string
	if rootPath == nil or rootPath == "" then
		return path
	end
	if TemplateRoots.IsAbsolutePath(path) then
		return path
	end

	local normalizedPath = normalizePath(path)
	local normalizedRoot = normalizePath(rootPath):gsub("/+$", "")
	if normalizedRoot == "" then
		return path
	end

	if normalizedPath == "libs" then
		return normalizedRoot
	end

	local prefix = "libs/"
	if normalizedPath:sub(1, #prefix) == prefix then
		local remainder = normalizedPath:sub(#prefix + 1)
		if normalizedRoot == "." then
			return remainder
		end
		return normalizedRoot .. "/" .. remainder
	end

	return path
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
	if type(templates) ~= "table" then
		return false, { Code = "MissingTemplates", Path = configPath }
	end

	local templateRefs: { [number]: { [string]: any } } = {}
	if #templates == 0 then
		return true, {
			Templates = templateRefs,
			SubmoduleRootPath = if type(result.SubmoduleRootPath) == "string" and result.SubmoduleRootPath ~= ""
				then result.SubmoduleRootPath
				else nil,
		}
	end

	local firstEntry = templates[1]
	local firstType = type(firstEntry)

	if firstType == "string" then
		for index, name in templates do
			if type(name) ~= "string" or name == "" then
				return false, { Code = "InvalidTemplateEntry", Index = index, Path = configPath }
			end
			table.insert(templateRefs, { Name = name, EnableScripts = true })
		end
	elseif firstType == "table" then
		for index, entry in templates do
			if type(entry) == "string" then
				if entry == "" then
					return false, { Code = "InvalidTemplateEntry", Index = index, Path = configPath }
				end
				table.insert(templateRefs, { Name = entry, EnableScripts = true })
			else
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

				local enableScripts = entry.EnableScripts
				if enableScripts ~= nil and type(enableScripts) ~= "boolean" then
					return false, { Code = "InvalidTemplateEnableScripts", Index = index, Path = configPath }
				end

				if enableScripts == nil then
					enableScripts = true
				end

				table.insert(templateRefs, {
					Name = name,
					Source = source,
					EnableScripts = enableScripts,
				})
			end
		end
	else
		return false, { Code = "InvalidTemplateEntry", Index = 1, Path = configPath }
	end

	local submoduleRootPath = result.SubmoduleRootPath
	if type(submoduleRootPath) ~= "string" or submoduleRootPath == "" then
		submoduleRootPath = nil
	end

	return true, {
		Templates = templateRefs,
		SubmoduleRootPath = submoduleRootPath,
	}
end

local function normalizeRequestedTemplates(
	requestedTemplates: { [number]: { [string]: any } },
	baseTemplateName: string
): { [number]: { [string]: any } }
	local normalizedTemplates: { [number]: { [string]: any } } = {}
	local baseTemplateRef = nil

	for _, templateRef in requestedTemplates do
		if templateRef.Name == baseTemplateName then
			if baseTemplateRef == nil then
				baseTemplateRef = templateRef
			end
		end
	end

	if baseTemplateRef == nil then
		baseTemplateRef = {
			Name = baseTemplateName,
			EnableScripts = true,
		}
	end

	table.insert(normalizedTemplates, baseTemplateRef)

	for _, templateRef in requestedTemplates do
		if templateRef.Name ~= baseTemplateName then
			table.insert(normalizedTemplates, templateRef)
		end
	end

	return normalizedTemplates
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
		local availableTemplates = TemplateRoots.ListTemplateNames(
			roots,
			fileSystemUtils,
			templateConfigFileName
		)
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

	local description = result.Description
	if type(description) ~= "string" then
		description = ""
	end

	return true, {
		Name = name,
		Extends = extends,
		Description = description,
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
	templatePesdeFileName: string,
	templateScriptsFileName: string,
	scriptExcludeSet: { [string]: boolean },
	fileSystemUtils
)
	local files = fileSystemUtils.CollectFiles(root)
	local filtered: { any } = {}
	for _, item in files do
		local isScriptAsset = scriptExcludeSet[item.RelativePath] == true

		if item.RelativePath ~= templateConfigFileName
			and item.RelativePath ~= templateSubmoduleFileName
			and item.RelativePath ~= templatePesdeFileName
			and item.RelativePath ~= templateScriptsFileName
			and not isScriptAsset then
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

local function appendPesdePackagesFromList(
	results: { [number]: { [string]: any } },
	packages,
	pesdePath: string,
	defaultDev: boolean,
	defaultPeer: boolean
)
	if packages == nil then
		return true, nil
	end
	if type(packages) ~= "table" then
		return false, { Code = "InvalidTemplatePesde", Path = pesdePath }
	end

	local firstEntry = packages[1]
	if firstEntry == nil then
		return true, nil
	end

	local firstType = type(firstEntry)
	if firstType == "string" then
		for index, entry in packages do
			if type(entry) ~= "string" or entry == "" then
				return false, {
					Code = "InvalidTemplatePesdeEntry",
					Path = pesdePath,
					Index = index,
				}
			end
			table.insert(results, {
				Spec = entry,
				Dev = defaultDev,
				Peer = defaultPeer,
				Target = nil,
			})
		end
		return true, nil
	end

	if firstType ~= "table" then
		return false, { Code = "InvalidTemplatePesde", Path = pesdePath }
	end

	for index, entry in packages do
		if type(entry) ~= "table" then
			return false, {
				Code = "InvalidTemplatePesdeEntry",
				Path = pesdePath,
				Index = index,
			}
		end

		local spec = entry.Spec or entry.Package or entry.Url
		if type(spec) ~= "string" or spec == "" then
			return false, {
				Code = "InvalidTemplatePesdeEntry",
				Path = pesdePath,
				Index = index,
			}
		end

		local devValue = entry.Dev
		if devValue ~= nil and type(devValue) ~= "boolean" then
			return false, {
				Code = "InvalidTemplatePesdeEntry",
				Path = pesdePath,
				Index = index,
			}
		end

		local peerValue = entry.Peer
		if peerValue ~= nil and type(peerValue) ~= "boolean" then
			return false, {
				Code = "InvalidTemplatePesdeEntry",
				Path = pesdePath,
				Index = index,
			}
		end

		local targetValue = entry.Target
		if targetValue ~= nil and (type(targetValue) ~= "string" or targetValue == "") then
			return false, {
				Code = "InvalidTemplatePesdeEntry",
				Path = pesdePath,
				Index = index,
			}
		end

		table.insert(results, {
			Spec = spec,
			Dev = if devValue == nil then defaultDev else devValue,
			Peer = if peerValue == nil then defaultPeer else peerValue,
			Target = targetValue,
		})
	end

	return true, nil
end

local function collectTemplatePesdePackages(
	templateRoot: string,
	templatePesdeFileName: string,
	tomlParser,
	fileSystemUtils
)
	if templatePesdeFileName == "" then
		return true, {}
	end

	local pesdePath = fileSystemUtils.JoinPath(templateRoot, templatePesdeFileName)
	if not FileSystem.isFile(pesdePath) then
		return true, {}
	end

	local okRead, result = tomlParser.ReadFile(pesdePath)
	if not okRead then
		if result.Code == "MissingFile" then
			return true, {}
		end
		if result.Code == "ParseError" then
			return false, {
				Code = "TemplatePesdeParseFailed",
				Path = pesdePath,
				Line = result.Line,
				LineText = result.LineText,
			}
		end
		return false, {
			Code = "TemplatePesdeReadFailed",
			Path = pesdePath,
			Detail = result.Detail or "",
		}
	end

	local results: { [number]: { [string]: any } } = {}
	local okAppend, appendError = appendPesdePackagesFromList(
		results,
		result.Packages,
		pesdePath,
		false,
		false
	)
	if not okAppend then
		return false, appendError
	end

	okAppend, appendError = appendPesdePackagesFromList(
		results,
		result.DevPackages,
		pesdePath,
		true,
		false
	)
	if not okAppend then
		return false, appendError
	end

	okAppend, appendError = appendPesdePackagesFromList(
		results,
		result.PeerPackages,
		pesdePath,
		false,
		true
	)
	if not okAppend then
		return false, appendError
	end

	return true, results
end

local function collectTemplateScripts(
	templateRoot: string,
	templateScriptsFileName: string,
	tomlParser,
	fileSystemUtils
)
	if templateScriptsFileName == "" then
		return true, {}
	end

	local scriptsPath = fileSystemUtils.JoinPath(templateRoot, templateScriptsFileName)
	if not FileSystem.isFile(scriptsPath) then
		return true, {}
	end

	local okRead, result = tomlParser.ReadFile(scriptsPath)
	if not okRead then
		if result.Code == "MissingFile" then
			return true, {}
		end
		if result.Code == "ParseError" then
			return false, {
				Code = "TemplateScriptsParseFailed",
				Path = scriptsPath,
				Line = result.Line,
				LineText = result.LineText,
			}
		end
		return false, {
			Code = "TemplateScriptsReadFailed",
			Path = scriptsPath,
			Detail = result.Detail or "",
		}
	end

	local scripts = result.Scripts
	if scripts == nil then
		return true, {}
	end
	if type(scripts) ~= "table" then
		return false, { Code = "InvalidTemplateScripts", Path = scriptsPath }
	end

	local results: { [number]: { [string]: any } } = {}
	for index, entry in scripts do
		if type(entry) ~= "table" then
			return false, {
				Code = "InvalidTemplateScriptEntry",
				Path = scriptsPath,
				Index = index,
			}
		end

		local scriptType = entry.Type
		if scriptType == nil or scriptType == "" then
			if entry.Script ~= nil then
				scriptType = "Lune"
			elseif entry.Command ~= nil then
				scriptType = "Command"
			end
		end
		if type(scriptType) ~= "string" or scriptType == "" then
			return false, {
				Code = "MissingTemplateScriptType",
				Path = scriptsPath,
				Index = index,
			}
		end

		local normalizedType = scriptType:lower()
		local typeValue = nil
		if normalizedType == "lune" then
			typeValue = "Lune"
		elseif normalizedType == "command" then
			typeValue = "Command"
		else
			return false, {
				Code = "InvalidTemplateScriptType",
				Path = scriptsPath,
				Index = index,
				Type = scriptType,
			}
		end

		local command = entry.Command
		local scriptPath = entry.Script
		if typeValue == "Command" then
			if type(command) ~= "string" or command == "" then
				return false, {
					Code = "MissingTemplateScriptCommand",
					Path = scriptsPath,
					Index = index,
				}
			end
		elseif typeValue == "Lune" then
			if type(scriptPath) ~= "string" or scriptPath == "" then
				return false, {
					Code = "MissingTemplateScriptPath",
					Path = scriptsPath,
					Index = index,
				}
			end
		end

		local args = entry.Args
		if args == nil then
			args = {}
		elseif type(args) ~= "table" then
			return false, {
				Code = "InvalidTemplateScriptArgs",
				Path = scriptsPath,
				Index = index,
			}
		else
			for argIndex, argValue in args do
				if type(argValue) ~= "string" or argValue == "" then
					return false, {
						Code = "InvalidTemplateScriptArg",
						Path = scriptsPath,
						Index = index,
						ArgIndex = argIndex,
						ArgValue = argValue,
					}
				end
			end
		end

		local rootValue = entry.Root
		if rootValue == nil or rootValue == "" then
			rootValue = "Project"
		end
		if type(rootValue) ~= "string" then
			return false, {
				Code = "InvalidTemplateScriptRoot",
				Path = scriptsPath,
				Index = index,
			}
		end

		local normalizedRoot = rootValue:lower()
		local rootType = nil
		if normalizedRoot == "project" then
			rootType = "Project"
		elseif normalizedRoot == "template" then
			rootType = "Template"
		else
			return false, {
				Code = "InvalidTemplateScriptRoot",
				Path = scriptsPath,
				Index = index,
				Root = rootValue,
			}
		end

		local scriptRootValue = entry.ScriptRoot
		if scriptRootValue == nil or scriptRootValue == "" then
			if typeValue == "Lune" then
				scriptRootValue = "Template"
			else
				scriptRootValue = rootType
			end
		end
		if type(scriptRootValue) ~= "string" then
			return false, {
				Code = "InvalidTemplateScriptRoot",
				Path = scriptsPath,
				Index = index,
			}
		end

		local normalizedScriptRoot = scriptRootValue:lower()
		local scriptRootType = nil
		if normalizedScriptRoot == "project" then
			scriptRootType = "Project"
		elseif normalizedScriptRoot == "template" then
			scriptRootType = "Template"
		else
			return false, {
				Code = "InvalidTemplateScriptRoot",
				Path = scriptsPath,
				Index = index,
				Root = scriptRootValue,
			}
		end

		local orderValue = entry.Order
		local orderNumber = nil
		if orderValue ~= nil then
			if type(orderValue) ~= "string" or orderValue == "" then
				return false, {
					Code = "InvalidTemplateScriptOrder",
					Path = scriptsPath,
					Index = index,
				}
			end
			orderNumber = tonumber(orderValue)
			if orderNumber == nil then
				return false, {
					Code = "InvalidTemplateScriptOrder",
					Path = scriptsPath,
					Index = index,
				}
			end
		end

		local nameValue = entry.Name
		if nameValue ~= nil and (type(nameValue) ~= "string" or nameValue == "") then
			return false, {
				Code = "InvalidTemplateScriptName",
				Path = scriptsPath,
				Index = index,
			}
		end

		local cwdValue = entry.Cwd
		if cwdValue ~= nil and (type(cwdValue) ~= "string" or cwdValue == "") then
			return false, {
				Code = "InvalidTemplateScriptCwd",
				Path = scriptsPath,
				Index = index,
			}
		end

		table.insert(results, {
			Type = typeValue,
			Command = command,
			Script = scriptPath,
			Args = args,
			Root = rootType,
			ScriptRoot = scriptRootType,
			Order = orderNumber,
			Name = nameValue,
			Cwd = cwdValue,
		})
	end

	return true, results
end

local function resolveDestinationPath(relativePath: string, templateGitignoreFileName: string): string
	if relativePath == templateGitignoreFileName then
		return ".gitignore"
	end
	return relativePath
end

local function applyTemplate(
	templateRoot: string,
	templateConfigFileName: string,
	templateSubmoduleFileName: string,
	templatePesdeFileName: string,
	templateScriptsFileName: string,
	templateGitignoreFileName: string,
	scriptExcludeSet: { [string]: boolean },
	fileSystemUtils,
	managedBlock
)
	local files = collectTemplateFiles(
		templateRoot,
		templateConfigFileName,
		templateSubmoduleFileName,
		templatePesdeFileName,
		templateScriptsFileName,
		scriptExcludeSet,
		fileSystemUtils
	)
	local appliedCount = 0

	for _, item in files do
		local okRead, templateContent = readFile(item.SourcePath)
		if not okRead or templateContent == nil then
			return false, { Code = "ReadTemplateFailed", Path = item.SourcePath }
		end

		local templateInfo = managedBlock.ParseTemplate(templateContent)
		local destinationPath = resolveDestinationPath(
			item.RelativePath,
			templateGitignoreFileName
		)

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

local function install(config, fileSystemUtils, tomlParser, managedBlock, installOptions)
	local projectConfigPath = config.ProjectConfigFileName
	local configRoot = TemplateRoots.ResolveConfigRoot(projectConfigPath, fileSystemUtils)

	local requestedTemplates = nil
	local submoduleRootPath = nil
	if installOptions ~= nil and type(installOptions.RequestedTemplates) == "table" then
		requestedTemplates = installOptions.RequestedTemplates
		submoduleRootPath = resolveSubmoduleRootPath(installOptions.SubmoduleRootPath, configRoot)
	else
		local okProject, projectResult = readProjectConfig(projectConfigPath, tomlParser)
		if not okProject then
			return false, projectResult
		end

		requestedTemplates = projectResult.Templates
		submoduleRootPath = resolveSubmoduleRootPath(
			projectResult.SubmoduleRootPath,
			configRoot
		)
	end

	if type(requestedTemplates) ~= "table" then
		return false, { Code = "MissingTemplates", Path = projectConfigPath }
	end

	requestedTemplates = normalizeRequestedTemplates(requestedTemplates, config.BaseTemplateName)

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
	local pesdePackages: { [number]: { [string]: any } } = {}
	local pesdePackagesBySpec: { [string]: { [string]: any } } = {}
	local scripts: { [number]: { [string]: any } } = {}
	local order = resolvedResult.Order
	local infos = resolvedResult.Infos
	local scriptsEnabledByTemplateName: { [string]: boolean } = {}

	for _, templateRef in requestedTemplates do
		local templateName = templateRef.Name
		local enableScripts = templateRef.EnableScripts
		if enableScripts == false then
			scriptsEnabledByTemplateName[templateName] = false
		elseif scriptsEnabledByTemplateName[templateName] == nil then
			scriptsEnabledByTemplateName[templateName] = true
		end
	end

	for orderIndex, templateName in order do
		local templateInfo = infos[templateName]
		if templateInfo == nil then
			return false, { Code = "MissingTemplateInfo", TemplateName = templateName }
		end

		local scriptsEnabled = scriptsEnabledByTemplateName[templateName]
		if scriptsEnabled == nil then
			scriptsEnabled = true
		end

		local okScripts, scriptsResult = collectTemplateScripts(
			templateInfo.Path,
			config.TemplateScriptsFileName,
			tomlParser,
			fileSystemUtils
		)
		if not okScripts then
			return false, scriptsResult
		end

		local scriptExcludeSet: { [string]: boolean } = {}
		for _, script in scriptsResult do
			if script.Type == "Lune" and script.ScriptRoot == "Template" then
				local scriptPath = script.Script
				if scriptPath ~= nil and not TemplateRoots.IsAbsolutePath(scriptPath) then
					local normalized = normalizePath(scriptPath):gsub("^%./", "")
					scriptExcludeSet[normalized] = true
				end
			end
		end

		local okApply, countOrErr = applyTemplate(
			templateInfo.Path,
			config.TemplateConfigFileName,
			config.TemplateSubmoduleFileName,
			config.TemplatePesdeFileName,
			config.TemplateScriptsFileName,
			config.TemplateGitignoreFileName,
			scriptExcludeSet,
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
			local resolvedPath = applySubmoduleRootPath(submodule.Path, submoduleRootPath)
			local resolvedSubmodule = { Path = resolvedPath, Url = submodule.Url }

			local existingUrl = submoduleUrlByPath[resolvedSubmodule.Path]
			if existingUrl ~= nil then
				if existingUrl ~= resolvedSubmodule.Url then
					return false, {
						Code = "DuplicateSubmodulePath",
						Path = resolvedSubmodule.Path,
					}
				end
			else
				submoduleUrlByPath[resolvedSubmodule.Path] = resolvedSubmodule.Url
				table.insert(submodules, resolvedSubmodule)
			end
		end

		local okPesde, pesdeResult = collectTemplatePesdePackages(
			templateInfo.Path,
			config.TemplatePesdeFileName,
			tomlParser,
			fileSystemUtils
		)
		if not okPesde then
			return false, pesdeResult
		end

		for _, packageEntry in pesdeResult do
			local spec = packageEntry.Spec
			local existing = pesdePackagesBySpec[spec]
			if existing ~= nil then
				existing.Dev = existing.Dev or packageEntry.Dev
				existing.Peer = existing.Peer or packageEntry.Peer
				if existing.Target == nil then
					existing.Target = packageEntry.Target
				elseif packageEntry.Target ~= nil and existing.Target ~= packageEntry.Target then
					return false, {
						Code = "DuplicatePesdeTarget",
						Spec = spec,
						Target = existing.Target,
						OtherTarget = packageEntry.Target,
					}
				end
			else
				local entry = {
					Spec = spec,
					Dev = packageEntry.Dev == true,
					Peer = packageEntry.Peer == true,
					Target = packageEntry.Target,
				}
				pesdePackagesBySpec[spec] = entry
				table.insert(pesdePackages, entry)
			end
		end

		if scriptsEnabled then
			for scriptIndex, script in scriptsResult do
				script.TemplateName = templateName
				script.TemplateRoot = templateInfo.Path
				script.TemplateIndex = orderIndex
				script.ScriptIndex = scriptIndex
				if script.Order == nil then
					script.SortOrder = orderIndex * 1000 + scriptIndex
				else
					script.SortOrder = script.Order
				end
				table.insert(scripts, script)
			end
		end

		templateCounts[templateName] = countOrErr
		totalCount += countOrErr
	end

	if #scripts > 1 then
		table.sort(scripts, function(a, b)
			if a.SortOrder ~= b.SortOrder then
				return a.SortOrder < b.SortOrder
			end
			if a.TemplateIndex ~= b.TemplateIndex then
				return a.TemplateIndex < b.TemplateIndex
			end
			return a.ScriptIndex < b.ScriptIndex
		end)
	end

	return true, {
		TemplateNames = order,
		TemplateCounts = templateCounts,
		TotalCount = totalCount,
		Submodules = submodules,
		PesdePackages = pesdePackages,
		Scripts = scripts,
	}
end

local function listTemplates(config, fileSystemUtils, tomlParser)
	local projectConfigPath = config.ProjectConfigFileName
	local configRoot = TemplateRoots.ResolveConfigRoot(projectConfigPath, fileSystemUtils)

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

	local roots: { string } = {}
	if hasProjectTemplatesRoot then
		table.insert(roots, projectTemplatesRoot)
	end
	if packageTemplatesRoot ~= nil then
		table.insert(roots, packageTemplatesRoot)
	end

	local names = TemplateRoots.ListTemplateNames(
		roots,
		fileSystemUtils,
		config.TemplateConfigFileName
	)
	local templates: { [number]: { [string]: any } } = {}

	for _, name in names do
		local okTemplate, templateInfo = loadTemplateConfig(
			name,
			nil,
			configRoot,
			if hasProjectTemplatesRoot then projectTemplatesRoot else nil,
			packageTemplatesRoot,
			config.TemplateConfigFileName,
			tomlParser,
			fileSystemUtils
		)
		if not okTemplate then
			return false, templateInfo
		end

		local sourceLabel = "package"
		if hasProjectTemplatesRoot and isPathInsideRoot(templateInfo.Path, projectTemplatesRoot) then
			sourceLabel = "project"
		end

		table.insert(templates, {
			Name = templateInfo.Name,
			Description = templateInfo.Description,
			Extends = templateInfo.Extends,
			Path = templateInfo.Path,
			Source = sourceLabel,
		})
	end

	return true, {
		Templates = templates,
		TemplateRoots = roots,
	}
end

local Installer = {
	Install = install,
	ListTemplates = listTemplates,
}

return Installer
