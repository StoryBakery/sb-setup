---
sidebar_label: OOP Style
---

# OOP Style

객체지향 스타일은 다양하지만 Story Bakery 에선 다음 구조를 자주 사용합니다.


## API 문서 주석

API 문서 주석의 상세한 체계적인 방식은, [document-based-comment](./document-based-comment.md) 를 참고하세요.
주로 `moonwave` 를 이용해서 주석을 작성합니다.


## 예제

```lua
--[=[
    @class Class
    
    Class 객체에 대한 설명
]=]

local Class = {}
Class.__index = Class
Class.__type = "Class"

export type Class = setmetatable<{
    --[=[
        @prop Class.IsDestroyed boolean
        설명
    ]=]
    IsDestroyed: boolean,
    
    
    --[=[
        @prop Class.Maid Maid
        설명
    ]=]
    Maid: Maid.Maid,
    
    --[=[
        @prop Class.Name string
        설명
    ]=]
    Name: string,
    
    _private: any,
}, typeof(Class)>

--#region Constructors

--[=[
    @interface ClassParams
    @within Class
    
    Class 생성자에 전달되는 매개변수들의 타입입니다.
    
    .Name string? -- 클래스의 이름입니다. 기본값은 "Name" 입니다.
]=]
export type ClassParams = {
	Name: string?,
}

--[=[
    Class 객체의 새 인스턴스를 생성합니다.
]=]
function Class.new(params: ClassParams?): Class
	local params = params or {}
	local self = setmetatable({}, Class)
	
	self.IsDestroyed = false
	self.Maid = Maid.new()
	
	self.Property = params.Name or "Name"
	
	self:_listenName()
	
	return self
end
--#endregion Constructors

function self:_listenName()
	-- do something...
end

--#region Methods
--[=[
    객체를 파괴하고 모든 내부 리소스를 정리합니다.
]=]
function Class:Destroy()
	if self.IsDestroyed then
		return
	end
	
	self.IsDestroyed = true
	self.Maid:Destroy()
	
	-- 추가 동작
end
--#endregion Methods

--#region Functions
--[=[
    이름으로부터 Class 객체를 검색합니다.
    
    @param name string -- 검색할 클래스 이름
    @return Class -- 검색된 클래스 객체
]=]
function Class.GetClassByName(name: string): Class
	return classesByName[name] or error(`Failed to get Class from name "{Name}".`)
end
--#endregion Functions
```



## 블록 구분 규칙

`--#region` / `--#endregion` 은 Types, Constructors, Methods 와 같이 객체지향 구조의 큰 구획만 감쌉니다.
서비스, Require, 상수 등 일반 코드 블록은 **빈 줄과 작성 순서**로만 구분하며, `-- 공통 조상 --`, `-- 외부 패키지 --` 같은 주석으로 감싸지 않습니다.
Require 블록은 외부 패키지 → 공통 조상 → 공통 조상의 하위 모듈 순서를 지키고, 각 항목은 문자열 literal alias 로 `require("@Alias/Path")` 형식만 사용합니다.

생성자와 내부 함수 작성 원칙:

- 생성자 이름은 언제나 camelCase 로 작성합니다.
- 내부 함수는 생성자나 메서드 안에서만 함께 사용하며, 기능 단위를 나누는 용도로만 둡니다.
- 내부 함수를 쪼개는 목적은 주석 없이도 함수 이름만으로 동작을 구분하도록 하기 위함입니다.

## 정의 순서

비슷한 책임을 가진 요소는 항상 묶어서 정의하고, Params → 지역 함수 → 메인 메서드 순으로 가까이 배치합니다.  
이렇게 하면 호출 관계를 한눈에 파악할 수 있고, 문서/코드 모두에서 동일한 흐름을 유지할 수 있습니다.

### Params 와 지역 함수

- 특정 메서드나 로컬 함수가 사용하는 Params 타입은 **무조건 가장 위**에 둡니다.
- Params 아래에는 해당 메서드를 위해 준비한 지역 함수를 나열합니다.
- 지역 함수는 "더 깊은" 헬퍼가 먼저, "메인 함수에 가까운" 헬퍼가 나중에 오도록 작성합니다.

