--[[
	프로젝트 Luau 파일의 문법을 검사하는 스크립트입니다.
]]

local FileSystem = require("@lune/fs")
local Process = require("@lune/process")

local FileSystemUtils = require("./src/modules/FileSystemUtils")

local function shouldSkipDir(name: string): boolean
	local skipDirs = {
		[".git"] = true,
		[".github"] = true,
		[".pesde"] = true,
		[".vscode"] = true,
		["build"] = true,
		["lune_packages"] = true,
		["luau_packages"] = true,
		["node_modules"] = true,
		["out"] = true,
		["pesde"] = true,
		["roblox_packages"] = true,
		["tests"] = false,
		[".tmp"] = true,
	}
	return skipDirs[name] == true
end

local function collectLuauFiles(root: string, fileSystemUtils): { string }
	local files: { string } = {}

	local function walk(dir: string)
		local ok, entries = pcall(FileSystem.readDir, dir)
		if not ok or entries == nil then
			return
		end

		for _, entry in entries do
			local path = fileSystemUtils.JoinPath(dir, entry)
			if FileSystem.isDir(path) then
				if not shouldSkipDir(entry) then
					walk(path)
				end
			elseif FileSystem.isFile(path) and entry:match("%.luau$") then
				table.insert(files, path)
			end
		end
	end

	walk(root)
	return files
end

local function getLoader()
	if loadstring ~= nil then
		return loadstring
	end
	if load ~= nil then
		return load
	end
	return nil
end

local function checkSyntax(path: string, loader): (boolean, string?)
	local okRead, contentOrErr = pcall(FileSystem.readFile, path)
	if not okRead then
		return false, tostring(contentOrErr)
	end

	local chunk, err = loader(contentOrErr, "@" .. path)
	if chunk == nil then
		return false, err or "Unknown syntax error."
	end

	return true, nil
end

local loader = getLoader()
if loader == nil then
	print("[Error] No Lua loader available for syntax checks.")
	Process.exit(1)
end

local files = collectLuauFiles(".", FileSystemUtils)
if #files == 0 then
	print("[CheckSyntax] No Luau files found.")
	Process.exit(0)
end

local errors = 0
for _, path in files do
	local ok, err = checkSyntax(path, loader)
	if not ok then
		errors += 1
		print(`[CheckSyntax] Failed: {path}`)
		print(`[CheckSyntax] Error: {err}`)
	end
end

if errors > 0 then
	print(`[CheckSyntax] Total errors: {errors}`)
	Process.exit(1)
end

print(`[CheckSyntax] OK ({#files} files).`)
Process.exit(0)
