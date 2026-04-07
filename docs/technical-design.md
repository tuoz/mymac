# macOS 自定义快捷键工具技术设计文档

## 1. 文档目标

本文档基于 [software-requirements.md](/Users/tuoz/Workspace/projects/mymac/docs/software-requirements.md) ，给出该 macOS 后台快捷键工具的技术实现方案，重点覆盖：

- 系统级按键监听与事件注入方案
- `Fn + H/J/K/L` 到方向键映射的关键实现
- 自启动、权限、后台常驻与菜单栏设计
- 为未来窗口管理预留的可扩展架构
- 关键风险、边界与测试策略

## 2. 设计结论摘要

### 2.1 核心技术路线

- 应用形态：`LSUIElement` 后台应用，保留菜单栏入口和设置窗口
- UI 层：SwiftUI
- 系统能力层：AppKit + Quartz Event Services + Accessibility API
- 自启动：`ServiceManagement.SMAppService.mainApp`
- 快捷键实现：`CGEventTap` 拦截键盘事件，命中规则后抑制原事件并注入目标方向键事件
- 配置存储：`UserDefaults` / `@AppStorage`
- 并发模型：UI 状态在 `@MainActor`，事件监听运行于独立线程 + RunLoop，事件匹配逻辑保持同步且常量时间

### 2.2 最重要的实现判断

MVP 不建议使用仅“注册全局快捷键”的高层方案，而应直接采用底层事件 tap。

原因：

1. 我们不只是要“收到一个热键回调”，还要“拦截原始 `H/J/K/L`”
2. 需要保留其他修饰键，并转换成新的方向键事件
3. 未来窗口管理也需要共用同一套“输入事件 -> 动作”管线
4. 仅靠全局快捷键注册方案，难以同时满足“抑制原字符输入”和“自然透传组合修饰键”两点

## 3. 技术目标与非目标

### 3.1 技术目标

- 低延迟、可预测地完成映射
- 在权限缺失时明确降级和提示
- 模块边界清晰，未来可扩展到窗口管理
- 尽量减少 MVP 的工程复杂度

### 3.2 技术非目标

- 本阶段不实现动态脚本系统
- 本阶段不实现任意用户自定义规则编辑器
- 本阶段不追求 App Sandbox / Mac App Store 兼容作为首要约束

## 4. 建议平台基线

### 4.1 建议最低版本

建议 MVP 以 `macOS 14+` 为目标。

理由：

- 可直接使用 `@Observable` 组织跨 SwiftUI / AppKit 状态
- `MenuBarExtra`、现代设置窗口和系统集成方案更顺滑
- `SMAppService` 自启动体验更统一
- 能减少兼容旧系统的额外样板代码

说明：

- 若必须支持 `macOS 13`，整体方案仍成立，但状态管理和部分 UI 实现会稍微退化

### 4.2 发布方式建议

当前建议采用：

- 非 App Sandbox
- 开发者签名
- 公证后直接分发

原因：

- 这是一个需要全局键盘监听与事件注入的工具型软件
- 内部使用优先，先以可用性和实现稳定性为主
- 后续如要考虑 Mac App Store，再单独评估权限模型和功能边界

## 5. 总体架构

### 5.1 分层架构

```text
App Shell
  ├─ Menu Bar / Settings / Onboarding
  ├─ AppLifecycleCoordinator
  └─ AppState

Application Services
  ├─ PermissionService
  ├─ LaunchAtLoginService
  ├─ EventTapController
  └─ DiagnosticsService

Input Domain
  ├─ KeyEventSnapshot
  ├─ KeyMappingEngine
  ├─ ModifierNormalizer
  └─ RuleSnapshotProvider

Action Domain
  ├─ ActionDispatcher
  ├─ AppAction
  ├─ KeyboardActionExecutor
  └─ Future: WindowActionExecutor

Persistence
  ├─ SettingsStore
  └─ Migration / Defaults
```

### 5.2 设计原则

1. 输入识别与动作执行分离
2. 事件 tap 回调保持同步、轻量、无阻塞
3. UI 状态与底层监听状态解耦
4. 配置使用不可变快照供底层读取，避免回调线程等待主线程

## 6. 模块设计

## 6.1 App Shell

职责：

- 应用启动与生命周期编排
- 创建菜单栏入口
- 打开设置与首次引导窗口
- 汇总运行状态并展示

