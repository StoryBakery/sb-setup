--[[
	Git 서브모듈을 추가하고 최신 상태로 맞추는 모듈입니다.
]]

local FileSystem = require("@lune/fs")
local Process = require("@lune/process")

local TemplateRoots = require("./TemplateRoots")

local function trim(value: string): string
	return value:gsub("%s+$", "")
end

local function normalizePath(path: string): string
	return path:gsub("\\", "/")
end

local function buildGitArgs(args: { string }, rootPath: string?): { string }
	if rootPath == nil or rootPath == "" then
		return args
	end

	local finalArgs = { "-C", rootPath }
	for _, arg in args do
		table.insert(finalArgs, arg)
	end

	return finalArgs
end

local function hasGit(): boolean
	local okExec, resultOrErr = pcall(Process.exec, "git", { "--version" }, { capture = true })
	if not okExec then
		return false
	end

	local result = resultOrErr
	return result.ok
end

local function runGit(args: { string }, rootPath: string?): (boolean, string, string)
	local finalArgs = buildGitArgs(args, rootPath)
	local okExec, resultOrErr = pcall(Process.exec, "git", finalArgs, { capture = true })
	if not okExec then
		return false, "", tostring(resultOrErr)
	end

	local result = resultOrErr
	return result.ok, result.stdout or "", result.stderr or ""
end

local function resolveGitRoot(startPath: string): string?
	if startPath == "" then
		startPath = "."
	end

	local ok, stdout = runGit({ "rev-parse", "--show-toplevel" }, startPath)
	if not ok then
		return nil
	end

	local root = trim(stdout)
	if root == "" then
		return nil
	end

	return normalizePath(root)
end

local function isGitRepo(path: string): boolean
	local ok, stdout = runGit({ "rev-parse", "--is-inside-work-tree" }, path)
	if not ok then
		return false
	end
	return trim(stdout) == "true"
end

local function findSubmoduleNameByPath(path: string, repoRoot: string): string?
	local ok, stdout = runGit({
		"config",
		"-f",
		".gitmodules",
		"--get-regexp",
		"^submodule\\..*\\.path$",
	}, repoRoot)
	if not ok then
		return nil
	end

	local normalizedPath = normalizePath(path)
	for line in stdout:gmatch("[^\r\n]+") do
		local key, value = line:match("^(%S+)%s+(.+)$")
		if key and value and normalizePath(value) == normalizedPath then
			local name = key:match("^submodule%.(.+)%.path$")
			if name then
				return name
			end
		end
	end

	return nil
end

local function getSubmoduleUrl(name: string, repoRoot: string): string?
	local ok, stdout = runGit({
		"config",
		"-f",
		".gitmodules",
		("submodule.%s.url"):format(name),
	}, repoRoot)
	if not ok then
		return nil
	end
	return trim(stdout)
end

local function listSubmoduleEntries(repoRoot: string): { [string]: string }
	local ok, stdout = runGit({
		"config",
		"-f",
		".gitmodules",
		"--get-regexp",
		"^submodule\\..*\\.path$",
	}, repoRoot)
	if not ok then
		return {}
	end

	local entries: { [string]: string } = {}
	for line in stdout:gmatch("[^\r\n]+") do
		local key, value = line:match("^(%S+)%s+(.+)$")
		if key and value then
			local name = key:match("^submodule%.(.+)%.path$")
			if name then
				entries[name] = value
			end
		end
	end

	return entries
end

local function deriveSubmoduleName(path: string): string
	local normalized = normalizePath(path)
	local cleaned = normalized:gsub("^%./", ""):gsub("/+$", "")
	local name = cleaned:match("([^/]+)$") or cleaned
	if name == nil or name == "" then
		return "submodule"
	end
	return name
end

local function resolveSubmoduleName(path: string, repoRoot: string): string
	local normalizedPath = normalizePath(path)
	local baseName = deriveSubmoduleName(normalizedPath)
	local entries = listSubmoduleEntries(repoRoot)

	local existingPath = entries[baseName]
	if existingPath == nil or normalizePath(existingPath) == normalizedPath then
		return baseName
	end

	local suffix = 2
	while true do
		local candidate = baseName .. "-" .. tostring(suffix)
		if entries[candidate] == nil then
			return candidate
		end
		suffix += 1
	end
end

local function buildSubmoduleAddArgs(
	name: string,
	url: string,
	path: string,
	force: boolean
): { string }
	local args = { "submodule", "add", "--name", name }
	if force then
		table.insert(args, "-f")
	end
	table.insert(args, url)
	table.insert(args, path)
	return args
end

local function hasSubmoduleGitDir(
	name: string,
	repoRoot: string,
	fileSystemUtils
): boolean
	local path = fileSystemUtils.JoinPath(repoRoot, ".git/modules/" .. name)
	return FileSystem.isDir(path)
end

local function resolveRemoteHead(path: string): string?
	local okHead, head = runGit({ "rev-parse", "origin/HEAD" }, path)
	if okHead then
		return trim(head)
	end

	local okMain, mainHead = runGit({ "rev-parse", "origin/main" }, path)
	if okMain then
		return trim(mainHead)
	end

	local okMaster, masterHead = runGit({ "rev-parse", "origin/master" }, path)
	if okMaster then
		return trim(masterHead)
	end

	return nil
