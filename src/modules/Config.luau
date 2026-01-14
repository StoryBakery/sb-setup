--[[
	템플릿 설정과 소스 경로, 서브모듈 정보를 관리하는 모듈입니다.
]]

local Config = {
	BaseTemplateName = "base",
	TemplatesRootName = "templates",
	ProjectTemplatesRootPath = "setup_configs/templates",
	ProjectConfigFileName = "bakery_project_configs.toml",
	TemplateConfigFileName = "template.toml",
	SourceCandidates = {
		"pkgs/setup_configs/src",
		".pesde/setup_configs/src",
		"src",
	},
	Submodule = {
		Path = "libs/bakery-dev-handbook",
		Url = "https://github.com/StoryBakery/bakery-dev-handbook",
	},
}

return Config
