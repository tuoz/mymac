# macOS 输入法切换调研报告

> 调研日期：2026-04-22，2026-04-24  
> 调研目标：验证是否可以通过调用私有 TIS API，复刻系统 `Caps Lock` 的输入法切换行为，并为 `Fn + Space` 切换输入法功能提供实现依据。  
> 调研范围：Carbon TIS API、HIToolbox 框架符号表、运行时私有符号解析、真实 `Caps Lock` 行为对照、临时执行器验证。

---

## 1. 总体结论

在当前环境下，即：

- macOS 26.4.1 (Tahoe)
- 已启用输入源仅为 `ABC` (`com.apple.keylayout.ABC`) 与简体拼音 (`com.apple.inputmethod.SCIM.ITABC`)
- 系统设置中“使用中/英键切换到/离开 ABC”已开启

报告中的私有 TIS API 方案已经被验证**可以复刻系统 `Caps Lock` 的输入法切换行为**。因此，在当前样本范围内，它可以作为 `Fn + Space` 输入法切换的实现路径。

这里的“可复刻”不是指“能做一个抽象的二元切换”，而是指：执行器读取系统维护的 `nonRomanTarget`，并在 `ABC` 与系统记忆的非 Roman 输入法之间进行切换。真实 `Caps Lock` 与该执行器在当前样本下表现一致。

但这个结论**仅覆盖当前 `ABC + 简体拼音` 场景**。日文、韩文、多 Roman 布局与 synthetic Roman mode 仍未验证，因此当前报告不将这一结论泛化到所有输入法状态机。

---

## 2. 公开 API 盘点

Carbon `Text Input Source Services` 中，与本次调研直接相关的公开 API 如下：

| 函数 / 常量 | 作用 | 当前结论 |
|------|------|--------|
| `TISCopyCurrentKeyboardInputSource()` | 获取当前输入法 | 已验证可用 |
| `TISCopyCurrentKeyboardLayoutInputSource()` | 获取当前 keyboard layout | 已验证可用 |
| `TISCopyCurrentASCIICapableKeyboardInputSource()` | 获取当前 ASCII capable 输入源 | 已验证可用 |
| `TISSelectInputSource()` | 选择指定输入源 | 已验证可用 |
| `TISCreateInputSourceList()` | 枚举输入源 | 已验证可用 |
| `kTISPropertyInputSourceIsASCIICapable` | 标识输入源是否为 ASCII capable | 应作为兜底主判断 |
| `kTISPropertyInputSourceLanguages` | 输入源语言数组 | 仅作为辅助观察值 |

**结论**：仅靠公开 API 可以完成“显式选择输入源”，但不能直接读取系统维护的 `Caps Lock` 非 Roman 记忆目标。因此，若要追求与系统 `Caps Lock` 行为一致，仍需要读取私有状态。

---

## 3. API 分类与运行时发现

### 3.1 公开 API

以下 API 在 SDK 头文件中可见，并已在临时工具中验证可调用：

```c
TISInputSourceRef TISCopyCurrentKeyboardInputSource(void);
TISInputSourceRef TISCopyCurrentKeyboardLayoutInputSource(void);
TISInputSourceRef TISCopyCurrentASCIICapableKeyboardInputSource(void);
OSStatus TISSelectInputSource(TISInputSourceRef inputSource);
```

### 3.2 私有 API

以下私有函数与常量出现在 `dyld_info -exports` 输出中，并已在修正后的运行时实验中成功解析：

```c
TISInputSourceRef TISCopyCurrentNonRomanInputSourceForRomanSwitch(void);
Boolean TISIsRomanSwitchEnabled(void);
Boolean TISIsKeyboardLayoutCapsLockSwitchAllowed(void);
Boolean TISIsKeyboardLayoutCapsLockSwitched(void);

CFStringRef kTISPropertyInputSourceDoesCapsLockSwitch;
CFStringRef kTISPropertyInputSourceDoesCapsLockSwitchToRomanMode;
CFStringRef kTISTypeKeyboardSyntheticRomanMode;
CFStringRef kTISAppleSyntheticRomanModeInputSourceID;
```

其中，`kTISPropertyInputSourceDoesCapsLockSwitch` 与 `kTISPropertyInputSourceDoesCapsLockSwitchToRomanMode` 本轮未被纳入主行为判定链路，但它们表明系统内部可能存在更细粒度的 Caps Lock / Roman mode 能力标记。因此，这两项当前只作为旁证保留，不作为本报告主结论的必要依据。

### 3.3 方法学更正

本次调研中，一个关键错误已经被纠正：

