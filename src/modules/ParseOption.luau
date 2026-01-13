--[[
	옵션 인자를 파싱하는 모듈입니다.
]]

local Process = require("@lune/process")

local function ParseOption(defaultOptionName: string): string
	local optionName = defaultOptionName
	local i = 1
	while i <= #Process.args do
		local arg = Process.args[i]
		if arg == "--option" or arg == "-o" then
			i += 1
			if Process.args[i] and Process.args[i] ~= "" then
				optionName = Process.args[i]
			end
		end
		i += 1
	end
	return optionName
end

return ParseOption