```lua
-- 스폰 관련 Params 를 먼저 둡니다.
export type SpawnParams = {
	Template: Model?,
	Name: string?,
}

-- 가장 안쪽에서만 쓰이는 헬퍼부터 선언합니다.
local function cloneTemplate(template: Model, name: string?): Model
end

local function createSpawnModel(params: SpawnParams): Model
	return cloneTemplate(params.Template, params.Name)
end

-- 마지막 줄에 메인 메서드를 정의합니다.
function Character:Spawn(params: SpawnParams)
	local model = createSpawnModel(params)
	-- ...
end
```

### 헬퍼 메서드(_prefix)

- `Class:_helper()` 처럼 `_` 로 시작하는 메서드는 **항상 해당 메인 메서드 아래**에 둡니다.
- 메인 메서드가 여러 헬퍼를 호출한다면 호출 순서가 비슷한 것끼리 묶고, 헬퍼의 서브 헬퍼는 부모 바로 아래에 둡니다.

```lua
function Character:Despawn(model: Model)
	self:_releaseModel(model)
	self:_cleanupMaid(model)
end

function Character:_releaseModel(model: Model)
	self:_releaseCharacterInfo(model)
end

function Character:_releaseCharacterInfo(model: Model)
	-- ...
end

function Character:_cleanupMaid(model: Model)
	-- ...
end
```

## 생성자

### 위치

생성자는 모듈 메서드/함수 정의 중 맨 위에 둡니다.

### 네이밍

전부 camelCase 로 작성합니다

```lua
--#region Constructors

function Cleaner.new(params: CleanerParams?): Cleaner
	local self = setmetatable({}, Cleaner)
	
	-- do something...
	
	return self
end

function Cleaner.fromInstance(instance: Instance, params: CleanerFromInstanceParams?): Cleaner
	local self = Cleaner.new()
	
	-- do something...
	
	return self
end
```

기존에 생성한 걸 찾거나 얻는 게 아니라면 함수 형식으로 작성합니다

### new

기본적인 객체 생성은 `new` 로 작성합니다.

#### 싱글턴

싱글턴 패턴의 모듈에도 `.new()` 를 사용해줍시다


```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")


local Signal = require("@Signal")
local Promise = require(Packages.Promise)

local CameraModules = ReplicatedStorage.CameraModules

local CameraManager = {}
CameraManager.__index = CameraManager
CameraManager.__type = "CameraManager"

--#region Constructors
function CameraManager.new(): CameraManager
end
--#endregion Constructors

--#region Methods
function CameraManager:GetCFrame(): CFrame
end
--#endregion Methods

return CameraManager.new()
```


혹은 싱글턴은 아니지만, 대부분의 상황에서 하나의 인스턴스만 필요하고
가끔씩 개별된 객체가 필요하다면, 싱글턴으로 만들기보단 `Global{Object}` 로 공통적으로 쓰일 수 있는 객체를 만듭니다.
```lua
local DyanmicTimer = {}
DyanmicTimer.__index = DyanmicTimer

-- ...


DyanmicTimer.GlobalTimer = DyanmicTimer.new()

return DyanmicTimer
```




### Params

생성자에는 여러 인수나, params 가 필요할 수 있습니다
params 필수 여부는 params 가 얼마나 중요하나에 따라 달리 설정할 수 있습니다

params 에 대한 타입은 해당 params 를 사용하는 생성자나 메서드 위에 올려둡니다.

```lua
--#region Constructors
export type CleanerParams = {
    
}
function Cleaner.new(params: CleanerParams?): Cleaner
end

export type CleanerFromInstanceParams = {
	
}
function Cleaner.fromInstance(instance: Instance, params: CleanerFromInstanceParams?): Cleaner
end
--#endregion Constructors
```

Params 가 필수가 아니라면 `local params = params or {}` 를 통해 코드 맨 위에 정의해줍니다.
```lua
function Cleaner.new(params: CleanerParams?): Cleaner
	local params = params or {}
	local self = setmetatable({}, Cleaner)
	-- ...
	self.Name = params.Name or "Name"
	-- ...
end
```

Params 가 필수고, 특정 인자값도 필수적이라면 `or error()` 를 이용할 수 있습니다
```lua
export type CarParams = {
    Speed: number,
    Optional: any?,
}

function Car.new(params: CarParams): Car
	local self = setmetatable({}, Cleaner)
	-- ...
	self:_setSpeed(params.Speed or error(`Missing Speed`))
	-- ...
end
```