建议组成：

- `MyMacApp.swift`
- `AppDelegate.swift`
- `AppCoordinator`
- `AppState`

关键配置：

- `Info.plist` 设置 `LSUIElement = YES`
- 应用无 Dock 图标
- 启动时决定展示 onboarding、settings 或直接后台常驻

## 6.2 PermissionService

职责：

- 检测监听权限与事件注入权限
- 提供权限申请引导
- 暴露权限状态给 UI

建议状态模型：

```swift
enum PermissionState: Sendable, Equatable {
    case unknown
    case granted
    case denied
    case requiresUserAction
}

struct PermissionsSnapshot: Sendable, Equatable {
    var accessibility: PermissionState
    var inputMonitoring: PermissionState
}
```

说明：

- macOS 上“监听全局键盘事件”和“投递模拟键盘事件”可能涉及不同权限路径
- UI 文案层面统一抽象为“核心权限未完整开启”
- 底层实现层面分别检测、分别展示、分别重试

## 6.3 LaunchAtLoginService

职责：

- 读取开机自启动状态
- 开启/关闭自启动
- 对 `requiresApproval` 等状态做 UI 映射

建议接口：

```swift
protocol LaunchAtLoginService: Sendable {
    func currentStatus() -> LaunchAtLoginStatus
    func setEnabled(_ enabled: Bool) throws
}

enum LaunchAtLoginStatus: Sendable, Equatable {
    case enabled
    case disabled
    case requiresApproval
    case unavailable
}
```

实现建议：

- 直接封装 `SMAppService.mainApp`
- 不在 View 中直接调用系统 API
- UI 只依赖语义状态，不依赖底层枚举

## 6.4 EventTapController

这是整个系统的核心基础设施。

职责：

- 创建与维护 `CGEventTap`
- 在独立线程的 RunLoop 上接收事件
- 将命中的原始事件转换为抽象动作
- 抑制原事件并投递新事件
- 处理 tap 被系统禁用的恢复逻辑

关键判断：

- 不使用 `NSEvent.addGlobalMonitorForEvents` 作为主方案，因为它只能监听，不能抑制原始输入
- 必须使用可以返回 `nil` 以抑制事件的 tap 方案

### 6.4.1 线程模型

建议结构：

- `EventTapThread`: 专用线程
- 线程上创建 `CFMachPort` event tap
- 将 tap source 挂入该线程 RunLoop
- 该线程只处理低延迟键盘事件，不参与 UI 更新和磁盘 I/O

原因：

- 避免主线程卡顿影响输入
- 避免 event callback 执行期间等待主线程
- 便于单独重启 tap 和做诊断

### 6.4.2 事件回调约束

event tap 回调必须满足：

- 不做异步等待
- 不访问复杂共享可变状态
- 不直接驱动 SwiftUI
- 不做日志刷盘
- 不做权限弹窗

回调中只做三件事：

1. 将系统事件投影成轻量 `KeyEventSnapshot`
2. 用当前规则快照进行匹配
3. 决定 `pass through / suppress / inject action`

### 6.4.3 事件类型

MVP 至少监听：

- `keyDown`
- `keyUp`
- `flagsChanged`

处理建议：

- `keyDown`: 做主要匹配与触发
- `keyUp`: 发送对应方向键 `keyUp`
- `flagsChanged`: 用于修饰键状态同步与诊断，尤其是 `Fn` 状态追踪

## 6.5 KeyMappingEngine

职责：

- 将键盘事件转换为抽象动作
- 只依赖不可变规则快照
- 不关心 UI、不关心系统权限、不直接发事件

建议输入输出：

```swift
struct KeyEventSnapshot: Sendable, Equatable {
    var type: KeyEventType
    var keyCode: CGKeyCode
    var modifiers: ModifierSet
    var isAutorepeat: Bool
}

enum AppAction: Sendable, Equatable {
    case sendKey(keyCode: CGKeyCode, modifiers: ModifierSet, kind: KeyEventType, isAutorepeat: Bool)
    case noop
}
```

MVP 规则可先硬编码，但表现为规则表：

```swift
Fn + H -> Left
Fn + J -> Down
Fn + K -> Up
Fn + L -> Right
```

未来再把规则表来源切换到配置存储即可。

## 6.6 ActionDispatcher

职责：

