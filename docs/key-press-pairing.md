# 按键按下与松开的配对

## 规则

一次物理按键在**首次 `keyDown`**（非 autorepeat）时决定去向，之后的 autorepeat 和 `keyUp` 都按这个决定处理，直到该键松开。实现见 `KeyPressRouter`。

- **映射**：Fn + Backspace/H/J/K/L 首次按下时注入目标键并记录。之后的重复和松开都发同一个目标键，即使 Fn 已经松开、映射开关已经关闭。
- **输入法切换**：Fn + Space 首次按下时切换并记录。之后的重复和松开都吞掉。
- **其他情况**：首次按下时没有命中的键不做记录。它的重复和松开原样放行，即使之后才按下 Fn。
- 多个键可以同时有记录，按各自的松开顺序配对。
- 重复和松开事件的输出修饰键按事件发生时的状态计算，只有 Fn 不会改变已经确定的去向。

## 异常处理

- **首次注入失败**：不建立记录，原始事件放行。
- **按住过程中注入失败**：记录诊断，原始事件仍然吞掉，`keyUp` 时结束记录。
- **残留记录**：同一个键再次首次按下时，如果还有它的记录（说明之前的 `keyUp` 丢了），先补发旧目标的 `keyUp`，再重新决定去向。
- **Tap 超时被禁用**：重新启用后，按 `CGEventSource.keyState(.hidSystemState, key:)` 检查记录中的物理键。已经松开的补发 `keyUp`，仍然按住的保留记录。
- **停止监听**：先给所有映射记录补发 `keyUp` 再清空。

## 已知限制

- **停止监听只能尽力恢复**：监听停止后，原始键的 `keyUp` 会原样放行，接收方会看到一个孤立的原始键 `keyUp`。
- **Secure Event Input**：在密码框等开启安全输入的地方，Event Tap 收不到按键事件。在此期间松开的映射键，记录会保留到这个键下次首次按下时才补发 `keyUp`。
- **同一 `keyCode` 来自多个来源**：多个物理键盘按下同一个 `keyCode`，或者物理方向键和映射出的同一方向键同时按下时，系统事件里没有足够的信息区分来源，这张记录表不能保证这些组合完全配对。

## 手动验证

用 `tools/KeyboardEventLogger.swift` 观察以下顺序，确认每个注入的 `keyDown` 都有对应的 `keyUp`：

1. Fn 按下 → Backspace 按下 → Fn 松开 → Backspace 松开
2. Fn 按下 → Backspace 按下 → J 按下 → Fn 松开 → J 松开 → Backspace 松开（再交换最后两步）
3. Backspace 按下 → Fn 按下 → Backspace 松开：整个过程都应该是原样的 Backspace
4. 长按 Fn + Backspace，中途松开 Fn：重复事件应该一直是 Forward Delete
5. Space 按下 → Fn 按下 → Space 松开：Space 的 `keyUp` 不应该被吞掉
