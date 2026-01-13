--[[
	Git 서브모듈을 추가하고 최신 상태로 맞추는 모듈입니다.
]]

local FileSystem = require("@lune/fs")
local Process = require("@lune/process")

local function trim(value: string): string
	return value:gsub("%s+$", "")
end

local function normalizePath(path: string): string
	return path:gsub("\\", "/")
end

local function hasGit(): boolean
	local okExec, resultOrErr = pcall(Process.exec, "git", { "--version" }, { capture = true })
	if not okExec then
		return false
	end

	local result = resultOrErr
	return result.ok
end

local function runGit(args: { string }): (boolean, string, string)
	local okExec, resultOrErr = pcall(Process.exec, "git", args, { capture = true })
	if not okExec then
		return false, "", tostring(resultOrErr)
	end

	local result = resultOrErr
	return result.ok, result.stdout or "", result.stderr or ""
end

local function isGitRepoRoot(): boolean
	return FileSystem.isDir(".git") or FileSystem.isFile(".git")
end

local function isGitRepo(path: string): boolean
	local ok, stdout = runGit({ "-C", path, "rev-parse", "--is-inside-work-tree" })
	if not ok then
		return false
	end
	return trim(stdout) == "true"
end

local function findSubmoduleNameByPath(path: string): string?
	local ok, stdout = runGit({
		"config",
		"-f",
		".gitmodules",
		"--get-regexp",
		"^submodule\\..*\\.path$",
	})
	if not ok then
		return nil
	end

	for line in stdout:gmatch("[^\r\n]+") do
		local key, value = line:match("^(%S+)%s+(.+)$")
		if key and value == path then
			local name = key:match("^submodule%.(.+)%.path$")
			if name then
				return name
			end
		end
	end

	return nil
end

local function getSubmoduleUrl(name: string): string?
	local ok, stdout = runGit({
		"config",
		"-f",
		".gitmodules",
		("submodule.%s.url"):format(name),
	})
	if not ok then
		return nil
	end
	return trim(stdout)
end

local function listSubmoduleEntries(): { [string]: string }
	local ok, stdout = runGit({
		"config",
		"-f",
		".gitmodules",
		"--get-regexp",
		"^submodule\\..*\\.path$",
	})
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

local function resolveSubmoduleName(path: string): string
	local normalizedPath = normalizePath(path)
	local baseName = deriveSubmoduleName(normalizedPath)
	local entries = listSubmoduleEntries()

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

local function hasSubmoduleGitDir(name: string): boolean
	return FileSystem.isDir(".git/modules/" .. name)
end

local function resolveRemoteHead(path: string): string?
	local okHead, head = runGit({ "-C", path, "rev-parse", "origin/HEAD" })
	if okHead then
		return trim(head)
	end

	local okMain, mainHead = runGit({ "-C", path, "rev-parse", "origin/main" })
	if okMain then
		return trim(mainHead)
	end

	local okMaster, masterHead = runGit({ "-C", path, "rev-parse", "origin/master" })
	if okMaster then
		return trim(masterHead)
	end

	return nil
end

local function ensureSubmodule(info, fileSystemUtils)
	if not hasGit() then
		return { IsOk = true, Status = "Skipped", Reason = "MissingGit" }
	end

	if not isGitRepoRoot() then
		return { IsOk = true, Status = "Skipped", Reason = "NotGitRepo" }
	end

	local parentDir = fileSystemUtils.GetDirectoryName(info.Path)
	if parentDir ~= "" then
		fileSystemUtils.MakeDirectoryRecursive(parentDir)
	end

	local existingName = findSubmoduleNameByPath(info.Path)
	local name = existingName or resolveSubmoduleName(info.Path)
	local added = false

	if not existingName then
		if FileSystem.isDir(info.Path) or FileSystem.isFile(info.Path) then
			if isGitRepo(info.Path) then
				local okAdd, _, err = runGit(buildSubmoduleAddArgs(name, info.Url, info.Path, true))
				if not okAdd then
					return { IsOk = false, Status = "GitFailed", Action = "SubmoduleAdd", Detail = err }
				end
				added = true
			else
				return { IsOk = false, Status = "PathConflict" }
			end
		else
			local forceAdd = hasSubmoduleGitDir(name)
			local okAdd, _, err = runGit(buildSubmoduleAddArgs(name, info.Url, info.Path, forceAdd))
			if not okAdd then
				return { IsOk = false, Status = "GitFailed", Action = "SubmoduleAdd", Detail = err }
			end
			added = true
		end
	end

	if not name then
		name = findSubmoduleNameByPath(info.Path)
	end

	if name then
		local currentUrl = getSubmoduleUrl(name)
		if currentUrl ~= nil and currentUrl ~= info.Url then
			local okSet, _, err = runGit({
				"config",
				"-f",
				".gitmodules",
				("submodule.%s.url"):format(name),
				info.Url,
			})
			if not okSet then
				return { IsOk = false, Status = "GitFailed", Action = "UpdateUrl", Detail = err }
			end
			runGit({ "submodule", "sync", "--", info.Path })
		end
	end

	if not FileSystem.isDir(info.Path) and not FileSystem.isFile(info.Path) then
		local okInit, _, err = runGit({ "submodule", "update", "--init", "--", info.Path })
		if not okInit then
			return { IsOk = false, Status = "GitFailed", Action = "SubmoduleInit", Detail = err }
		end
	end

	if not isGitRepo(info.Path) then
		return { IsOk = false, Status = "NotGitRepo" }
	end

	local okRemote, remoteUrl = runGit({ "-C", info.Path, "remote", "get-url", "origin" })
	if okRemote then
		remoteUrl = trim(remoteUrl)
		if remoteUrl ~= info.Url then
			local okSet, _, err = runGit({ "-C", info.Path, "remote", "set-url", "origin", info.Url })
			if not okSet then
				return { IsOk = false, Status = "GitFailed", Action = "SetOrigin", Detail = err }
			end
		end
	end

	local okFetch, _, fetchErr = runGit({ "-C", info.Path, "fetch", "origin", "--prune" })
	if not okFetch then
		return { IsOk = false, Status = "GitFailed", Action = "Fetch", Detail = fetchErr }
	end

	local okHead, head = runGit({ "-C", info.Path, "rev-parse", "HEAD" })
	local remoteHead = resolveRemoteHead(info.Path)
	if okHead and remoteHead ~= nil then
		head = trim(head)
		if head ~= remoteHead then
			local okCheckout, _, checkoutErr = runGit({ "-C", info.Path, "checkout", remoteHead })
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