1. `dyld_info -exports` 显示的是 Mach-O 导出名，通常带前导下划线，例如 `_TISCopyCurrentNonRomanInputSourceForRomanSwitch`。
2. 运行时 `dlsym` 应传入源码符号名，例如 `TISCopyCurrentNonRomanInputSourceForRomanSwitch`，而不是带前导下划线的导出字符串。
3. 因此，先前基于下划线名称得到的“私有符号不可解析”结论是**方法错误导致的假阴性**，不成立。

修正后，以下运行时解析已验证成功：

- `TISCopyCurrentNonRomanInputSourceForRomanSwitch`
- `TISIsRomanSwitchEnabled`
- `TISSelectInputSource`
- `TISCopyCurrentASCIICapableKeyboardInputSource`
- `kTISTypeKeyboardSyntheticRomanMode`
- `kTISAppleSyntheticRomanModeInputSourceID`

---

## 4. 实验结果

### 4.1 环境

- macOS 26.4.1 (Tahoe)
- arm64
- 已启用输入源：
  - `ABC` (`com.apple.keylayout.ABC`)
  - `Pinyin – Simplified` (`com.apple.inputmethod.SCIM.ITABC`)
- 系统设置中“使用中/英键切换到/离开 ABC”已开启

### 4.2 私有 API 调用结果

修正 `dlsym` 名称后，独立临时 C 程序已成功调用以下私有函数：

```text
TISIsRomanSwitchEnabled() == true
TISCopyCurrentNonRomanInputSourceForRomanSwitch() == com.apple.inputmethod.SCIM.ITABC
```

这说明当前机器正处于适合验证 `Caps Lock` 记忆切换的真实状态。

### 4.3 私有 API 执行器结果

使用以下执行逻辑构造临时执行器：

```swift
let current = TISCopyCurrentKeyboardInputSource()
let nonRomanTarget = TISCopyCurrentNonRomanInputSourceForRomanSwitch()
let asciiTarget = TISCopyCurrentASCIICapableKeyboardInputSource()

if current == nonRomanTarget {
    TISSelectInputSource(asciiTarget)
} else {
    TISSelectInputSource(nonRomanTarget)
}
```

验证结果如下：

- 当当前输入源为简体拼音时，执行器走 `nonroman -> ascii`，切换到 `ABC`
- 当当前输入源为 `ABC` 时，执行器走 `ascii -> nonroman`，切换到简体拼音
- 连续 6 次往返切换稳定，无状态漂移
- `currentNonRoman` 始终保持为 `com.apple.inputmethod.SCIM.ITABC`
- 单次执行耗时约 `208ms` 到 `238ms`（该值包含 `200ms` 的 settle 等待时间；实测 `TISSelectInputSource()` 本身仅耗时约 `2ms–23ms`，`P50 ≈ 7ms`）

### 4.4 真实 `Caps Lock` 对照结果

以真实 `Caps Lock` 作为真值基准，对当前样本做了双向对照：

1. 第 1 组：
   - 初始状态：`ABC`
   - 真实 `Caps Lock` 后：切换到 `com.apple.inputmethod.SCIM.ITABC`
   - 与执行器的 `ascii -> nonroman` 结果一致

2. 第 2 组：
   - 初始状态：`com.apple.inputmethod.SCIM.ITABC`
   - 真实 `Caps Lock` 后：切换到 `ABC`
   - 与执行器的 `nonroman -> ascii` 结果一致

在这两组对照中，以下维度均一致：

- 切换目标输入源
- 切换后的 keyboard layout
- 切换后的 `currentNonRoman`

**结论**：在当前 `ABC + 简体拼音` 场景下，该私有 API 执行器与真实 `Caps Lock` 行为一致。

---

## 5. 系统进程观察

系统中仍能观察到以下与输入法切换相关的进程和文件：

| 进程/文件 | 路径 | 观察 |
|-----------|------|------|
| TextInputMenuAgent | `/System/Library/CoreServices/TextInputMenuAgent.app` | 负责菜单栏输入法图标 |
| TextInputSwitcher | `/System/Library/CoreServices/TextInputSwitcher.app` | 核心切换逻辑相关进程 |
| TISwitcher Cache | `~/Library/Caches/com.apple.tiswitcher.cache` | 存在但本轮未作进一步解析 |

本轮调研没有继续依赖 IPC 逆向来下结论，因为仅通过 TIS API 与真实 `Caps Lock` 对照，已经足以回答当前调研目的。

---

## 6. 已验证方案设计

### 6.1 核心逻辑

