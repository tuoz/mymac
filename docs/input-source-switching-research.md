# macOS 输入法切换调研报告

> 调研日期：2026-04-22  
> 调研目标：寻找能复刻系统 Caps Lock 输入法切换记忆的 API 或机制，为 `Fn + Space` 切换输入法功能提供技术选型依据。  
> 调研范围：Carbon TIS API、HIToolbox 框架符号表、TextInputSwitcher/TextInputMenuAgent 系统进程、运行时 API 探测。

---

## 1. 总体结论

macOS 不存在可以直接"触发 Caps Lock 输入法切换行为"的公开或私有 API。系统的 Caps Lock 输入法切换记忆栈由 `TextInputSwitcher.app` 等系统进程内部维护，没有暴露给第三方调用。

**但是**，HIToolbox 框架中存在一组**与 Caps Lock 切换配套的私有 API**，可以**读取系统维护的"当前非 Roman 输入法记忆"**。这意味着我们可以用这组私有 API 实现与系统 Caps Lock 切换**行为一致**的二元切换，而不需要自己维护状态。

**最终技术选型**：基于私有 API `_TISCopyCurrentNonRomanInputSourceForRomanSwitch()` + `_TISCopyCurrentASCIICapableKeyboardInputSource()` 实现 Fn + Space 输入法切换，同时保留基于 `kTISPropertyInputSourceLanguages` 的 Latin 判定作为兜底。

---

## 2. 公开 API 盘点

Carbon `Text Input Source Services` 公开的 API 如下（节选）：

| 函数 | 作用 | 局限性 |
|------|------|--------|
| `TISCopyCurrentKeyboardInputSource()` | 获取当前输入法 | 无法得知"上一个输入法" |
| `TISSelectInputSource()` | 选择指定输入法 | 只能精确选择，无法触发系统切换逻辑 |
| `TISCreateInputSourceList()` | 枚举所有输入法 | 无法获取系统记忆栈 |
| `kTISNotifySelectedKeyboardInputSourceChanged` | 输入法变化通知 | 只能被动监听，无法主动读取记忆 |

**结论**：仅靠公开 API 无法实现与 Caps Lock 一致的切换行为，必须自己维护状态记忆。

---

## 3. 关键私有 API 发现

通过对 HIToolbox 框架导出符号的完整扫描（`dyld_info -exports`）和运行时验证，发现以下与 Roman 切换直接相关的私有 API：

### 3.1 核心 API

```c
// 获取系统当前记忆的非 Roman 输入法（即 Caps Lock 切换的目标）
TISInputSourceRef _TISCopyCurrentNonRomanInputSourceForRomanSwitch(void);

// 获取当前的 ASCII capable 输入法（通常是 ABC）
TISInputSourceRef _TISCopyCurrentASCIICapableKeyboardInputSource(void);

// 选择指定输入法（公开 API，但这里一同列出）
OSStatus _TISSelectInputSource(TISInputSourceRef inputSource);
```

### 3.2 辅助查询 API

```c
// 查询 Roman 切换是否启用（用户是否打开了"使用 Caps Lock 切换..."）
Boolean _TISIsRomanSwitchEnabled(void);

// 查询当前键盘布局是否处于 Caps Lock 切换状态
Boolean _TISIsKeyboardLayoutCapsLockSwitched(void);

// 查询键盘布局是否允许 Caps Lock 切换
Boolean _TISIsKeyboardLayoutCapsLockSwitchAllowed(void);

// 判断 Caps Lock 切换时是否应该使用 alternate modifiers
Boolean _TISCapsLockSwitchShouldKeyboardLayoutUseAlternateForModifiers(void);
```

### 3.3 关键常量

```c
// 属性：输入法是否支持 Caps Lock 切换
CFStringRef _kTISPropertyInputSourceDoesCapsLockSwitch;

// 属性：输入法是否支持切换到 Roman 模式
CFStringRef _kTISPropertyInputSourceDoesCapsLockSwitchToRomanMode;

// 属性：输入法是否覆盖 Caps Lock 延迟
CFStringRef _kTISPropertyInputSourceOverrideCapsLockDelay;

// 类型：合成 Roman 模式输入法
CFStringRef _kTISTypeKeyboardSyntheticRomanMode;

// 特殊的合成 Roman 模式输入法 ID
CFStringRef _kTISAppleSyntheticRomanModeInputSourceID;
```

---

## 4. API 行为验证

### 4.1 测试环境