## 속성

모듈이나 객체에 `.` 으로 인덱스하며, 함수가 아닌 변수들을 말합니다.

### Destroy / Maid 규칙

모든 객체(싱글턴 제외)는 `IsDestroyed` 와 `Maid` 속성을 기본으로 갖습니다. 
생성자에서 `self.IsDestroyed = false`, `self.Maid = Maid.new()` 를 세팅하고, 
파괴 시 `self.Maid:Destroy()` 로 연결·콜백을 정리합니다.

절대 삭제되지 않는 싱글턴이라면 파괴 루틴이 없으므로 `IsDestroyed` 나 `Maid` 속성을 정의하지 않아도 됩니다.

`:Destroy()` 메서드는 항상 아래 패턴을 따릅니다.
```lua
function Object:Destroy()
	if self.IsDestroyed then
		return
	end
	self.IsDestroyed = true
	self.Maid:Destroy()
	-- 추가 정리 로직
end
```

파괴 시점에만 필요한 연결이나 콜백은 `_connection`, `_listener` 같은 내부 변수로 남겨 두지 않고 Maid 에 직접 `GiveTask` 합니다. 
단, 매우 자주 재설정되는 값/캐시처럼 Maid 정리와 관계없는 상태는 기존 방식대로 내부 속성으로 유지합니다.

`_` 접두사를 쓰는 private 멤버는 Maid 로 수명 관리를 대체할 수 없는 데이터일 때만 허용합니다. 
단순히 연결을 끊기 위해 기록하는 용도라면 `_connection` 대신 Maid 에서 정리할 수 있도록 우선 등록하세요.

외부에서 인스턴스가 파괴되는 상황을 감지해야 한다면 
인스턴스의 `Maid` 에 `Instance.AncestryChanged` 연결을 등록하여 `self:Destroy()` 를 호출하도록 구성합니다.  
`Destroying` 이벤트는 `:Destroy()` 호출에만 반응하고 `.Parent = nil` 이나 스트리밍 아웃 시에는 발동하지 않으므로 **절대 사용하지 않습니다**.  
`AncestryChanged:Connect(function(_, newAncestor)` 형식으로 연결해 `newAncestor == nil` 일 때 수거하세요.

## 메서드

메서드는 객체에 `:` 으로 작동하는 함수들입니다.

## 순서

`:Destroy` 메서드가 필요한 객체라면 항상 메서드 목록의 맨 위에 둡니다.

최대한 비슷한 분류의 메서드끼리 나열해 둡니다.
인덱스 관련 메서드 끼리는 인덱스 관련 메서드끼리, 속성 관련 메서드 끼리는 속성 관련 메서드끼리 모아둡니다.

이 때 `Set-`, `Find-`, `Get-` 계열의 메서드라면
1. Set
2. Find (Find 가 필요없다면, 생략)
3. Get
   Get 메서드의 동작은 ```Find(...) or error(`Failed to find ...`)``` 형태로 작성하는 경우가 많기 때문

예시
```lua
function InventoryInfoInstance:Destroy()
end

function InventoryInfoInstance:SetItemAtIndex(index: number, itemInfo: InventoryInfoInstance.RawItemInfo)
end

function InventoryInfoInstance:FindItemAtIndex(index: number): InventoryInfoInstance.RawItemInfo?
end

function InventoryInfoInstance:GetItemAtIndex(index: number): InventoryInfoInstance.RawItemInfo
end

function InventoryInfoInstance:SetItemAttribute(index: number, attributeName: string, value: any)
end

function InventoryInfoInstance:FindItemAttribute(index: number, attributeName: string): any?
end

function InventoryInfoInstance:GetItemAttribute(index: number, attributeName: string): any
end
```

 

## 함수

함수들은 모듈에 `.` 으로 작동하는 함수들입니다.

## 순서

메서드처럼 비슷한 분류의 함수끼리 나열해 둡니다.

똑같이 `Set-`, `Find-`, `Get-` 계열의 함수라면
1. Set
2. Find (Find 가 필요없다면, 생략)
3. Get
   Get 함수의 동작은 ```Find(...) or error(`Failed to find ...`)``` 형태로 작성하는 경우가 많기 때문