- 接收 `AppAction`
- 按动作类型分派到具体执行器

建议接口：

```swift
protocol ActionExecutor<Action> {
    associatedtype Action
    func execute(_ action: Action)
}
```

MVP 只需要：

- `KeyboardActionExecutor`

未来可以新增：

- `WindowActionExecutor`
- `ApplicationCommandExecutor`

## 6.7 SettingsStore

MVP 建议直接使用 `UserDefaults`，不引入 SwiftData。

原因：

- 当前只有少量布尔状态与简单运行配置
- 快速、稳定、无 schema 迁移负担
- 日后需要规则列表时仍可平滑演进

建议存储项：

- `hasCompletedOnboarding`
- `isKeyboardMappingEnabled`
- `launchAtLoginDesired`
- `lastKnownPermissions`
- `diagnosticsEnabled`

## 7. 关键实现难点

## 7.1 难点一：为什么必须用事件 tap，而不是普通全局快捷键

这个产品不是“收到一个热键后执行命令”那么简单，而是“把真实输入流改写掉”。

目标行为是：

1. 用户按下 `Fn + Cmd + H`
2. 系统原本会看到字母 `H`
3. 我们必须拦截这个 `H`
4. 然后发出 `Cmd + Left`

如果只能监听而不能抑制原事件，最终前台应用会同时收到：

- 原始 `H`
- 新注入的 `Left`

这会导致文本输入污染，因此必须使用可抑制事件的实现路径。

## 7.2 难点二：`Fn` 键识别并不等于普通修饰键

`Fn` 在 macOS 上不是一个常规字母修饰键。

实现上需要注意：

- 它通常体现在事件 flags 中的 `secondaryFn`
- 某些键盘、系统设置、外接设备下表现可能略有差异
- 新机型上 `Fn` 还常与 Globe 键共享物理键位

设计策略：

1. 主判断以目标键 `keyDown` 事件自身的 modifier flags 为准
2. 同时维护一个轻量 `flagsChanged` 状态跟踪器用于容错和调试
3. 测试矩阵中必须覆盖内建键盘和常见外接键盘

## 7.3 难点三：避免注入事件再次被自己捕获，形成递归

如果应用注入了一个方向键事件，而 tap 又把这次注入捕获回来，就会造成：

- 重复映射
- 无限递归
- 键盘行为错乱

解决方案：

1. 为本应用生成的 `CGEvent` 写入专属标记
2. tap 回调第一步先检测该标记
3. 命中本应用标记则直接透传，不再参与映射

实现上可通过事件字段中的自定义用户数据标识完成。

## 7.4 难点四：长按与自动重复

用户长按 `Fn + H` 时，期望行为接近原生左箭头长按。

需要处理：

- 初始 `keyDown`
- 自动重复 `keyDown`
- 最终 `keyUp`

设计要求：

- 保留 autorepeat 语义
- 对重复 `keyDown` 继续生成重复方向键事件
- 对 `keyUp` 发出一次对应方向键释放事件

不建议：

- 在应用层自己用定时器模拟按键重复

原因：

- 会导致和系统键盘重复设置不一致
- 更容易产生节奏抖动

## 7.5 难点五：tap 可能被系统禁用

`CGEventTap` 在以下情况下可能失效：

- 回调执行过慢
- 用户输入风暴期间超时
- 权限状态变化
- 系统睡眠/唤醒后的底层状态异常

设计要求：

- 监听 tap disabled 回调事件
- 对 `byTimeout` 自动 re-enable
- 对 `byUserInput` / 权限缺失转为诊断状态
- 将状态同步给菜单栏和设置页

## 7.6 难点六：权限是运行时核心依赖，不是一次性配置

该软件能否工作，高度依赖系统权限。

设计上不能把权限检查只放在 onboarding：

- 启动时要检查
- 用户从系统设置切回后要允许重试
- 监听启动失败时要回落到“缺少权限”状态
- 菜单栏状态要持续反映当前权限是否完整

## 8. 关键流程设计

## 8.1 应用启动流程

```text
App Launch
  -> 构建 AppState / Services
  -> 检测权限状态
  -> 读取本地设置
  -> 初始化菜单栏
  -> 若未完成 onboarding，显示引导窗口
  -> 若权限完整且映射开关开启，启动 EventTapController
  -> 后台常驻
```