end

local function ensureSubmodule(info, fileSystemUtils, configRoot: string?)
	if not hasGit() then
		return { IsOk = true, Status = "Skipped", Reason = "MissingGit" }
	end

	local rootBase = configRoot
	if rootBase == nil or rootBase == "" then
		rootBase = "."
	end

	local repoRoot = resolveGitRoot(rootBase)
	if repoRoot == nil then
		local okInit, _, initErr = runGit({ "init" }, rootBase)
		if not okInit then
			return { IsOk = false, Status = "GitFailed", Action = "InitRepo", Detail = initErr }
		end

		repoRoot = resolveGitRoot(rootBase)
		if repoRoot == nil then
			return {
				IsOk = false,
				Status = "GitFailed",
				Action = "ResolveRepo",
				Detail = "Failed to resolve Git root.",
			}
		end
	end

	local submodulePath = normalizePath(info.Path)
	local resolvedPath = submodulePath
	if not TemplateRoots.IsAbsolutePath(submodulePath) then
		resolvedPath = fileSystemUtils.JoinPath(repoRoot, submodulePath)
	end

	local parentDir = fileSystemUtils.GetDirectoryName(resolvedPath)
	if parentDir ~= "" then
		fileSystemUtils.MakeDirectoryRecursive(parentDir)
	end

	local existingName = findSubmoduleNameByPath(submodulePath, repoRoot)
	local name = existingName or resolveSubmoduleName(submodulePath, repoRoot)
	local added = false

	if not existingName then
		if FileSystem.isDir(resolvedPath) or FileSystem.isFile(resolvedPath) then
			if isGitRepo(resolvedPath) then
				local okAdd, _, err = runGit(
					buildSubmoduleAddArgs(name, info.Url, submodulePath, true),
					repoRoot
				)
				if not okAdd then
					return { IsOk = false, Status = "GitFailed", Action = "SubmoduleAdd", Detail = err }
				end
				added = true
			else
				return { IsOk = false, Status = "PathConflict" }
			end
		else
			local forceAdd = hasSubmoduleGitDir(name, repoRoot, fileSystemUtils)
			local okAdd, _, err = runGit(
				buildSubmoduleAddArgs(name, info.Url, submodulePath, forceAdd),
				repoRoot
			)
			if not okAdd then
				return { IsOk = false, Status = "GitFailed", Action = "SubmoduleAdd", Detail = err }
			end
			added = true
		end
	end

	if not name then
		name = findSubmoduleNameByPath(submodulePath, repoRoot)
	end

	if name then
		local currentUrl = getSubmoduleUrl(name, repoRoot)
		if currentUrl ~= nil and currentUrl ~= info.Url then
			local okSet, _, err = runGit({
				"config",
				"-f",
				".gitmodules",
				("submodule.%s.url"):format(name),
				info.Url,
			}, repoRoot)
			if not okSet then
				return { IsOk = false, Status = "GitFailed", Action = "UpdateUrl", Detail = err }
			end
			runGit({ "submodule", "sync", "--", submodulePath }, repoRoot)
		end
	end

	if not FileSystem.isDir(resolvedPath) and not FileSystem.isFile(resolvedPath) then
		local okInit, _, err = runGit(
			{ "submodule", "update", "--init", "--", submodulePath },
			repoRoot
		)
		if not okInit then
			return { IsOk = false, Status = "GitFailed", Action = "SubmoduleInit", Detail = err }
		end
	end

	if not isGitRepo(resolvedPath) then
		return { IsOk = false, Status = "NotGitRepo" }
	end

	local okRemote, remoteUrl = runGit(
		{ "remote", "get-url", "origin" },
		resolvedPath
	)
	if okRemote then
		remoteUrl = trim(remoteUrl)
		if remoteUrl ~= info.Url then
			local okSet, _, err = runGit(
				{ "remote", "set-url", "origin", info.Url },
				resolvedPath
			)
			if not okSet then
				return { IsOk = false, Status = "GitFailed", Action = "SetOrigin", Detail = err }
			end
		end
	end

	local okFetch, _, fetchErr = runGit({ "fetch", "origin", "--prune" }, resolvedPath)
	if not okFetch then
		return { IsOk = false, Status = "GitFailed", Action = "Fetch", Detail = fetchErr }
	end

	local okHead, head = runGit({ "rev-parse", "HEAD" }, resolvedPath)
	local remoteHead = resolveRemoteHead(resolvedPath)
	if okHead and remoteHead ~= nil then
		head = trim(head)
		if head ~= remoteHead then
			local okCheckout, _, checkoutErr = runGit(
				{ "checkout", remoteHead },
				resolvedPath
			)
			if not okCheckout then
				return { IsOk = false, Status = "GitFailed", Action = "Checkout", Detail = checkoutErr }
			end
			return { IsOk = true, Status = "Updated", IsAdded = added }
		end
	end

	if added then
		return { IsOk = true, Status = "Added" }
	end

	return { IsOk = true, Status = "Ok" }
end

local Submodule = {
	Ensure = ensureSubmodule,
}

return Submodule