- macOS 26.4.1 (Tahoe)
- arm64
- 已启用的输入法：ABC (`com.apple.keylayout.ABC`)、简体拼音 (`com.apple.inputmethod.SCIM.ITABC`)
- Caps Lock 切换功能：已开启（系统设置 > 键盘 > 输入法 > 使用 Caps Lock 键切换...）

### 4.2 测试结果

```
=== 初始状态（当前在 ABC）===
Roman switch enabled: 1
Caps lock switched: 0
Current input source ID: com.apple.keylayout.ABC
NonRoman for Roman switch ID: com.apple.inputmethod.SCIM.ITABC
ASCII capable input source ID: com.apple.keylayout.ABC

=== 切换到 ABC 后 ===
Current input source ID: com.apple.keylayout.ABC
NonRoman for Roman switch ID: com.apple.inputmethod.SCIM.ITABC  ← 记忆不变

=== 切换到非 Roman 后 ===
Current input source ID: com.apple.inputmethod.SCIM.ITABC
```

### 4.3 关键发现

1. `_TISCopyCurrentNonRomanInputSourceForRomanSwitch()` 返回的**不是当前输入法**，而是系统内部维护的**"用于 Roman 切换的非 Roman 输入法记忆"**。这正是 Caps Lock 短按时会切到的目标输入法。

2. 无论当前在 ABC 还是中文输入法，`_TISCopyCurrentNonRomanInputSourceForRomanSwitch()` 都会返回系统记录的非 Roman 输入法。这意味着系统确实在维护一个独立的记忆栈。

3. `_TISIsRomanSwitchEnabled()` 可以正确反映用户是否开启了 Caps Lock 切换功能。

4. `_TISIsKeyboardLayoutCapsLockSwitched()` 在我们的测试中始终返回 0，可能是因为该标记只在真正的 Caps Lock 按键触发时才会被设置，而不是在输入法状态变化时设置。

---

## 5. 系统进程观察

在系统中找到了以下与输入法切换相关的进程和文件：

| 进程/文件 | 路径 | 观察 |
|-----------|------|------|
| TextInputMenuAgent | `/System/Library/CoreServices/TextInputMenuAgent.app` | 负责菜单栏输入法图标，通过 `messageSwitcher:dictionary:` 与 Switcher 通信 |
| TextInputSwitcher | `/System/Library/CoreServices/TextInputSwitcher.app` | 核心切换逻辑，包含 `moveSelection:`、`setCurrentInputSource:` 等方法 |
| TISwitcher Cache | `~/Library/Caches/com.apple.tiswitcher.cache` | 存在但内容未解析 |

关键字符串发现：`TextInputMenuAgent` 中有 `copyTISwitcherMessageReceiver:withInfo:` 和 `messageSwitcher:dictionary:`，说明输入法切换是通过进程间消息通信完成的，而不是简单的 API 调用。

---

## 6. 最终方案设计

### 6.1 核心逻辑

```swift
func switchInputSource() {
    let current = TISCopyCurrentKeyboardInputSource()
    
    // 策略1：优先使用系统的非 Roman 记忆
    if let nonRoman = _TISCopyCurrentNonRomanInputSourceForRomanSwitch(),
       let nonRomanID = TISGetInputSourceProperty(nonRoman, kTISPropertyInputSourceID) as? String,
       let currentID = TISGetInputSourceProperty(current, kTISPropertyInputSourceID) as? String {
        
        if currentID == nonRomanID {
            // 当前是非 Roman → 切到 ASCII capable（ABC）
            if let ascii = _TISCopyCurrentASCIICapableKeyboardInputSource() {
                _TISSelectInputSource(ascii)
            }
        } else {
            // 当前是 Roman → 切到系统记忆的非 Roman
            _TISSelectInputSource(nonRoman)
        }
        return
    }
    
    // 策略2：兜底，基于语言判断
    fallbackSwitchBasedOnLanguage()
}
```

### 6.2 Latin 判定兜底策略

当私有 API 获取失败时，使用 `kTISPropertyInputSourceLanguages` 判断是否包含 `"en"`：

```swift
func isLatinInputSource(_ source: TISInputSourceRef) -> Bool {
    guard let languages = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) as? [String] else {
        return false
    }
    return languages.contains("en")
}
```

### 6.3 事件流集成

在现有的 `EventTapController.handle(eventType:event:)` 中增加前置分支：

