--[[
	bakery-dev-handbook luau 문서를 스킬 레퍼런스로 동기화하는 스크립트입니다.
]]

local Process = require("@lune/process")

local SyncBakeryDevHandbookDocs = require("../../shared/scripts/sync_bakery_dev_handbook_docs")

SyncBakeryDevHandbookDocs.Run({
	SkillName = "luau-scripting",
	GuideRelativePath = "docs/luau",
	GuideLabel = "luau",
})

Process.exit(0)