当前样本下已验证有效的实验逻辑如下。它描述的是 TIS 调用顺序，不等同于产品代码中的具体类型划分：

```swift
func switchInputSource() {
    // 这里依赖 Swift 对 Create/Copy 规则返回值的桥接管理；若改为 dlsym / C 层调用，需要显式处理对象所有权。
    guard
        let current = TISCopyCurrentKeyboardInputSource(),
        let nonRomanTarget = TISCopyCurrentNonRomanInputSourceForRomanSwitch(),
        let asciiTarget = TISCopyCurrentASCIICapableKeyboardInputSource(),
        let currentID = TISGetInputSourceProperty(current, kTISPropertyInputSourceID) as? String,
        let nonRomanID = TISGetInputSourceProperty(nonRomanTarget, kTISPropertyInputSourceID) as? String
    else {
        fallbackSwitchBasedOnASCIICapability()
        return
    }

    if currentID == nonRomanID {
        TISSelectInputSource(asciiTarget)
    } else {
        TISSelectInputSource(nonRomanTarget)
    }
}
```

### 6.2 当前结论的真正含义

这个方案的价值不在于“恰好做了一个二元切换”，而在于：

- 它读取了系统维护的 `nonRomanTarget`
- 它复用了系统的非 Roman 记忆，而不是应用自行维护“上一个输入法”状态
- 在当前样本下，它与真实 `Caps Lock` 的双向行为一致

因此，它优于单纯在应用内部维护 `ABC <-> 拼音` 切换状态的粗糙方案。

### 6.3 兜底策略

若未来私有 API 不可用，兜底主判断应基于：

```swift
kTISPropertyInputSourceIsASCIICapable
```

而不是：

```swift
languages.contains("en")
```

`kTISPropertyInputSourceLanguages` 仍可作为辅助观察值，但不应再被用作 Latin / Roman 的主定义。

### 6.4 当前事件流集成

当前代码的 `Fn + Space` 接入链路如下：

```text
CGEventTap → EventTapController.handle()
         ├─ 检测到 Fn + Space keyDown ──→ InputSourceSwitchTrigger.trigger()
         │                                    → 主队列异步调用
         │                                    → InputSourceSwitchService.switchRomanNonRoman()
         │                                    → CarbonInputSourceSwitchingClient.selectInputSource()
         │                                    → TISSelectInputSource(target)
         │                                    → 返回 nil（消费事件）
         ├─ 检测到 Fn + Space keyUp ─────→ 返回 nil（消费事件）
         └─ 其他事件 ───────────────────→ 原有 H/J/K/L 映射流程
```

`DefaultInputSourceSwitchService` 优先使用系统维护的 non-Roman 目标和 ASCII capable 目标；这些信息不完整时，才按 ASCII capable 属性从已启用输入源中回退选择。每次触发只选择一次目标，成功或失败后立即结束。

实际切换在 event tap 回调外通过主队列异步执行，回调本身只负责识别、消费事件和投递请求；实验中关于同步放入回调的耗时与风险观察保留为实验资料，不是当前实现方式。

---

## 7. 风险说明

| 风险 | 等级 | 说明 | 缓解措施 |
|------|------|------|---------|
| **样本范围有限** | 高 | 当前结论只覆盖 `ABC + 简体拼音` | 后续补做日文、韩文、多 Roman、synthetic Roman mode 样本 |
| **复杂输入法状态机未覆盖** | 高 | 尚未验证更复杂输入法是否仍与 `Caps Lock` 一致 | 将复杂输入法场景单独列为后续验证项 |
| **私有 API 变更** | 中 | 系统升级可能修改或移除相关私有 API | 代码中封装隔离；保留公开 API 兜底路径 |
| **`CGEventTap` 同步调用阻塞风险** | 低 | 产品代码不在 event tap 回调内同步调用 TIS，而是投递到主队列异步执行；实验中的 `2ms–23ms`（`P50 ≈ 7ms`）仅作为调用耗时参考 | 保持回调轻量，切换逻辑在回调外执行 |
| **`CGEventTap` 集成方式** | 低 | 当前实现由 `EventTapController` 消费 `Fn + Space`，再通过 `InputSourceSwitchTrigger` 异步触发单次切换 | 保留单飞和 generation 取消保护，避免停用后执行过期请求 |
| **App Store 上架** | 低 | 使用私有 API 无法通过 App Store 审核 | 当前为个人自用工具，不考虑上架 |
| **多 Roman 输入源优先级** | 低 | 当前未覆盖第二 Roman 布局场景 | 若后续需要，可增加用户配置首选 Roman 输入源 |
| **`TISIsKeyboardLayoutCapsLockSwitched` 导致进程挂起** | 中 | 该函数从独立进程调用时会永久阻塞（120s 超时验证）；`TISIsKeyboardLayoutCapsLockSwitchAllowed` 同样 | 生产代码中**禁止调用**；只需使用 `TISCopyCurrentNonRomanInputSourceForRomanSwitch` 和 `TISIsRomanSwitchEnabled` 即可 |

