---
id: scripting-guide
sidebar_label: Scripting Overview
---

# Scripting Overview

Story-Bakery 스크립팅 프레임워크는 그룹 전반의 코드 일관성과 유지보수성을 보장하기 위한 규칙 모음입니다. 모든 개발자는 여기서 정의한 기본 원칙을 토대로 게임 별 요구사항을 확장해야 하며, 새로운 스크립트를 작성하기 전 본 문서를 통해 세부 가이드의 목적을 먼저 파악해야 합니다.

스크립팅 가이드군은 파일 구조, 주석 방식, 네이밍, 객체지향 설계, 실행 컨텍스트 관리 등 프로젝트 전반에 적용되는 코딩 습관을 명문화합니다. 각 문서는 서로 연결되어 있으므로, 특정 규칙을 추가하거나 예외를 정의하기 전에 연관된 문서를 함께 확인하십시오.

- [code-style](./code-style.md)는 기본 파일 구성, 문자열 작성 방식, 지역 변수 선언 순서 등 전반적인 코드 스타일 규약을 정리합니다.
- [require-style](./require-style.md)는 Require 블록 우선순위, alias 선택, 외부 라이브러리 별칭 규칙을 세부적으로 설명하므로 새 스크립트를 작성하기 전에 반드시 한 번 이상 정독해야 합니다.
- [naming-style](./naming-style.md)는 클래스, 메서드, 인스턴스 속성 등 요소 별 네이밍 규칙과 접두사/접미사 사용 기준을 제공합니다.
- [object-oriented-style](./object-oriented-style.md)는 모듈 간 책임 분리, 상속과 조합 사용 원칙, 객체 생명주기 관리 패턴을 안내합니다.
- [document-based-comment](./document-based-comment.md)는 주석 기반 문서화 흐름과 API 문서 주석 작성 규칙을 설명합니다.
- [vide-component-design](../vide/component-design.md)는 Vide 컴포넌트의 상속/조합 선택 기준과 설계 원칙을 요약합니다.
- [ui-style](../ui-style.md)은 UI가 따라야 하는 시각적 제약과 상호작용 기본값을 정의하여, 스크립트가 UI 상태를 변경할 때 지켜야 할 기준을 제공합니다.
- [vide-component-documentation](../vide/component-documentation.md)는 videKit 컴포넌트의 문서 주석 작성 흐름과 `@tag vide` 적용 규칙을 명시합니다.
 - [vide-story-modules](../vide/story-modules.md)는 UILabs를 사용한 Vide 스토리 파일 작성 규칙과 예시를 제공합니다.
