--[[
	매직패턴 블록을 병합하는 모듈입니다.
]]

local function trim(value: string): string
	return value:match("^%s*(.-)%s*$")
end

local function splitLines(text: string): { string }
	local normalized = text:gsub("\r\n", "\n")
	normalized = normalized:gsub("\r", "\n")
	if normalized == "" then
		return {}
	end

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

local function parseMarker(line: string, marker: string): (string?, string?)
	local tag = marker .. " STORY BAKERY MANAGED BLOCK:"
	local startIndex = line:find(tag, 1, true)
	if not startIndex then
		return nil, nil
	end

	local rest = line:sub(startIndex + #tag)
	rest = trim(rest)
	rest = rest:gsub("%s*-->%s*$", "")
	rest = rest:gsub("%s*%*/%s*$", "")
	rest = trim(rest)

	local blockId = rest
	local mode = nil
	local bracketStart = rest:find("%[")
	if bracketStart then
		local bracketEnd = rest:find("]", bracketStart, true)
		if bracketEnd then
			blockId = trim(rest:sub(1, bracketStart - 1))
			local modePart = rest:sub(bracketStart + 1, bracketEnd - 1)
			mode = modePart:match("mode%s*=%s*(%w+)")
		end
	end

	blockId = trim(blockId)
	if blockId == "" then
		return nil, nil
	end

	return blockId, mode
end

local function parseBlocks(lines: { string })
	local blocksById: { [string]: any } = {}
	local order: { string } = {}
	local index = 1

	while index <= #lines do
		local startLine = lines[index]
		local blockId, mode = parseMarker(startLine, "BEGIN")
		if blockId then
			local contentLines: { string } = {}
			local endIndex = nil
			local scanIndex = index + 1

			while scanIndex <= #lines do
				local endId = parseMarker(lines[scanIndex], "END")
				if endId == blockId then
					endIndex = scanIndex
					break
				end
				table.insert(contentLines, lines[scanIndex])
				scanIndex += 1
			end

			if endIndex then
				if blocksById[blockId] == nil then
					blocksById[blockId] = {
						Id = blockId,
						StartIndex = index,
						EndIndex = endIndex,
						StartLine = startLine,
						EndLine = lines[endIndex],
						Lines = contentLines,
						Mode = mode,
					}
					table.insert(order, blockId)
				end
				index = endIndex + 1
			else
				index += 1
			end
		else
			index += 1
		end
	end

	return blocksById, order
end

local function endsWithLines(source: { string }, suffix: { string }): boolean
	if #suffix == 0 then
		return true
	end
	if #source < #suffix then
		return false
	end

	local offset = #source - #suffix
	for i = 1, #suffix do
		if source[offset + i] ~= suffix[i] then
			return false
		end
	end

	return true
end

local function parseTemplate(text: string)
	local lines = splitLines(text)
	local blocksById, order = parseBlocks(lines)
	return {
		Lines = lines,
		Blocks = blocksById,
		Order = order,
		HasBlocks = #order > 0,
	}
end

local function merge(destinationText: string, templateInfo)
	local destinationLines = splitLines(destinationText)
	local destinationBlocks, _ = parseBlocks(destinationLines)

	local updates: { [string]: any } = {}
	for _, blockId in templateInfo.Order do
		local templateBlock = templateInfo.Blocks[blockId]
		local mode = templateBlock.Mode
		if mode ~= "append" and mode ~= "remove" then
			mode = "replace"
		end

		local destinationBlock = destinationBlocks[blockId]
		if mode == "remove" then
			if destinationBlock then
				updates[blockId] = { Action = "remove" }
			end
		elseif destinationBlock then
			local mergedLines: { string } = {}
			if mode == "append" then
				if endsWithLines(destinationBlock.Lines, templateBlock.Lines) then
					mergedLines = destinationBlock.Lines
				else
					for _, line in destinationBlock.Lines do
						table.insert(mergedLines, line)
					end
					for _, line in templateBlock.Lines do
						table.insert(mergedLines, line)
					end
				end
			else
				mergedLines = templateBlock.Lines
			end

			updates[blockId] = {
				Action = "update",
				Lines = mergedLines,
			}
		else
			updates[blockId] = {
				Action = "insert",
				Lines = templateBlock.Lines,
				StartLine = templateBlock.StartLine,
				EndLine = templateBlock.EndLine,
			}
		end
	end

	local blocksByStartIndex: { [number]: any } = {}
	for _, block in destinationBlocks do
		blocksByStartIndex[block.StartIndex] = block
	end

	local mergedLines: { string } = {}
	local index = 1
	while index <= #destinationLines do
		local block = blocksByStartIndex[index]
		if block then
			local update = updates[block.Id]
			if update and update.Action == "remove" then
				index = block.EndIndex + 1
			else
				local contentLines = block.Lines
				if update and update.Action == "update" then
					contentLines = update.Lines
				end

				table.insert(mergedLines, block.StartLine)
				for _, line in contentLines do
					table.insert(mergedLines, line)
				end
				table.insert(mergedLines, block.EndLine)
				index = block.EndIndex + 1
			end
		else
			table.insert(mergedLines, destinationLines[index])
			index += 1
		end
	end

	for _, blockId in templateInfo.Order do
		local update = updates[blockId]
		if update and update.Action == "insert" then
			table.insert(mergedLines, update.StartLine)
			for _, line in update.Lines do
				table.insert(mergedLines, line)
			end
			table.insert(mergedLines, update.EndLine)
		end
	end

	return table.concat(mergedLines, "\n")
end

local ManagedBlock = {
	ParseTemplate = parseTemplate,
	Merge = merge,
}

return ManagedBlock
