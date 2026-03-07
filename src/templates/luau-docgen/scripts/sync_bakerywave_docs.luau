--[[
	bakerywave luau-tags 문서를 스킬 레퍼런스로 동기화하는 스크립트입니다.
]]

local Process = require("@lune/process")

local SyncBakerywaveDocs = require("../../../modules/SyncBakerywaveDocs")

SyncBakerywaveDocs.Run({
	SkillName = "luau-docgen",
	GuideRelativePath = "website/docs/luau-tags",
	GuideLabel = "luau-tags",
})

Process.exit(0)
