<!-- BEGIN STORY BAKERY MANAGED BLOCK: sb.agents.extra [mode=append] -->
# 검증 워크플로우

모든 코드 수정이 끝나면 아래 순서를 지켜서 검증합니다.
AGENT 는 변경사항이 위 검증 항목과 관련이 있으면 어떤 경우에도 검증 절차를 생략하지 않습니다.
검증 중 오류가 발생하면 직접 원인을 파악하고 수정한 뒤, 동일한 검증 명령을 다시 실행해야합니다.
1. `lune run CheckSyntax` 를 실행하고 실패하면 작업을 중단한 뒤 에러를 고칩니다.
2. 문서/문서 주석 관련 변경, API 문서 주석 작성이 있다면 `lune run BuildDocs` 를 실행합니다. (`BuildDocs` 실행 시 금지 태그 검사도 자동 수행됩니다.)

CI 파이프라인에서도 위와 동일한 명령을 동일한 순서로 실행하도록 반드시 구성합니다.
<!-- END STORY BAKERY MANAGED BLOCK: sb.agents.extra -->
