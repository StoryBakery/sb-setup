--[[
	단순 TOML 설정을 파싱하는 모듈입니다.
]]

local FileSystem = require("@lune/fs")

local function trim(value: string): string
	return value:match("^%s*(.-)%s*$")
end

local function stripComments(line: string): string
	local inString = false
	local escaped = false
	for i = 1, #line do
		local ch = line:sub(i, i)
		if escaped then
			escaped = false
		elseif ch == "\\" then
			escaped = true
		elseif ch == "\"" then
			inString = not inString
		elseif ch == "#" and not inString then
			return line:sub(1, i - 1)
		end
	end
	return line
end

local function unescapeString(value: string): string
	local unescaped = value:gsub("\\\"", "\"")
	unescaped = unescaped:gsub("\\\\", "\\")
	return unescaped
end

local function parseString(value: string): (boolean, string?)
	local inner = value:match('^"(.*)"$')
	if inner == nil then
		return false, nil
	end
	return true, unescapeString(inner)
end

local function parseStringArray(value: string): (boolean, { string }?)
	local body = value:match("^%[(.*)%]$")
	if body == nil then
		return false, nil
	end

	local items: { string } = {}
	for item in body:gmatch('"(.-)"') do
		table.insert(items, unescapeString(item))
	end

	if #items == 0 and trim(body) ~= "" then
		return false, nil
	end

	return true, items
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

local function parseLine(line: string): (boolean, string?, any?)
	local key, value = line:match("^([%w%-%_]+)%s*=%s*(.+)$")
	if key == nil or value == nil then
		return false, nil, nil
	end

	local okString, parsedString = parseString(value)
	if okString then
		return true, key, parsedString
	end

	local okArray, parsedArray = parseStringArray(value)
	if okArray then
		return true, key, parsedArray
	end

	return false, nil, nil
end

local function parse(text: string): (boolean, { [string]: any } | { [string]: any })
	local data: { [string]: any } = {}
	local lines = splitLines(text)
	local currentArrayKey: string? = nil
	local currentArrayEntry: { [string]: any }? = nil

	for lineNumber, line in lines do
		local stripped = trim(stripComments(line))
		if stripped ~= "" then
			local arrayKey = stripped:match("^%[%[(.+)%]%]$")
			if arrayKey then
				arrayKey = trim(arrayKey)
				if arrayKey == "" then
					return false, {
						Code = "ParseError",
						Line = lineNumber,
						LineText = line,
					}
				end

				local list = data[arrayKey]
				if list == nil then
					list = {}
					data[arrayKey] = list
				end

				if type(list) ~= "table" then
					return false, {
						Code = "ParseError",
						Line = lineNumber,
						LineText = line,
					}
				end

				local entry = {}
				table.insert(list, entry)
				currentArrayKey = arrayKey
				currentArrayEntry = entry
			else
				local ok, key, value = parseLine(stripped)
				if not ok or key == nil then
					return false, {
						Code = "ParseError",
						Line = lineNumber,
						LineText = line,
					}
				end

				if currentArrayKey and currentArrayEntry then
					currentArrayEntry[key] = value
				else
					data[key] = value
				end
			end
		end
	end

	return true, data
end

local function readFile(path: string): (boolean, { [string]: any } | { [string]: any })
	if not FileSystem.isFile(path) then
		return false, { Code = "MissingFile", Path = path }
	end

	local okRead, contentOrErr = pcall(FileSystem.readFile, path)
	if not okRead then
		return false, {
			Code = "ReadFailed",
			Path = path,
			Detail = tostring(contentOrErr),
		}
	end

	return parse(contentOrErr)
end

local TomlParser = {
	Parse = parse,
	ReadFile = readFile,
}

return TomlParser
