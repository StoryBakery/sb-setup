--[[
	bakery-dev-handbook 문서를 스킬 레퍼런스로 동기화하는 공통 모듈입니다.
]]

local FileSystem = require("@lune/fs")
local Process = require("@lune/process")

local HANDBOOK_REPO_URL = "https://github.com/StoryBakery/bakery-dev-handbook"
local HANDBOOK_REF = "main"
local SKILL_GITIGNORE_RULE = "/references/bakery-dev-handbook/"

local function joinPath(a: string, b: string): string
	if a == "" or a == "." then
		return b
	end
	if b == "" or b == "." then
		return a
	end
	if a:sub(-1) == "/" then
		return a .. b
	end
	return a .. "/" .. b
end

local function getDirectoryName(path: string): string
	return (path:match("^(.*)/[^/]+$")) or ""
end

local function makeDirectoryRecursive(path: string)
	if path == "" or path == "." then
		return
	end
	if FileSystem.isDir(path) then
		return
	end

	local parentPath = getDirectoryName(path)
	if parentPath ~= "" and not FileSystem.isDir(parentPath) then
		makeDirectoryRecursive(parentPath)
	end

	local okWrite = pcall(function()
		FileSystem.writeDir(path)
	end)
	if not okWrite and not FileSystem.isDir(path) then
		FileSystem.writeDir(path)
	end
end

local function runGit(args: { string }, cwd: string?): (boolean, string)
	local options = { capture = true }
	if cwd ~= nil and cwd ~= "" then
		options.cwd = cwd
	end

	local okExec, resultOrErr = pcall(Process.exec, "git", args, options)
	if not okExec then
		return false, tostring(resultOrErr)
	end

	local result = resultOrErr
	if result.ok then
		return true, ""
	end

	local stderr = result.stderr or ""
	if stderr ~= "" then
		return false, stderr
	end

	local stdout = result.stdout or ""
	if stdout ~= "" then
		return false, stdout
	end

	return false, "unknown error"
end

local function hasGit(): boolean
	local okExec, resultOrErr = pcall(Process.exec, "git", { "--version" }, { capture = true })
	if not okExec then
		return false
	end

	local result = resultOrErr
	return result.ok == true
end

local function ensureSparseCheckoutPath(handbookRoot: string, guideRelativePath: string): boolean
	local okInit, initError = runGit({ "sparse-checkout", "init", "--cone" }, handbookRoot)
	if not okInit then
		print(`[Setup] Sparse-checkout is not available. Keeping current checkout: {initError}`)
		return false
	end

	local okSet, setError = runGit({ "sparse-checkout", "set", guideRelativePath }, handbookRoot)
	if not okSet then
		print(`[Setup] Failed to set sparse-checkout path "{guideRelativePath}": {setError}`)
		return false
	end

	return true
end

local function cloneHandbook(handbookRoot: string, guideRelativePath: string): (boolean, string)
	local parentDirectory = getDirectoryName(handbookRoot)
	if parentDirectory ~= "" then
		makeDirectoryRecursive(parentDirectory)
	end

	local okSparseClone, sparseCloneError = runGit({
		"clone",
		"--depth",
		"1",
		"--filter=blob:none",
		"--sparse",
		"--branch",
		HANDBOOK_REF,
		HANDBOOK_REPO_URL,
		handbookRoot,
	}, nil)
	if okSparseClone then
		local okSparseSet, sparseSetError =
			runGit({ "sparse-checkout", "set", guideRelativePath }, handbookRoot)
		if not okSparseSet then
			return false, sparseSetError
		end
		return true, ""
	end

	print(`[Setup] Sparse clone failed. Falling back to regular clone: {sparseCloneError}`)
	local okClone, cloneError = runGit({
		"clone",
		"--depth",
		"1",
		"--branch",
		HANDBOOK_REF,
		HANDBOOK_REPO_URL,
		handbookRoot,
	}, nil)
	if not okClone then
		return false, cloneError
	end

	ensureSparseCheckoutPath(handbookRoot, guideRelativePath)
	return true, ""
end

local function updateHandbook(handbookRoot: string, guideRelativePath: string): (boolean, string)
	ensureSparseCheckoutPath(handbookRoot, guideRelativePath)
	return runGit({ "pull", "--ff-only", "origin", HANDBOOK_REF }, handbookRoot)
end

local function ensureSkillGitignore(skillGitignorePath: string): boolean
	local parentDirectory = getDirectoryName(skillGitignorePath)
	if parentDirectory ~= "" then
		makeDirectoryRecursive(parentDirectory)
	end

	local content = ""
	if FileSystem.isFile(skillGitignorePath) then
		local okRead, contentOrErr = pcall(FileSystem.readFile, skillGitignorePath)
		if not okRead then
			print(`[Setup] Failed to read "{skillGitignorePath}": {tostring(contentOrErr)}`)
			return false
		end
		content = contentOrErr
	end

	if content:find(SKILL_GITIGNORE_RULE, 1, true) then
		return true
	end

	if content ~= "" and content:sub(-1) ~= "\n" then
		content ..= "\n"
	end
	content ..= SKILL_GITIGNORE_RULE .. "\n"

	local okWrite, writeErr = pcall(function()
		FileSystem.writeFile(skillGitignorePath, content)
	end)
	if not okWrite then
		print(`[Setup] Failed to write "{skillGitignorePath}": {tostring(writeErr)}`)
		return false
	end

	return true
end

local function run(options: { SkillName: string, GuideRelativePath: string, GuideLabel: string })
	local skillName = options.SkillName
	local guideRelativePath = options.GuideRelativePath
	local guideLabel = options.GuideLabel

	local handbookRoot = `.agents/skills/{skillName}/references/bakery-dev-handbook`
	local skillGitignorePath = `.agents/skills/{skillName}/.gitignore`
	local guideRoot = joinPath(handbookRoot, guideRelativePath)

	if not hasGit() then
		print("[Setup] Git is not available. Skipping bakery-dev-handbook sync.")
		return
	end

	if not ensureSkillGitignore(skillGitignorePath) then
		return
	end

	if FileSystem.isFile(handbookRoot) then
		print(`[Setup] Failed to sync bakery-dev-handbook. "{handbookRoot}" is a file.`)
		return
	end

	if FileSystem.isDir(handbookRoot) then
		if not FileSystem.isDir(joinPath(handbookRoot, ".git")) then
			print(
				`[Setup] Skipped bakery-dev-handbook sync. "{handbookRoot}" is not a Git repository.`
			)
			return
		end

		print("[Setup] Updating bakery-dev-handbook docs.")
		local okUpdate, updateError = updateHandbook(handbookRoot, guideRelativePath)
		if not okUpdate then
			print(`[Setup] Failed to update bakery-dev-handbook docs: {updateError}`)
			return
		end

		print("[Setup] Updated bakery-dev-handbook docs.")
	else
		print("[Setup] Cloning bakery-dev-handbook docs.")
		local okClone, cloneError = cloneHandbook(handbookRoot, guideRelativePath)
		if not okClone then
			print(`[Setup] Failed to clone bakery-dev-handbook docs: {cloneError}`)
			return
		end

		print("[Setup] Cloned bakery-dev-handbook docs.")
	end

	if FileSystem.isDir(guideRoot) then
		print(`[Setup] bakery-dev-handbook {guideLabel} references are ready.`)
	else
		print(
			`[Setup] bakery-dev-handbook repository is synced, but {guideLabel} docs were not found.`
		)
	end
end

return {
	Run = run,
}