## 8.2 快捷键处理流程

```text
系统键盘事件
  -> CGEventTap callback
  -> 过滤本应用注入事件
  -> 转换成 KeyEventSnapshot
  -> 使用 RuleSnapshot 匹配
  -> 若未命中，透传原事件
  -> 若命中，抑制原事件
  -> 生成 AppAction.sendKey(...)
  -> KeyboardActionExecutor 注入方向键事件
```

## 8.3 权限补齐流程

```text
用户打开应用 / 设置页
  -> PermissionService 检测
  -> 若缺权限，展示解释与入口
  -> 用户跳转系统设置授权
  -> 返回应用
  -> 用户点击“重新检测”
  -> 若已齐全，启动或重启 EventTapController
```

## 8.4 自启动开启流程

```text
用户切换“开机启动”
  -> LaunchAtLoginService.setEnabled(true)
  -> 读取返回状态
  -> 若 requiresApproval，提示去系统设置确认
  -> 更新 UI 状态
```

## 9. 关键数据结构

### 9.1 修饰键模型

建议不要直接把系统原始 flags 暴露给所有上层模块，而是归一化为内部模型：

```swift
struct ModifierSet: OptionSet, Sendable {
    let rawValue: Int

    static let command
    static let shift
    static let option
    static let control
    static let fn
}
```

原因：

- 便于跨层测试
- 便于以后扩展其他输入来源
- 便于统一“输出时去掉 `fn`”的规则

### 9.2 规则快照

事件回调不能依赖可变 UI 状态，因此需要只读快照：

```swift
struct RuleSnapshot: Sendable {
    var isEnabled: Bool
    var mappings: [InputChord: OutputAction]
    var eventMarker: Int64
}
```

说明：

- `eventMarker` 用于标记本应用注入事件
- `mappings` MVP 可只有四条
- 后续窗口管理可直接复用该结构

### 9.3 动作模型

```swift
enum OutputAction: Sendable, Equatable {
    case keyboard(keyCode: CGKeyCode)
    case window(command: WindowCommand)
}
```

这一步是未来可扩展性的关键。

当前只实现：

- `.keyboard(.leftArrow / .downArrow / .upArrow / .rightArrow)`

## 10. 状态管理设计

### 10.1 UI 状态

建议使用 `@Observable @MainActor` 的 `AppState`：

```swift
@MainActor
@Observable
final class AppState {
    var permissions: PermissionsSnapshot = .init(...)
    var runtimeStatus: RuntimeStatus = .starting
    var launchAtLogin: LaunchAtLoginStatus = .disabled
    var isMappingEnabled: Bool = true
}
```

### 10.2 底层运行状态

底层监听线程不直接依赖 `AppState`，而是依赖快照对象。

推荐关系：

- UI 修改设置
- `SettingsStore` 写入
- `RuleSnapshotProvider` 生成新快照
- `EventTapController` 替换内部快照引用

这样可以避免 event callback 与主线程状态直接共享。

## 11. 工程组织建议

MVP 不建议一开始拆成本地 Swift Packages，建议先单 target + feature folders。

推荐目录：

```text
MyMacApp/
  App/
    MyMacApp.swift
    AppDelegate.swift
    AppCoordinator.swift
    AppState.swift
  Features/
    Onboarding/
    Settings/
    MenuBar/
  Core/
    Domain/
      AppAction.swift
      ModifierSet.swift
      InputChord.swift
      RuleSnapshot.swift
    Services/
      PermissionService.swift
      LaunchAtLoginService.swift
      DiagnosticsService.swift
    EventSystem/
      EventTapController.swift
      EventTapThread.swift
      KeyEventSnapshot.swift
      KeyMappingEngine.swift
      KeyboardActionExecutor.swift
      CGEvent+Helpers.swift
    Persistence/
      SettingsStore.swift
  Resources/
```

理由：

- 当前规模小，过早模块化收益不高
- 先保证边界正确，再视复杂度升级为 package

## 12. UI 技术设计

## 12.1 菜单栏

建议使用 `MenuBarExtra`。

菜单内容：

- 当前状态
- 快捷键映射开关
- 开机启动开关
- 权限状态
- 打开设置
- 退出应用

### 12.2 设置窗口

建议保留三个页签：

- General
- Permissions
- About

### 12.3 首次引导