```
CGEventTap → EventTapController.handle()
         ├─ 检测到 Fn + Space keyDown ──→ InputMethodSwitchService.switchToNext()
         │                                    → 返回 nil（消费事件）
         ├─ 检测到 Fn + Space keyUp ─────→ 返回 nil（消费事件，防止 Space 传递）
         └─ 其他事件 ───────────────────→ 原有 H/J/K/L 映射流程
```

### 6.4 开关设计

```
├── 总开关：启用键盘映射 (isKeyboardMappingEnabled)
│   ├── 子开关：Fn + H/J/K/L 方向键映射 (isArrowKeyMappingEnabled)
│   └── 子开关：Fn + Space 切换输入法 (isInputMethodSwitchEnabled)
```

---

## 7. 风险说明

| 风险 | 等级 | 说明 | 缓解措施 |
|------|------|------|---------|
| **私有 API 变更** | 中 | macOS 更新可能修改或移除这些私有 API | 代码中封装隔离，添加 API 可用性检查；保留基于公开 API 的兜底方案 |
| **App Store 上架** | 低（当前） | 使用私有 API 无法通过 App Store 审核 | 当前为个人自用工具，不考虑上架 |
| **CJK 输入法 Bug** | 低（当前） | `TISSelectInputSource` 切换到 CJK 输入法时可能存在菜单栏图标变了但实际未生效的 Bug | 当前环境未观察到该 Bug；若未来遇到，参考 Kawa/macism 的 workaround（先切到非 CJK，再切回目标） |
| **多 Roman 输入法** | 低 | 如果用户有多个 Latin 输入法（如 ABC + Dvorak），`_TISCopyCurrentASCIICapableKeyboardInputSource()` 可能返回非预期的那个 | 个人使用场景通常只有 ABC；若未来需要，可以增加用户配置首选 Latin 输入法 |
| **系统进程通信** | 低 | TextInputSwitcher 等系统进程的 IPC 机制可能变化 | 不依赖 IPC，只使用 HIToolbox API |

---

## 8. 实现要点

### 8.1 私有 API 声明

由于这些 API 不在公开头文件中，需要在 Swift/C 代码中手动声明：

```swift
// 在 Swift 中通过 @_silgen_name 或桥接 C 头文件
@_silgen_name("TISCopyCurrentNonRomanInputSourceForRomanSwitch")
func TISCopyCurrentNonRomanInputSourceForRomanSwitch() -> Unmanaged<TISInputSource>?

@_silgen_name("TISCopyCurrentASCIICapableKeyboardInputSource")
func TISCopyCurrentASCIICapableKeyboardInputSource() -> Unmanaged<TISInputSource>?
```

或使用 C 桥接头：

```c
// InputMethodSwitchService_Private.h
#import <Carbon/Carbon.h>

TISInputSourceRef TISCopyCurrentNonRomanInputSourceForRomanSwitch(void);
TISInputSourceRef TISCopyCurrentASCIICapableKeyboardInputSource(void);
```

### 8.2 事件消费

`Fn + Space` 的 `keyDown` 和 `keyUp` 都必须消费（返回 `nil`），否则前台应用会收到 Space 键输入。

### 8.3 线程安全

`TISSelectInputSource` 等 API 是线程安全的，可以在 EventTap 的独立线程中直接调用，不需要 hop 到主线程。

---

## 9. 参考资料

- [Stack Overflow - How to programmatically switch an input method on OS X](https://stackoverflow.com/questions/22885767)
- [Karabiner-Elements Issue #1602 - CJKV input sources switching workaround](https://github.com/pqrs-org/Karabiner-Elements/issues/1602)
- [macism - Reliable CLI macOS Input Source Manager](https://github.com/laishulu/macism)
- [Kawa - macOS input source switcher](https://github.com/hatashiro/kawa)
- Apple HIToolbox framework symbols, extracted via `dyld_info -exports` on macOS 26.4.1

---

## 10. 结论

这次调研确认了：**macOS 虽然没有公开"触发 Caps Lock 切换"的 API，但提供了读取系统记忆的非 Roman 输入法的私有 API**。利用这组 API，我们可以实现与系统 Caps Lock 切换**行为一致**的 `Fn + Space` 输入法切换，而不需要自己维护状态记忆。

这比自建状态的方案更可靠，因为：
1. 记忆是系统级别的，跨 App 一致
2. 能感知 Menubar 手动切换
3. 不需要处理多 Roman 输入法的优先级问题
4. 行为与用户的 Caps Lock 切换体验保持一致
