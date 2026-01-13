---
sidebar_label: Naming Style
---


# Naming Style

축약형, 약어 사용은 지양합니다. 특히 80자 폭 모니터 시절처럼 매우 짧은 변수명은 가독성을 해칩니다.

**PascalCase**:
Roblox API(서비스, 프로퍼티, 메서드, Enum 등)
클래스
타입
모듈에서 반환하는 객체
테이블의 속성
테이블의 함수
테이블의 메서드

**camelCase**:
지역 변수
지역 함수
객체의 private 멤버(접두사 `_` 포함, `_camelCase`)

**LOUD_SNAKE_CASE**:
상수(예: `MAX_SIZE`, `DEBUG_MODE`)

약어를 전부 대문자로 쓰지 않습니다. 예: `Json`, `Http`, `Id`.
단, **집합(Set)의 축약**인 `XYZ`, `RGB` 등은 대문자로 표기 가능합니다.

생성자(함수)는 주로 `camelCase`로 사용합니다. (예: `new()`, `fromRGB()`, `fromMatrix()`)

## 모듈 이름

모듈이 하나의 객체(테이블)를 반환한다면, 해당 객체(또는 테이블)의 이름과 모듈 파일 이름을 **일치**시킵니다.

모듈이 **단일 함수**만 반환한다면, 함수명을 `PascalCase`로 하고 모듈 파일 이름도 동일하게 합니다.

예시:

```lua
-- FooThing.luau
local FOO_THRESHOLD = 6

local FooThing = {}

FooThing.Constant = 5

function FooThing.Go()
	print("Foo Delta:", FooThing.Constant - FOO_THRESHOLD)
end

return FooThing
```


`PlayerData.PlayerDataServer` 대신 `PlayerData.Server`로 모듈을 구성할 수 있습니다.  
모듈 변수명은 `local PlayerDataServer = require(...)`처럼 표현해 맥락을 파악하기 쉽게 합니다.

모듈 파일 이름도 동일한 네이밍 규칙을 지켜야 하며, 상위 폴더가 이미 맥락을 제공한다면 파일 이름에서는 중복되는 접두사를 생략합니다. 예를 들어 `CameraModules/Manager.luau`가 `CameraManager` 객체를 반환하도록 구성하면 폴더 구조와 객체명이 함께 의미를 완성합니다. 테이블이나 반환 객체의 식별자는 충분히 길게 적어도 되지만, 파일 이름은 부모 폴더로부터 맥락을 상속받아 가능한 짧고 명확하게 유지합니다.

## 변수명
### 복수형

문법적으로 다소 어색해도 배열·딕셔너리 변수명 뒤에 `s` 또는 `es`를 붙여 복수임을 명시합니다. 예: `infos`, `datas`.


## 구분

**지역변수**
- 일반적으로 **camelCase**를 사용합니다.
- **PascalCase**는 Roblox 서비스나, 외부/내부 모듈을 require했을 때 그 반환값을 담는 변수명에 씁니다.
- 단, **외부(서드파티) 패키지**를 require할 때는 해당 패키지에서 요구하는 네이밍을 존중하기 위해 변수명을 패키지의 스타일에 맞춰 사용할 수 있습니다. 예를 들어 Vide 패키지가 소문자 `vide`를 기본으로 사용한다면 `local vide = require("@vide")`처럼 작성해도 됩니다. 이 예외는 외부 패키지에만 적용되며, Roblox 서비스나 내부 모듈에는 기본 규칙을 그대로 적용합니다.
- 속성값처럼, 그때 그때 변하는 값을 저장한 **지역 변수**는 **camelCase** 로 작성합니다. 여기서 말하는 속성은 Roblox 인스턴스의 `Value`와 같이 수시로 바뀌는 값으로, 앞단 "테이블의 속성" 항목에서 정의한 `PascalCase` 프로퍼티 규칙과는 별개입니다.

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")


local ObjectClass = require(ObjectModules.Class)

local player = Player.LocalPlayer
```

**상수**
- **LOUD_SNAKE_CASE**를 사용합니다.

```lua
local DEBUG_MODE = true
local MAX_SIZE = 2^16
```

## 테이블


### 배열
배열을 표기할 때는
`{요소이름}s` 혹은 `{요소이름}es` 로 합니다

배열의 배열을 표기할 때는
`{요소이름}Lists` 를 사용합니다.

### 딕셔너리

- 딕셔너리의 키는 **PascalCase** 로 씁니다

#### 키-값 쌍

Key-Value 관계를 표현할 때 `<Item>By<Key>` 를 사용합니다.
```lua
local characters = {} :: {Character}
local charactersByPlayer = {} :: {[Player]: Character}
    
local monsterInfos = {} :: {MonsterInfo}
local monsterInfosByMonsterId = {} :: {[MonsterId]: MonsterInfo}
```

##### 중첩 키-값 쌍 딕셔너리

키-값 쌍의 딕셔너리에서, 값이 키-값쌍 딕셔너리인 경우, 
`<Item>By<Key1>And<Key2>...` 를 사용합니다.

```lua
local easingsByStyleAndDirection = {} :: {
    [EasingStyle]: {
        [EasingDirection]: EasingFunction
    }
}

local bindingsByNameAndTypeAndInstance = {} :: {
    [string]: {
        [Type]: {
            [Instance]: Binding
        }
    }
}
```

    
### 집합

집합은 딕셔너리지만, 키만 필요하고, 값은 사용하지 않는 딕셔너리를 의미합니다
즉 키를 통해, 해당 딕셔너리에 있는지 없는지 정도만 확인하는 용도.

주로 `ClassSet: {[Class]: true} = {}` 로 선언합니다

`Set`을 접미사로 활용할 수 있습니다.

```lua
local PlayerSet: {[Player]: true} = {}

