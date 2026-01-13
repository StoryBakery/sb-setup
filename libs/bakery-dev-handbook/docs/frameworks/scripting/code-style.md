---
sidebar_label: Code Style
---

# Code Style 

이 문서는:
Roblox 공식 문서([Roblox Lua Style Guide](https://roblox.github.io/lua-style-guide/))를 참고합니다.

본 문서는 팀 내에서 코드 리뷰와 협업 시 발생할 수 있는 스타일 관련 논쟁을 최소화하고, 읽기 좋은 코드를 작성하기 위한 원칙을 안내합니다. 
빠른 작성보다는 **읽기 쉽고 유지 보수하기 좋은 코드** 작성에 집중해주세요.



## 스크립트

모든 스크립트 파일은 `.luau` 확장자를 사용해야 합니다.

### 코드 순서

코드는 아래 항목들을 **가능한 경우** 다음 순서대로 포함합니다. 
항목이 필요 없다면 생략합니다.

0. 주석 지시어
파일 최상단에 `--!native`, `--!nolint` 등과 같은 주석 지시어를 둡니다.

`--!strict` 는 적지 않습니다, `--!nonstrict` 가 기본이기 때문.

1. 코드 설명 블록 주석

해당 파일이 존재하는 이유나 기능을 간단히 설명합니다, 생략 가능.
파일명, 작성자, 날짜 등의 메타 정보는 버전 관리 시스템에서 충분히 파악 가능하므로 기재하지 않습니다.

만약 API 문서로 작성할 경우, 문서 주석으로 작성합니다.
자세한 것은 [주석 기반 문서](document-based-comment.md) 참고.


2. 서비스
`game:GetService("...")` 호출부를 모아서 적습니다.

예시:
```lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
```

3. Require
Require 블록의 순서, alias 사용법, 별칭 정리는 [require-style](./require-style.md) 문서에서 세부적으로 정의합니다. 외부 패키지 → 공통 조상 → 내부 모듈 순으로 블록을 구성하고, 모든 경로는 문자열 literal alias 를 사용한 뒤 상수와 함수를 선언합니다.

4. 상수

5. 변수와 함수

6. 현재 모듈이 반환하는 오브젝트

7. Return
최종적으로 이 스크립트(모듈)가 반환할 값(테이블, 함수, 클래스 등).

### RunContext

`LocalScript`와 `Script`를 굳이 폴더나 구조 상으로 구분하기보다는, 
`Script`의 `RunContext`를 활용해 동일한 폴더(혹은 패키지) 내에서 관리하기를 권장합니다.
이렇게 하면 스크립트 파일의 수가 불필요하게 늘어나지 않고, 프로젝트 구조가 단순해집니다.

## 모듈 스크립트

- 종속성을 정적으로 만들기 위해, 일반적으로 스크립트의 맨 위에서 `require` 문을 모두 선언합니다.
- 모듈의 이름을 해당 변수의 이름과 동일하게 맞추는 것이 권장됩니다.

### require

Require 블록 구성, 정렬, 외부 라이브러리 별칭 규칙은 [require-style](./require-style.md) 문서에서 전부 관리합니다. 이 문서에서는 해당 규칙을 따라 파일 상단에 모든 `require` 호출을 모으고, 별칭 블록 이후에만 일반 지역 상수나 변수를 선언한다는 점을 기억하세요.

### 패키지 구조

- **패키지**는 외부에서 소비될 API를 정의하는 모듈입니다.
- 일반적으로 **최상위 레벨 테이블**이 여러 모듈을 require한 후, 이들을 모아서 최종적으로 반환합니다.
- 소비자 입장에서는 최상위 패키지만 require하고, 필요한 서브 모듈을 패키지 객체에서 꺼내 쓰는 방식을 선호합니다.

```lua
-- 패키지 내부 (예: MyLibrary/Foo.luau)
local MyLibrary = script.Parent
local MyModule = require("./MyModule")
...
return Foo

-- 패키지를 사용하는 곳
local MyLibrary = require("@Some/MyLibrary")
local MyModule = require("@Some/MyLibrary/MyModule")
```

## 코드

### 인덴트

인덴트는 **Space** 가 아닌, 무조건 **Tab** 으로 처리해야합니다.
Tab 간격은 **4칸**을 사용합니다.

### 줄당 글자 수

코드 라인은 **최대 100자**를 권장합니다. 
주석은 80자 이내로 쓰면 가독성이 올라갑니다.


### 정렬
수평 정렬은 유지 보수를 어렵게 만들고 diff를 복잡하게 하므로 지양합니다.

```lua
-- Good:
local frobulator = 132
local grog = 17

-- Bad:
local frobulator = 132
local grog       =  17
```

### 줄넘김
**빈 줄**을 적절히 사용하여 코드를 블록별로 구분합니다. 
다만 블록 시작 부분에 바로 빈 줄을 넣지는 않습니다.

```lua
local Foo = require("./Common/Foo")

local function gargle()
    -- gargle gargle
end

Foo.frobulate()
Foo.frobulate()

Foo.munge()
```

## 구문
한 줄에 구문은 **하나만** 작성합니다.  
`if state then return end` 같은 구문도 가급적 줄바꿈하여 가독성을 높입니다.
```lua
-- Good:
if state then 
	return 
end

-- Bad:
if state then return end
```


---

## if 문

`if` 문에서 한줄 코드는 자제합니다.
```lua
-- Bad:
if isActive then onActive() end

-- Good
if isActive then
	onActive()
end
```

조건이 길면 각 조건마다 탭을 넣어 가독성을 높입니다.

여러 `if ~ elseif ~ else` 구조라면, `then`과 `else`를 새 줄에 배치하여 가독성을 높입니다.

### 상세하고 보기 좋은 조건

변수명을 이용해 조건이 무얼 의미하는지 더 명확하게 합니다.
```lua
-- Bad:
if cond1 and cond2 and cond3 and cond4 then
    doSomething()
end

-- Good
local shouldDoSomething = cond1 and cond2 and cond3 and cond4
if shouldDoSomething then
    doSomething()
end
```

### if-then-else 표현식 사용

if-then-else 표현식은 다음과 같은 구조를 가집니다.
```lua
local object = if hasObjectId
	then Object.GetFromId(objectId)
	else Object.create()
```

`if-then-else` 표현식에서 3줄을 초과하는 경우 일반 `if ~ else` 문을 쓰는 것이 좋습니다.
 
큰 테이블이나 함수 호출 결과를 한 줄에서 3항처럼 사용해야 할 때는 예외적으로 `if` 표현식을 쓰기도 하지만, 너무 길면 **도움 변수**를 만드는 편이 낫습니다.
 
`if` 표현식에서 `elseif`도 지원하나, 과도한 중첩은 피해주세요.

### 삼항 연산자 사용 금지
*삼항 연산자*는 사용하지 않습니다.
```lua
-- Bad:
local value = condition and a or b 

-- Good:
local value = if condition
	then a
	else b
```

이유는 a 가 `nil` 인 경우, 위의 삼항 연산자는 b 가 되고, if-then-else 표현식에선 a 가 됩니다.
거의 대부분 a 가 되는 것이 맞는 동작.

## 테이블

`pairs` 나 `ipairs` 는 사용하지 않습니다.
```lua
for key, value in t do
	doSomething(key, value)
end
```
`for key, value in t do` 나 `for index, value in t` 를 사용합니다.

변수명은 자율적으로 설정하고, 최선의 이름은 각기 다르지만
이름이 크게 설정되지 않은 경우에는 (그냥 아무런 명확한 키-값 타입이 없는 테이블을 돌리는 경우)
딕셔너리는 `key, value` 혹은 `k, v` 로 하고
배열은 `index, value` 혹은 `i, v` 로 해서, 딕셔너리인지 배열인지 드러냅니다.


### 후행콤마

테이블 항목마다 **끝에 콤마**를 남겨두면, 이후 항목 추가 시 diff를 간결하게 유지할 수 있습니다.


### 테이블에서 공백

- 테이블 정의 시 여는 중괄호 `{`를 **새로운 줄에 두지 않도록** 합니다.
- 인라인 테이블 혹은 함수가 너무 길면 여러 줄로 나눕니다.
- 너무 긴 키-값 구조는 **서브테이블**로 분리하는 것이 좋습니다. 그래야 diff가 깔끔해집니다.
- 테이블 리터럴만 사용하는 경우, vide 엘리먼트 선언처럼 한 줄에서 인라인으로 사용 가능하나, 변수와 섞여 있으면 지양합니다.

## 함수

함수 선언 시 `function` 키워드로 시작하고, 모듈 바깥(Non-member) 함수는 가급적 `local` 함수로 작성합니다.

```lua
-- 선호
local function isFrozen()
    -- ...
end

-- 모듈 내 함수
function module.IsFrozen()
    -- ...
end
```

특정 조건에 따라 다른 버전의 함수를 정의해야 하는 경우, `local function`을 정의 후 원하는 위치에서 할당하거나 조건부로 교체합니다.

### 매개변수

함수의 **매개변수 개수는 1~2개** 정도가 가장 적절합니다. 너무 많으면 가독성이 떨어집니다.

많이 필요하다면, 혹은 앞으로의 확장성(매개변수가 많아질 가능성)을 고려한다면, `Params` 나 `Options` 를 만듭시다.
`params: {Prefix}Params` 를 주로 작성합니다.

적용 범위와 예외:
- 위 권장은 외부에서 호출되는 공개 API 함수나 객체의 메서드에 우선 적용합니다.
- 모듈 내부에서만 사용하는 지역 함수(헬퍼)는 맥락상 필요한 경우 여러 매개변수, ~7개를 허용합니다.
- 다만 서명이 장황해져 호출부 가독성이 떨어지거나, 동일한 인자 군을 반복 전달한다면 `Params`/`Options` 딕셔너리로 묶는 것을 고려합니다.


#### Dictionary Keys
`Params` 같은 딕셔너리 설정 맵을 작성할 때는 서열 위치 효과를 참고합니다.
딕셔너리 설정 맵에서 가장 눈에 잘 띄어야하는 것들은 가장 위, 아래에 두고
세부 설정들은 중간에 둡니다.

```lua
{
	Crucial1 = 1,
	Important1 = 2,
	LessImportant1 = 3,
	NotImportant1 = 4,
	NotImportant2 = 5,
	NotImportant3 = 6,
	LessImpotant2 = 7,
	Important2 = 8,
	Crucial2 = 9,
}
```

단 선언해야할 키가 4~5 개 정도라면, 중요한 것부터 위로 둡니다.

또한 키가 여러개라면, 보기 쉽게 비슷한 종류 끼리 묶어줍니다
DynamicTween 을 예시로하면 이런 순서로 작성합니다
```lua
local tween = DynamicTween.new({
	-- 중요한 애니메이션 움직임
	Duration = 0.5,
	EasingStyle = "Sine",
	EasingDirection = "Out",

	-- StepEvent 는 마이너한 설정, 또한 묶을 대상도 크게 없음
	StepEvent = RunService.RenderStepped,
	
	-- 애니메이션 반복 설정, 상대적으로 마이너한 설정
	RepeatCount = -1,
	Reverses = true,
	DelayTime = 0.5,
	
	-- 중요한 콜백함수와 그에 대한 시작 및 끝 값
	Start = vector.create(100, 50, 1000),
	Goal = vector.create(50, 1000, 100),
	Callback = function(new) -- 콜백 함수가 가장 중요하기에, 마지막에 둡니다
		partSizeNode:SetValue(new)
	end,
})
```

### 함수 주석

```lua
-- 함수 주석 
local function fn()
	-- ...
end
```

주석 앵커와 함께하는 경우
다음 포맷으로 작성합니다.
```lua
-- 속성의 값을 구합니다.
function Object:GetProperty(property: number)
```

함수의 이름만으로 왜 이 함수가 사용되는지, 존재하는지 설명하기 어려울 때, 
moonwave 를 통한 API 문서 주석 작성일 때만, 함수 주석을 작성합니다.

그 외는 함수 의 이름으로 최대한 행동을 예측할 수 있도록 작성합니다.

## 타입

### Luau 타입 확장

Luau 구조체 타입을 상속처럼 조합할 때는 **교집합(`&`)** 으로 계층을 표현합니다.

**가장 구체적인 타입(Child) → 가장 추상적인 타입(Ancestor)** 순으로 나열해 덮어쓰기 우선순위를 명시합니다.

```lua
type AncestorProps = {
	Size: UDim2,
}

type ParentProps = {
	Size: UDim2,
	ColorStyle: "Primary" | "Secondary",
}

type ChildProps = {
	ColorStyle: "Primary",
}

export type ButtonProps =
	ChildProps
	& ParentProps
	& AncestorProps
```

### 외부 타입 참조

외부 라이브러리에서 제공하는 타입을 사용할 때는 별도의 지역 타입을 다시 만들지 않습니다.
```lua
-- Bad:
type Maid = Maid.Maid
type InstanceAddedSignal = Signal.AddedSignal<Instance>
type Component = Component.Component

export type Object = setmetatable<{
    Maid: Maid,
    Signal: InstanceAddedSignal,
    Component: Component,
}, typeof(Object)>

-- Good:
-- 별도의 복잡한 타입이 없으면 따로 정의하지 않고, 기존 모듈로부터 그대로 가져옵니다
-- 기존 모듈에서 타입 이름이나 제너릭을 바꿀 때도 수정이 용이해집니다 

export type Object = setmetatable<{
    Maid: Maid.Maid,
    Signal: Signal.AddedSignal<Instance>,
    Component: Component.Component,
}, typeof(Object)>
```
 
`Maid.Maid`, `Signal.Signal` 처럼 모듈 이름과 타입 이름을 함께 적어 어떤 패키지의 타입인지 바로 알 수 있도록 명시합니다.  
여러 타입을 총괄해 재노출하는 인터페이스 모듈(최종 타입 집합)의 역할을 맡았을 때만 
내부 type 를 불러와서 export 합니다.

## 주석

3줄 이하의 주석은 `--` 를 사용합니다
여러 줄에 걸친 주석은 블록 주석(`--[[ ... ]]`)을 사용합니다.

문서 블록 주석은 moonwave 의 `--[=[ ... ]=]` 를 사용합니다.
1줄 이하의 API 문서 주석은 `---` 를 사용합니다.
자세한 moonwave API 작성법은 [document-based-comment](./document-based-comment.md) 를 참고하세요.


### 블록 주석
파일 맨 위에 삽입하여 해당 파일의 용도를 설명합니다.
함수, 모듈, 클래스의 의도를 작성할 때도 사용합니다.

API 문서 주석이 아닌 경우 **무조건** `--[[]]` 패턴을 사용합니다.
```lua
--[[
    이 블록 주석이 기본
]]
```

```lua
--[=[
    @class Test
    
    문서 주석에만 `--[=[` 패턴을 사용한다.
]=]
```

### 주석의 의의
주석은 **"무엇"** 을 하는지보다 **"왜 이렇게 작성했는지"** 를 설명하는 데 초점을 둡니다.
```lua
-- Bad:
-- 오브젝트 ObjectId를 저장하고 value의 TypeId, value 를 저장합니다
bufBuilder:WriteUInt32(objectId)
bufBuilder:WriteUInt16(valueTypeInfoId)
bufBuilder:WriteType(valueTypeInfo, value)

-- Good:
-- Object의 값에 대한 valueTypeInfo 의 Id 를 저장해야,
-- 역직렬화시 타입이 무엇인지 유추할 수 있습니다
bufBuilder:WriteUInt32(objectId)
bufBuilder:WriteUInt16(valueTypeInfoId)
bufBuilder:WriteType(valueTypeInfo, value)
```

큰 파일을 쪼개려 섹션 주석(`--- VARIABLES ---`, `------`)을 사용하는 것은 지양합니다.
필요한 경우 [주석-region](#주석-region) 으로 작성하거나, 파일을 작게 쪼개거나 블록 주석으로 구분하세요.

변수명으로 주석의 의미를 대체할 수 있다면, 너무 장황한 주석 대신 가독성 좋은 이름을 사용합니다.
```lua
-- Bad:
-- 해당 변수는 Object 를 키로, 오브젝트가 변경되었는지 boolean 값을 저장합니다
local isChangeds = {} :: {[Object]: boolean}

-- Good:
local isChangedStatesByObject = {} :: {[Object]: boolean}
```

### 주석 기반 문서 작성

moonwave 를 사용하여 문서를 작성합니다.
[주석 기반 문서](./document-based-comment.md)를 참고하세요.

### 구분

[outline-map](https://marketplace.visualstudio.com/items?itemName=Gerrnperl.outline-map)을 사용하면, 더 주석 region 과 tag 를 통해 심볼 단위말고도고 코드 사이를 빠르게 이동할 수 있습니다.

#### 주석 Region

주석 Region 기능을 이용해 코드 블록을 구분합니다.
`--#region <Name>` 과 `--#endregion <Name>` 으로 코드 블록을 감싸줍니다

감싸는 코드 블록은 다음과 같습니다:
- 객체: 객체가 모듈 스크립트에 여러 있다면 감싸줍니다, 단 객체가 하나라면 감싸주지 않아도 됩니다
  감싸줄 경우, 메소드와 이벤트들도 Region 안에 들어가도록 설정해줍니다 
- - InternalMethods
- - Methods
- - Events
- - Functions

```lua
--[[
	이 모듈의 설명
]]

--#region Object
local Object = {}
Object.__index = Object
Object.__type = "Object"

--#region Constructors
function Object.new()
end

function Object.fromInstance()
end
--#endregion Constructors
--#region Methods
function Object:Destroy()
end

function Object:GetProperty()
end
--#endregion Methods
--#endregion Object

--#region Subobject
local Subobject = {}
Subobject.__index = Subobject
Subobject.__type = "Subobject"

-- ...

--#endregion Subobject
```

#### 태그
큰 코드 블록 구분(생성자 블록/메소드 블록 등) 구분에 쓰거나, 매우 큰 동작 구분에 씁니다

```lua
--#tag 객체 속성 찾기
-- 아래 코드들부턴 객체 속성으로 찾습니다.
```

물론 태그로 분리하는 것보단 코드를 나눠 함수로 구분 하는 것이 더 좋습니다.
어쩔 수 없는 경우, 태그로 보는 것이 더 나은 경우 사용.


## 출력

### 에러


#### API 에러 호출

평범한 이름이나, `Validate-` 와 같은 이름의 함수들은 잘못된 값을 받으면 에러를 호출합니다

```lua
function Object:SetProperty()
    if not VALID_PROPERTY_KEY_SET[property] then
        error(`Property must be a string, got "{property}", "{typeof(property)}"`)
    end
    
    -- ...
end

-- `Validate-` 와 같은 이름의 함수는 잘못되면 에러를 호출하는 것이 목적입니다. 
function Object.Validate(object: Instance)
    if not object:HasTag("Object") then
        error(`Instance "{object}" must have "Object" tag to be a valid Object.`)
    end
end
```


#### 에러 대신 성공과 에러 메세지를 리턴하는 함수

Lua 함수가 실패할 수 있지만, 에러를 호출하지 않는 함수들은 `success, result` 패턴을 사용합니다.
`result`를 담은 커스텀 타입(`Result`, `Promise` 등)으로 반환해도 좋습니다.

`IsAllowed-` 같은 이름의 함수들에 사용됩니다.



### 상황별 형태

#### 공통

[문자열 보간](#문자열-보간)을 사용합니다.

#### 객체를 설명할 때

`메세지- <객체의 클래스> "{객체의 실제 이름}" -메세지` 이런 식으로 작성합니다.

```lua
print(`SpecialTag "{specialTag}" is added to the game`)

warn(`Character "{character}" is removed while loading`)

error(`Instance "{instanceName}" is destroyed`)
```

#### 실수 출력

소수점 출력이 너무 길어 문제되는 경우
`string.format("%.3f", number)` 과 문자열 보간을 이용할 수 있습니다 

```lua
local preciseValue = 3.1415926535
print(`The precise value is {string.format("%.3f", preciseValue)}`)
```

### 에러

#### 잘못된 타입을 받아서일 경우
`Invalid <파라미터 이름> "<받은 값>", "<받은 값의 타입>"` 형태로 작성합니다.

```lua
error(`Invalid property "{property}", "{typeof(property)}"`)
```

#### 넣어야할 값이 없을 경우
`Missing <파라미터 이름>` 형태로 작성합니다.

```lua
error(`Missing property "{property}"`)
```

## 문자열

### 따옴표

**큰따옴표** `"` 사용을 기본으로 합니다. 

작은따옴표 `'`는 가독성 측면에서 혼동이 있을 수 있어 최소화합니다.



### 문자열 보간

문자열 안에 무언가를 넣어야할 때는
`:format` 대신 Luau String Interpolation 기능을 사용합니다.

```lua
-- Bad:
print("Bob has " .. tostring(count) .. " apple(s)!")

-- Good:
print(`Bob has {count} apple(s)!`)
```

```lua
-- Bad:
error("Invalid class \"%s\", \"%s\" "):format(class, typeof(class)))

-- Good:
error(`Invalid class "{class}", "{typeof(class)}"`)
```

### 긴 문자열

가로로 너무 넓은 문자열의 경우, 보기 좋지 않으니,
이스케이프 시퀀스 `\z` 를 사용해 여러 줄로 작성합니다.

```lua
-- Bad:
error(`Failed to set ExtendedInstance "{self}" Property "{property}" because DataObject "{connectedDataObject}" has been destroyed.\nMake sure ObjectBuilder is still running.`)

-- Good:
error(
	`Failed to set ExtendedInstance "{self}" Property {property} \z
	because DataObject "{connectedDataObject}" has been destroyed. \n\z
	Make sure ObjectBuilder is still running.`
)
```


## 숫자

1 미만의 소수의 경우엔 `0.5` `0.1` `0.05` 처럼 `0.{n}`을 명시해줍니다.
음수의 경우에도 마찬가지

큰 수, 백만 이상의 수엔  언더스코어 `_` 로 세 자리마다 구분해줍니다.

```lua
local ONE_MILLION = 1_000_000
local someValue = 12_345_678
```


### 수식 공백
연산자 양옆에는 상황에 따라 공백을 둡니다. 우선순위를 명확히 해야 할 때만 예외를 둡니다.
```lua
print(5 + 5 * 6^2)
```

콤마 뒤에는 항상 공백을 둡니다.

괄호, 중괄호 등 블록을 여는 문법 요소는 **같은 줄**에 작성합니다.

## 코드 나누기

동작은 주석대신 여러 함수로 나눕니다.

```lua
local function detectPlayerRemovingToDestroy(context: PlayerContext, player: Player)
	-- ...
end

local function observePlayerScore(self: PlayerContext, initialScore: number)
	-- ...
end

local function observePlayerAttributes(self: PlayerContext)
	local initialScore = getScoreFromPlayer(player)
	observePlayerScore(self.Context, self.Player, initialScore)
	-- ...
end

local function createPlayerContext(player: Player): PlayerContext
	local self = {
		Player = player,
		-- ...
	}
	
	-- ...
	
	observePlayerAttributes(self)
	detectPlayerRemovingToDestroy(self)
	
	-- ...
	
	return self
end
```

함수의 이름은 디테일하게 지어서, 가독성을 높입니다.

다음 원칙을 함께 지킵니다.

- 외부 상태에 직접 접근하기보다, 상단에서 필요한 값을 지역 변수로 준비하고 각 함수에는 필요한 값만 인수로 전달합니다.
- 상위 함수는 흐름(오케스트레이션)만 담당하고, 실제 작업은 역할별 하위 함수로 위임합니다.
- 매개변수는 1~2개를 권장하며, 많아지면 `Params`/`Options` 딕셔너리를 사용합니다.

작은 예제(일반 동작을 함수로 분리, 상단에서 지역 변수 준비 후 인수로 전달):

```lua
-- 일반적인 주문 처리 예제: 동작을 함수로 쪼개고, 상단에서 지역 변수로 준비 후 인수로 전달

type Item = {
    Name: string,
    Price: number,
    Quantity: number,
}

type OrderParams = {
    Items: {Item},
    OrderId: string,
}

local function normalizeItems(items: {Item}): {Item}
    -- 유효하지 않은 수량/가격 보정 등 사전 처리
    local normalized = {} :: {Item}
    for i, item in items do
        local qty = if item.Quantity < 0 then 0 else item.Quantity
        local price = if item.Price < 0 then 0 else item.Price
        normalized[i] = { Name = item.Name, Price = price, Quantity = qty }
    end
    return normalized
end

local function calcLineTotal(item: Item): number
    return item.Price * item.Quantity
end

local function calcOrderTotal(items: {Item}): number
    local total = 0
    for _, item in items do
        total += calcLineTotal(item)
    end
    return total
end

local function createInvoice(orderId: string, items: {Item}, total: number)
    return {
        OrderId = orderId,
        Items = items,
        Total = total,
    }
end

local function processOrder(params: OrderParams)
    -- 상단에서 필요한 값을 지역 변수로 준비
    local orderId = params.OrderId
    local items = normalizeItems(params.Items)
    local total = calcOrderTotal(items)

    -- 하위 함수로 역할 위임
    return createInvoice(orderId, items, total)
end
```

## 재사용과 통일

- 여러 스크립트에서 동일한 상수, 검증 테이블, Attribute 타입 목록 등을 반복해서 선언하지 않습니다.

- 공용 모듈이나 유틸리티를 만들어 한 곳에서만 유지보수하고 필요한 곳에서 require 해 사용합니다.

- 이미 존재하는 공용 헬퍼가 있다면 새 코드를 작성할 때 우선 재사용합니다.

- 사용 가능한 해결책의 우선순위는 
  - Roblox/Luau 표준 라이브러리, 내장 인스턴스 속성, 메서드
  - 프로젝트 공용 유틸(TableUtil 등)
  - 새로 작성하는 지역 헬퍼 (정말로 필요할 경우만) 
  상위 단계에서 해결되지 않는 경우에만 다음 단계를 검토합니다.

- 특히 TableUtil 과 같이 제공되고 있는 라이브러리가 동일한 기능(예: children 병합, 딕셔너리 머지)을 해결할 수 있다면 지역 헬퍼 함수를 새로 만들지 말고 우선 이를 사용합니다. 유틸 함수가 처리하지 못하는 입력만 최소 범위의 보조 함수를 두고, 동일 로직을 반복하지 않습니다.

## 기타 규칙

**세미콜론 `;`** 은 사용하지 않습니다. 


---

## 참고 자료

- [Roblox 공식 Roblox Lua Style Guide](https://roblox.github.io/lua-style-guide/)
- [Google C++ Style Guide](https://google.github.io/styleguide/cppguide.html)
- [Why You Shouldn't Nest Your Code (영상)](https://youtu.be/CFRhGnuXG-4?si=pTY9rwNHSJvWciRh)
- [Naming Things In Code (영상)](https://youtu.be/-J3wNP6u5YU?si=8RmUk8FMCaS9yXBR)
- [Plant Reference Project](https://create.roblox.com/docs/resources/plant-reference-project)
