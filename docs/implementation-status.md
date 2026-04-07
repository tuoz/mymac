# MyMac 阶段性实现状态

## 1. 文档目的

本文档用于记录当前代码实现已经达到的阶段、已验证结果、已知限制，以及后续任务最适合继续推进的方向。

适用场景：

- 后续任务接手时快速建立上下文
- 对照需求文档与技术设计文档判断当前落地程度
- 避免重复调研已经完成的实现细节

关联文档：

- [software-requirements.md](/Users/tuoz/Workspace/projects/mymac/docs/software-requirements.md)
- [technical-design.md](/Users/tuoz/Workspace/projects/mymac/docs/technical-design.md)

## 2. 当前阶段结论

当前项目已经从“可编译工程骨架”推进到“真实 CGEventTap 链路已接入，应用可编译”的阶段。

这意味着：

- 项目不再只依赖 `StubKeyboardMappingService`
- 已接入真实 `CGEventTap` 创建与运行
- 已接入真实方向键事件注入
- 已接入权限请求与权限状态驱动的运行状态切换
- 已在 Xcode 中完成 Debug 构建验证

当前更准确的阶段描述是：

`MVP 底层链路已集成完成，接下来重点转向真实运行验证与行为稳定性调试`

## 3. 已完成内容

### 3.1 工程与应用壳

已完成：

- 原生 `MyMac.xcodeproj`
- `LSUIElement` 后台应用形态
- 菜单栏入口
- 设置窗口
- 首次引导窗口
- `AppState + AppCoordinator` 的运行状态编排

关键文件：

- [MyMacApp.swift](/Users/tuoz/Workspace/projects/mymac/MyMac/App/MyMacApp.swift)
- [AppCoordinator.swift](/Users/tuoz/Workspace/projects/mymac/MyMac/App/AppCoordinator.swift)
- [AppState.swift](/Users/tuoz/Workspace/projects/mymac/MyMac/App/AppState.swift)

### 3.2 权限服务

已完成：

- `PermissionService` 从占位实现升级为真实系统权限实现
- 提供了：
  - 状态刷新
  - 主动请求权限
  - 跳转系统设置
  - `canStartMapping(_:)`

实现说明：

- 当前实现已收敛为单一用户可见权限模型：`Accessibility`
- 权限状态仅通过 AX trusted 状态判断
- 权限同步与运行状态协调由 `AppCoordinator` 在启动、主动请求权限、首次引导完成、用户点击“重新检测”、应用回到前台时统一触发
- UI 与运行状态不再展示 `Input Monitoring`
- Swift 6 并发检查相关问题已处理

关键文件：

- [PermissionService.swift](/Users/tuoz/Workspace/projects/mymac/MyMac/Core/Services/PermissionService.swift)

### 3.3 真实事件链路

已完成：

- 用真实 `CGEventTapKeyboardMappingService` 取代原 stub
- 使用 `cgSessionEventTap + headInsertEventTap`
- 监听事件类型：
  - `keyDown`
  - `keyUp`
  - `flagsChanged`
- 在独立线程中创建 tap 并运行 RunLoop
- `tapDisabledByTimeout` 自动尝试恢复
- `tapDisabledByUserInput` 会更新状态为 `tapDisabled`

已实现的内部组件：

- `EventTapController`
- `ModifierStateTracker`
- `KeyboardActionExecutor`
- `CGEvent` / `CGEventFlags` 转换辅助

关键文件：

- [KeyboardMappingService.swift](/Users/tuoz/Workspace/projects/mymac/MyMac/Core/EventSystem/KeyboardMappingService.swift)
- [InputModels.swift](/Users/tuoz/Workspace/projects/mymac/MyMac/Core/Domain/InputModels.swift)

### 3.4 映射与注入逻辑

已完成：

- `Fn + H/J/K/L -> Left/Down/Up/Right`
- 输出时移除 `.fn`
- 保留非 `fn` 修饰键，例如：
  - `Cmd`
  - `Shift`
  - `Option`
  - `Control`
- 支持 `keyDown` / `keyUp`
- 保留 autorepeat 标志
- 为自注入事件写入 `eventMarker`
- tap 回调会过滤带相同 marker 的事件，避免递归映射

关键文件：

- [KeyMappingEngine.swift](/Users/tuoz/Workspace/projects/mymac/MyMac/Core/EventSystem/KeyMappingEngine.swift)
- [DefaultRuleSnapshotFactory.swift](/Users/tuoz/Workspace/projects/mymac/MyMac/Core/EventSystem/DefaultRuleSnapshotFactory.swift)

### 3.5 UI 联动

已完成：

- 设置页新增“请求权限”入口
- 设置页“请求权限”会在触发系统提示后立即同步权限与运行状态
- 设置页“重新检测”现在会刷新权限并立即协调运行状态
- 首次引导页新增“请求权限”入口
- 首次引导完成后会立即同步权限与运行状态
- `AppCoordinator` 会在启动、主动请求权限、首次引导完成、用户主动重新检测、应用回到前台时根据权限状态决定是否启动或停用真实映射服务
- `RuntimeStatus` 已增加 `tapDisabled`
- 菜单栏图标已能反映更多运行状态

关键文件：

