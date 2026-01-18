--[[
	템플릿 설정과 소스 경로, 템플릿 서브모듈 파일 이름을 관리하는 모듈입니다.
]]

local Config = {
	BaseTemplateName = "base",
	TemplatesRootName = "templates",
	ProjectTemplatesRootCandidates = {
		"setup_configs/templates",
		"bakery_setup_project_configs/templates",
	},
	ProjectConfigFileName = "bakery_project_configs.toml",
	TemplateConfigFileName = "template.toml",
	TemplateSubmoduleFileName = "template.gitmodules",
	SourceCandidates = {
		"pkgs/setup_configs/src",
		".pesde/setup_configs/src",
		"pkgs/bakery_setup_project_configs/src",
		".pesde/bakery_setup_project_configs/src",
		"src",
	},
}

return Config