> **评审补充**（2026-04-24）：独立验证发现关闭系统设置「使用中/英键切换到/离开 ABC」后，`TISIsRomanSwitchEnabled()` 仍返回 `true`，`TISCopyCurrentNonRomanInputSourceForRomanSwitch()` 仍返回正确目标。因此 Fn+Space 输入法切换功能不依赖该系统设置。

---

## 8. 实现要点

### 8.1 私有 API 解析方式

本轮调研最终采信的是**运行时解析已验证的调用方式**，而不是最初那组未经校正的声明草案。

关键点：

- `dyld_info -exports` 看到的是带前导下划线的导出名
- `dlsym` 传入的应是源码符号名

例如：

```c
void *handle = dlopen("/System/Library/Frameworks/Carbon.framework/Versions/A/Frameworks/HIToolbox.framework/Versions/A/HIToolbox", RTLD_NOW);
void *symbol = dlsym(handle, "TISCopyCurrentNonRomanInputSourceForRomanSwitch");
```

### 8.2 事件消费

`Fn + Space` 的 `keyDown` 和 `keyUp` 都应消费（返回 `nil`），否则前台应用会收到 `Space` 键输入。

### 8.3 线程与集成

普通线程调用已验证可行。当前产品实现遵循回调轻量原则：`EventTapController` 只消费 `Fn + Space` 并投递请求，`InputSourceSwitchTrigger` 再通过主队列异步调用 `switchRomanNonRoman()`；该调用成功或失败后不再执行额外 re-select。

实验中记录的 `TISSelectInputSource()` 调用耗时约 `2ms–23ms`（`P50 ≈ 7ms`）仍可用于评估系统调用本身，但不改变当前异步集成设计。

---

## 9. 参考资料

- [Stack Overflow - How to programmatically switch an input method on OS X](https://stackoverflow.com/questions/22885767)
- [Karabiner-Elements Issue #1602 - CJKV input sources switching workaround](https://github.com/pqrs-org/Karabiner-Elements/issues/1602)
- [macism - Reliable CLI macOS Input Source Manager](https://github.com/laishulu/macism)
- [Kawa - macOS input source switcher](https://github.com/hatashiro/kawa)
- Apple HIToolbox framework symbols, extracted via `dyld_info -exports` on macOS 26.4.1
- 本轮外部临时实验记录：`/tmp/mymac-input-source-lab-KjnGuk/`

---

## 10. 结论

本次调研已经验证：**在当前 `ABC + 简体拼音`、且系统已开启 `Caps Lock` 切换 ABC 的真实环境下，报告中的私有 TIS API 方案能够复刻系统 `Caps Lock` 的输入法切换行为。**

因此，从工程角度看，这条私有 API 路线已经足以作为 `Fn + Space` 输入法切换的实现路径，而不必退回到应用自行维护“上一个输入法”状态的方案。

但这个结论当前**不能泛化到所有输入法场景**。日文、韩文、多 Roman 布局与 synthetic Roman mode 仍未验证，因此后续若需要扩大适用范围，应继续补齐这些样本。

当前代码已完成 event tap 集成：回调只识别并消费快捷键，实际输入源选择通过主队列异步执行。后续验证重点仍是不同输入法样本下的目标选择行为，而不是再引入延迟 re-select workaround。

---

## 11. 当前集成实现（2026-08-31）

应用在 `Fn + Space` 的 keyDown 时消费事件，并在主队列异步执行一次输入源选择：

```text
CGEventTap → EventTapController.handle()
         → InputSourceSwitchTrigger.trigger()
         → DispatchQueue.main.async
         → switchRomanNonRoman()
         → TISSelectInputSource(target)
```

目标仍优先使用系统维护的 non-Roman 输入源，并在该信息不可用时基于 ASCII capable 属性回退。一次选择成功或失败后，本次触发立即结束；实现不会延迟重新选择当前输入源。

此前曾在特定环境中试验过延迟重新选择的 workaround。实际使用表明它未能解决输入法切换问题，因此已从产品代码移除；关于固定延迟、重新激活路径和底层机制的结论不再作为实现依据。