- [SettingsView.swift](/Users/tuoz/Workspace/projects/mymac/MyMac/Features/Settings/SettingsView.swift)
- [OnboardingView.swift](/Users/tuoz/Workspace/projects/mymac/MyMac/Features/Onboarding/OnboardingView.swift)

### 3.6 测试与校验

已完成：

- 纯逻辑测试已更新到新接口
- 使用 Xcode 真实工具链完成了 `xcodebuild` Debug 构建
- 修复了 `MyMacTests` 的宿主绑定，`xcodebuild test` 已可正常执行
- 单测已覆盖权限服务、首次启动权限分支、手动“重新检测”、应用回前台自动刷新、功能关闭时不自动启动、已授权但底层启动失败等关键场景
- 已手工验证首次授权后的“重新检测”链路可正常恢复权限状态与功能，无需重启应用

已验证命令：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project MyMac.xcodeproj -scheme MyMac -configuration Debug -sdk macosx build

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test -project MyMac.xcodeproj -scheme MyMac -destination 'platform=macOS'
```

结论：

- 当前代码在编译层面是通的
- App target 与测试 target 都可正常构建和运行

## 4. 当前未完成项

以下内容尚未完成或尚未验证：

### 4.1 真实运行行为未做系统性手工验收

还没有完成以下真实场景验证：

- `Fn + H/J/K/L` 在文本编辑器中是否稳定生效
- `Fn + Cmd + H` 是否正确变成 `Cmd + Left`
- 原始 `HJKL` 是否完全被抑制
- autorepeat 在真实应用中是否接近系统方向键体验
- 外接键盘与内建键盘对 `Fn` 的表现是否一致

### 4.2 权限行为仍需跨环境验证

当前实现已统一为 `Accessibility` 驱动的权限模型，但以下点仍建议继续验证：

- 新 bundle identifier、DerivedData 运行、复制到 `/Applications` 运行时的授权体验是否一致
- 权限切换后 Event Tap 恢复是否在更多 macOS 版本和安装形态下稳定

### 4.3 tap 生命周期仍需经过真实场景验证

代码里已经实现了 timeout 恢复与状态降级，但还没有实际验证：

- 睡眠/唤醒后是否能稳定恢复
- 切换权限后是否能正确停启
- 连续长时间运行是否会出现 tap 失效

## 5. 已知风险与注意事项

### 5.1 `Fn` 判定仍然是重点风险点

当前实现已经有：

- `flagsChanged` 跟踪
- 事件 flags 转换
- `effectiveModifiers` 合并

但 `Fn` 在不同键盘设备上的行为仍然需要真实验证，尤其是：

- 内建键盘
- 外接机械键盘
- Globe/Fn 复用键

### 5.2 事件注入成功不等于用户体验完全正确

即使编译和注入都成功，仍可能在实际使用中遇到：

- 某些应用吞掉模拟方向键
- 组合修饰键语义不一致
- 长按节奏和系统不完全一致
- 某些输入法或终端对事件解释不同

### 5.3 当前工作区还有未跟踪本地文件

当前仓库里仍有一些不属于应用源码的本地项，例如：

- `.agents/`
- `skills-lock.json`
- 本地生成的 `.DS_Store`
- `xcuserdata`

它们不属于产品实现上下文，后续如果需要整理仓库，建议单独处理 `.gitignore`。

## 6. 推荐的下一步任务

按优先级建议如下：

### 任务 1：真实运行调试

目标：

- 启动应用
- 授权所需权限
- 在真实前台应用中验证 `Fn + H/J/K/L`
- 补充验证“从系统设置授权后切回应用自动恢复”的链路

重点观察：

- 原始 `HJKL` 是否泄漏
- 方向键是否被正确注入
- 组合修饰键是否保留
- 长按是否正常
- 自动恢复与手动“重新检测”是否都稳定

### 任务 2：日志与诊断增强

目标：

- 在不刷屏的前提下增加必要诊断信息

建议方向：

- 规则命中计数
- tap 启停原因
- 权限状态变化
- 注入失败原因

### 任务 3：稳定性补强

目标：

- 针对睡眠/唤醒、权限变化、tap 失效做恢复强化

建议方向：

- 更明确的恢复重试策略
- 更具体的 UI 状态提示
- 更清晰的失败路径日志

## 7. 后续任务接手建议

后续继续开发时，建议优先阅读以下文件：

1. [docs/technical-design.md](/Users/tuoz/Workspace/projects/mymac/docs/technical-design.md)
2. [AppCoordinator.swift](/Users/tuoz/Workspace/projects/mymac/MyMac/App/AppCoordinator.swift)
3. [KeyboardMappingService.swift](/Users/tuoz/Workspace/projects/mymac/MyMac/Core/EventSystem/KeyboardMappingService.swift)
4. [PermissionService.swift](/Users/tuoz/Workspace/projects/mymac/MyMac/Core/Services/PermissionService.swift)

如果后续任务目标是“继续把功能做稳”，最自然的切入点不是再改架构，而是：

- 直接运行应用
- 基于真实行为逐项验证需求
- 再对具体失败场景做定点修复

## 8. 一句话总结

当前项目已经完成了从“工程骨架”到“真实 CGEventTap 链路集成”的跨越，编译链路已打通；下一阶段的核心不再是继续搭结构，而是围绕真实运行行为做验证、调试与稳定性收口。
