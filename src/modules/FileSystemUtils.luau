--[[
	파일 시스템 유틸리티를 제공하는 모듈입니다.
]]

local FileSystem = require("@lune/fs")

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

local function makeDirectoryRecursive(dir: string)
	if dir == "" or dir == "." then
		return
	end
	if not FileSystem.isDir(dir) then
		local parent = getDirectoryName(dir)
		if parent ~= "" and not FileSystem.isDir(parent) then
			makeDirectoryRecursive(parent)
		end
		local ok = pcall(function()
			FileSystem.writeDir(dir)
		end)
		if not ok and not FileSystem.isDir(dir) then
			FileSystem.writeDir(dir)
		end
	end
end

local function ensureParentDirectory(path: string)
	local parent = getDirectoryName(path)
	if parent ~= "" then
		makeDirectoryRecursive(parent)
	end
end

local function copyFile(src: string, dst: string)
	ensureParentDirectory(dst)
	local ok = pcall(function()
		FileSystem.copy(src, dst, { overwrite = true })
	end)
	if not ok then
		FileSystem.writeFile(dst, FileSystem.readFile(src))
	end
end

local function collectFiles(root: string)
	local collected = {}

	local function walk(dir: string, relBase: string)
		local ok, entries = pcall(FileSystem.readDir, dir)
		if not ok or entries == nil then
			return
		end

		for _, entry in entries do
			local abs = joinPath(dir, entry)
			local rel = joinPath(relBase, entry)

			if FileSystem.isDir(abs) then
				walk(abs, rel)
			elseif FileSystem.isFile(abs) then
				table.insert(collected, { SourcePath = abs, RelativePath = rel })
			end
		end
	end

	walk(root, "")
	return collected
end

local function exists(path: string): boolean
	return FileSystem.isDir(path) or FileSystem.isFile(path)
end

local FileSystemUtils = {
	JoinPath = joinPath,
	GetDirectoryName = getDirectoryName,
	MakeDirectoryRecursive = makeDirectoryRecursive,
	EnsureParentDirectory = ensureParentDirectory,
	CopyFile = copyFile,
	CollectFiles = collectFiles,
	Exists = exists,
}

return FileSystemUtils