建议为单独窗口，不做复杂多页引导。

内容最少包含：

- 产品作用说明
- 权限说明
- 自启动开关
- “完成并开始使用”按钮

## 13. 错误处理与诊断

## 13.1 运行状态枚举

```swift
enum RuntimeStatus: Sendable, Equatable {
    case starting
    case running
    case paused
    case missingPermissions
    case tapDisabled
    case failed(String)
}
```

### 13.2 日志建议

建议使用 `Logger` 记录：

- 权限检查结果
- tap 启动/停止/重启
- 自启动状态变化
- 命中规则计数
- 注入失败

注意：

- 不记录完整用户输入序列
- 诊断日志以状态变化和计数为主

## 14. 测试设计

## 14.1 单元测试

重点测试纯逻辑层：

- `ModifierNormalizerTests`
- `KeyMappingEngineTests`
- `RuleSnapshotProviderTests`
- `LaunchAtLoginStatusMapperTests`

关键用例：

- `Fn + H -> Left`
- `Fn + Cmd + H -> Cmd + Left`
- 非目标键不命中
- 输出时移除 `fn`
- 重复按键时动作类型正确

## 14.2 集成测试

关注：

- Event tap 启停
- 权限不足时的降级
- 设置变更后规则快照是否即时生效

## 14.3 手工验证矩阵

至少覆盖：

- 内建键盘
- 外接键盘
- 编辑器
- 终端
- 浏览器输入框
- Finder
- 长按重复
- 睡眠唤醒
- 登录后自动启动

## 15. 演进设计：未来窗口管理如何接入

未来增加窗口管理时，不修改事件采集链路，只新增：

1. 新规则
2. 新动作类型
3. 新执行器

演进方式：

```text
Fn + H -> keyboard(left)
Fn + Return -> window(maximize)
Fn + U -> window(snapLeft)
```

所需改动范围应限制在：

- `OutputAction`
- `ActionDispatcher`
- `WindowActionExecutor`
- 设置页中的规则展示

Event tap、权限管理、自启动、菜单栏状态都不应被推翻。

## 16. 不建议的实现路径

1. 不建议只用 `NSEvent` 全局监听
   原因：无法可靠抑制原始字符输入。

2. 不建议把键位映射逻辑直接写在 View 或 AppDelegate 中
   原因：后续窗口管理会迅速失控。

3. 不建议在 event callback 中做异步 hop 到主线程再决定是否拦截
   原因：延迟和竞争条件都不可接受。

4. 不建议自己用 Timer 模拟长按重复
   原因：与系统重复节奏不一致。

5. 不建议一开始就引入 SwiftData
   原因：当前配置结构过于简单，收益不足。

## 17. 实施顺序建议

### Phase 1：验证底层能力

- 创建后台应用壳
- 完成 event tap 原型
- 验证 `Fn + H/J/K/L` 检测
- 验证原事件抑制与方向键注入
- 验证组合修饰键透传

### Phase 2：接入产品骨架

- 接入菜单栏
- 接入设置页
- 接入权限引导
- 接入自启动开关

### Phase 3：稳态与诊断

- 补齐 tap 恢复逻辑
- 补齐日志与状态展示
- 扩充手工测试矩阵

## 18. 参考资料

- Apple Service Management: [developer.apple.com/documentation/servicemanagement](https://developer.apple.com/documentation/servicemanagement)
- Apple Quartz Event Services: [developer.apple.com/documentation/coregraphics/quartz_event_services](https://developer.apple.com/documentation/coregraphics/quartz_event_services)
- Apple Accessibility: [developer.apple.com/documentation/applicationservices/accessibility](https://developer.apple.com/documentation/applicationservices/accessibility)
- Apple SwiftUI MenuBarExtra: [developer.apple.com/documentation/swiftui/menubarextra](https://developer.apple.com/documentation/swiftui/menubarextra)

## 19. 结论

这款软件的技术核心不是“注册几个快捷键”，而是建立一条稳定的系统输入改写管线：

- 监听原始键盘事件
- 在低延迟路径上识别 `Fn + H/J/K/L`
- 抑制原字符
- 注入目标方向键
- 让 UI、权限、自启动、未来动作扩展都围绕这条管线展开

只要第一版把这条管线和模块边界设计正确，后面增加窗口管理、规则配置、动作扩展时，才不会进入大规模返工。
