# 第三方键盘 F 区事件诊断结论

## 背景

MyMac 当前使用 macOS 可见的 `Fn` modifier（`CGEventFlags.maskSecondaryFn`）实现 `Fn + H/J/K/L` 方向键映射和 `Fn + Space` 输入法切换。

第三方键盘上常见的 Fn 键通常不是 macOS 的 Fn，而是键盘固件内部的 layer 切换键。它可能不会作为独立按键事件进入 macOS。因此，需要先确认第三方键盘 F 区实际发送给 macOS 的事件类型，再讨论是否能在 MyMac 中补救。

## 诊断工具

新增了独立 Swift 命令行工具：

```bash
swiftc tools/KeyboardEventLogger.swift -o /tmp/keyboard-event-logger
/tmp/keyboard-event-logger
```

该工具通过 `CGEventTap` 监听并打印：

- `keyDown`
- `keyUp`
- `flagsChanged`
- `systemDefined`

工具只观察事件，不消费、不修改、不注入事件。

## 已验证样本

在当前第三方键盘上，直接触发部分 F 区按键时，macOS 收到的是 `.systemDefined` 事件，而不是标准 F 键 keyCode。

| 物理按键 | macOS 收到的事件 | `nxKeyType` | 识别名称 |
| --- | --- | ---: | --- |
| `F1` | `systemDefined` | `3` | `brightnessDown` |
| `F2` | `systemDefined` | `2` | `brightnessUp` |
| `F11` | `systemDefined` | `1` | `soundDown` |
| `F12` | `systemDefined` | `0` | `soundUp` |

样例日志：

```text
systemDefined subtype=8 data1=199168 data1Hex=0x30A00 nxKeyType=3 nxKeyName=brightnessDown
systemDefined subtype=8 data1=133632 data1Hex=0x20A00 nxKeyType=2 nxKeyName=brightnessUp
systemDefined subtype=8 data1=68096 data1Hex=0x10A00 nxKeyType=1 nxKeyName=soundDown
systemDefined subtype=8 data1=2560 data1Hex=0xA00 nxKeyType=0 nxKeyName=soundUp
```

其中 `0xA00` / `0xB00` 分别对应按下 / 抬起。调试工具已修正状态解码，后续日志会显示为 `state=down` / `state=up`。

## 结论

这把第三方键盘的部分 F 区按键没有以标准 `F1`、`F2`、`F11`、`F12` keyCode 进入 macOS，而是以亮度、音量等系统功能键进入。

因此，当前问题不是 MyMac 没有识别标准 F 键，而是这些物理按键在进入 macOS 时已经不是标准 F 键。

这也说明：

- `Fn + H/J/K/L` 依赖 macOS 可见的 `maskSecondaryFn`，属于系统事件层映射。
- 第三方键盘自己的 Fn 多数属于固件 layer，和 macOS Fn 不是同一层概念。
- 将某个键映射成 macOS Fn 可以让 MyMac 识别 `Fn + H/J/K/L`，但不会自动改变第三方键盘 F 区的固件输出。

## 后续讨论方向

如果希望 MyMac 对这类键盘做软件补救，可以考虑新增一个独立的 F 区兼容模式：

- 捕获特定 `systemDefined` 事件。
- 将 `brightnessDown` / `brightnessUp` / `soundDown` / `soundUp` 等事件映射为标准 `F1` / `F2` / `F11` / `F12`。
- 对被映射的原始系统功能键事件进行消费，避免同时触发亮度或音量变化。

该方向应作为独立功能讨论，不应混入现有 `Fn + H/J/K/L` 映射逻辑。
