--[[
	bakery-dev-handbook document 문서를 스킬 레퍼런스로 동기화하는 스크립트입니다.
]]

local Process = require("@lune/process")

local SyncBakeryDevHandbookDocs = require("../../shared/scripts/sync_bakery_dev_handbook_docs")

SyncBakeryDevHandbookDocs.Run({
	SkillName = "markdown-style",
	GuideRelativePath = "docs/document",
	GuideLabel = "document",
})

Process.exit(0)