if PlayerSet[player] then
	print("플레이어가 있습니다.")
else
	print("플레이어가 없습니다.)
end

local function onPlayerRemoving(player: Player)
	PlayerSet[player] = nil
end
```


## 클래스


**차원**: 2D, 3D 등은 `GuiBase2d`, `GuiBase3d` 처럼 합니다


### 속성

#### Property, Attribute, CustomProperty 의 차이

세가지를 구분해서 사용합니다.

Property: 언제든 변경될 수 있는 값이며 기본적으로 내제되어 속성.
Attribute: 커스텀으로 추가된 상수값, 왠만해선 바뀌지 않는 속성.
CustomProperty: 언제든 변경될 수 있는 값이지만 기본적으로 내제되지 않아 커스텀으로 추가/제거될 수 있는 속성.

한글로 적을 때도 Property, Attribute, CustomProperty 를 작성 시
한국어에는 따로 대체할 수 있는 단어가 없음으로 영어 원문으로 작성합니다.


### 속성 적용용 변수명

#### Content / Id / Uri

Resource 를 가리키는 변수를 만들 때는 값의 형태를 접미사로 명시합니다.

- `Id`: 숫자 식별자(`number`). 예: `local imageId = 123456789`.
- `Uri`: 문자열 경로(`string`). 예: `local imageUri = "rbxassetid://123456789"`.
- `Content`: Roblox `Content` 타입. 어떤 생성 방식이든 `Content` 타입이면 모두 포함합니다. 예: `local imageContent = Content.fromId(12345678)`.

상수로 선언하면 기존 규칙에 따라 LOUD_SNAKE_CASE 를 적용합니다.

```lua
local IMAGE_ID = 123456789
local IMAGE_URI = "rbxassetid://123456789"
local IMAGE_CONTENT = Content.fromId(12345678)
```

이렇게 접미사를 맞춰 두면 함수 시그니처나 데이터 테이블에서 타입을 즉시 파악할 수 있습니다.


## 타입

### Enums

Enum의 각 키는 **PascalCase**를 사용합니다.

### 시그널 변수명

이벤트(`RBXScriptSignal`)를 변수로 받을 때는 접미사로 `Conn`을 붙여서 `touchedConn`처럼 사용하면 역할이 명확해집니다.


#### Updated vs Changed

- Roblox API에서 `Changed` 이벤트가 이미 많이 사용되고 있습니다만, 상황에 따라 `Updated`나 `Modified`를 쓰기도 합니다.
- 내부적으로는 `Updated`가 `Changed`보다 범위가 좀 더 한정적일 수 있으니, **이벤트의 의미**를 정확히 표현하도록 주의해주세요.

## 함수명

### 찾기 함수

- `GetSomethingByName`: `(self, name: string) -> (Something)`
- `FindSomethingByName`: `(self, name: string) -> (Something?)`

은 서로 다릅니다

Get 은 무조건 Something 을 반환하는 경우가 대부분이며, Something 을 찾을 수 없는 경우엔
```lua
return something or error(`Failed to find "{Name}".`)
```
이렇게 하는 경우가 대부분입니다

대신 Find 는 없을 수도 있으며, nil 이 될 수 있단 것을 알려줍니다
함수로 얻은 값의 `?` 여부를 확실하게 하기 위함입니다

#### By 와 From

- **From vs By**
    - `<A>From<B>`: B에서 A를 추출(이미 B가 A에 대한 정보를 가지는 경우)
    - `<A>By<B>`: A는 특정 컬렉션이며, B를 식별자로 사용하는 경우

By 는 딕셔너리에서 바로 캐시/인덱스할 수 있는 것
From 은 어딘가를 거치고 여러 계산을 통해서 찾는다는 의미가 강합니다


만약 플레이어와 캐릭터가 속성으로 연결되어있어서, 즉시 캐싱이나 찾기가 가능하다면
`FindCharacterByPlayer` 으로 지을 수 있고
플레이어와 캐릭터가 즉시 캐싱할 수 없는 구조, 캐릭터는 월드맵에 저장되고, 월드맵은 플레이어로부터 색인하는 복잡한 과정을 거친다면
`FindCharacterFromPlayer` 라고 지을 수 있습니다

### 매개변수

함수 옵션 매개변수는 `Options`
필수 매개변수는 `Params` 와 같은 식으로 구분 지으면 의도를 파악하기 좋습니다.

## 기타

- `Init` : 초기 실행 설정
- `Configure` : 매개변수를 받아 재구성
- `Start` : 메인 프로세스 실행
- `Stop` : 실행 중단

## 기타

- **개수**: `count` 사용, 인덱스는 `index` 사용. `number` 등 모호한 표현은 피합니다.
- **시간**: `Time` 접미사 사용(`UpdatedTime`, `CreatedTime`). `Date` 대신 `Time`이 명확합니다.
- **단위**: 초 단위라면 `Second`, 미터라면 `Meter`를 붙여 이름만으로 단위를 알 수 있게 합니다. 예: `delaySeconds`.
- **속성(Property) 네이밍**: Roblox API 스타일에 맞춰 `ClipsDescendants`, `CanCollide`, `IsVisible`처럼 **3인칭 동사 또는 상태**를 쓰는 편을 권장합니다.
- **이벤트(Event) 네이밍**: 보통 수동태(`Touched`, `Began`, `Changed`)를 사용합니다.  
    이벤트 콜백 함수를 만들 때도 `onTouched`, `onBegan` 등으로 의미를 명확히 합니다.
