# `Fn + H/J/K/L` 映射问题排查与修复经验

## 1. 背景

本次问题的表象是：

- `fn + cmd + l` 可以正常等价为 `cmd + right`
- `fn + ctrl + l` 日志显示已经命中映射、也成功注入了 `right` 事件，但实际没有触发 `ctrl + right`

这类问题很容易误判成：

- 没有正确监听到 `ctrl`
- 没有发出 `keyDown` 或 `keyUp`
- 需要单独补发 modifier 键的按下/抬起事件

最终排查结果表明，上述判断都不是根因。

## 2. 这次修复里最重要的结论

### 2.1 要参考 `Mousepad` 的“事件语义”，不要照搬它的结构

真正需要参考的是：

- 用 `CGEvent(keyboardEventSource:virtualKey:keyDown:)` 创建目标方向键事件
- 把修饰键作为同一个方向键事件的 `flags` 传入
- 用 `.cgSessionEventTap` 注入

不需要模仿：

- 它的类结构
- 它的文件拆分
- 它的接口风格

### 2.2 `modifier` 不是单独注入的键

对于 `fn + ctrl + l -> ctrl + right` 这类映射，正确模型是：

- 捕获原始 `l` 的 `keyDown` / `keyUp`
- 若有效 flags 含 `fn`，只生成一个方向键事件
- 这个方向键事件本身携带“去掉 `fn` 之后的其他 modifiers”

错误模型是：

- 先发 `ctrl keyDown`
- 再发 `right keyDown`
- 再发 `right keyUp`
- 最后发 `ctrl keyUp`

这个模型和 `Mousepad` 处理 `modifier + arrow` 的方式并不一致，也会把问题带偏。

### 2.3 用于“匹配”的 flags 和用于“输出”的 flags 不能混为一谈

匹配阶段需要：

- 用当前事件的 flags
- 再并上 `flagsChanged` 跟踪到的活跃修饰键

这样可以覆盖 `fn + ctrl + l` 几乎同时按下时，`l` 自身 `event.flags` 不完整的情况。

但输出阶段不能直接拿“标准化后的高位 modifier 集合”去重建一个新事件。  
这次 bug 的关键教训就是：

- 匹配时可以做 `sanitize`
- 输出时要尽量保留原始 `event.flags` 的 raw bits

### 2.4 `ctrl` 比 `cmd` 更依赖原始 raw flags

这次日志非常有价值，因为它证明了：

- `fn + cmd + l` 在旧实现里已经能工作
- `fn + ctrl + l` 在旧实现里不能工作

两者都完成了：

- 监听
- 映射
- 注入

但只有 `ctrl` 失败，说明问题不是“大方向错了”，而是注入出来的 `ctrl + right` 还不够“像系统原生事件”。

最终定位点是：

- 旧实现把输出 flags 过度简化成了自定义筛选后的 modifier 掩码
- 这会丢掉原始事件中的低位 raw bits
- `cmd` 对这些位不敏感，`ctrl` 更敏感

## 3. 最终生效的修复原则

### 3.1 匹配规则

- 只处理 `h/j/k/l` 的 `keyDown` / `keyUp`
- 只在有效 flags 包含 `fn` 时命中
- `effectiveFlags = sanitize(event.flags) ∪ sanitize(trackedFlags)`

### 3.2 输出规则

- 输出事件只生成一次
- 输出 keyCode 为方向键
- 输出 flags 以原始 `event.flags` 为基础
- 只移除 `.maskSecondaryFn`
- 如果 `trackedFlags` 里有当前事件缺失的相关 modifier，再补进去

简化后可理解为：

`outputFlags = rawEventFlags - fn + missingTrackedModifiers`

### 3.3 注入规则

- 使用 `CGEvent(keyboardEventSource: nil, virtualKey: targetKeyCode, keyDown: ...)`
- 对事件使用 `event.flags.insert(outputFlags)`
- 不要直接用“重建后的纯 modifier flags”完全覆盖事件 flags
- 使用 `.cgSessionEventTap` 注入
- 使用 `eventSourceUserData` marker 避免递归映射

## 4. 这次日志排查为什么有效

最终决定性日志链路是：

- `flagsChanged`
- `Received event`
- `Mapped event`
- `Injected target`
- `Ignored injected event`

它回答了几个关键问题：

1. 原始修饰键有没有收到
2. `fn` 和 `ctrl/cmd` 有没有同时进入有效匹配条件
3. 是否已经成功生成目标方向键事件
4. 注入事件有没有真的被系统接收并回流到 tap
5. 注入前后的 flags 有没有发生异常变化

没有这套日志，很容易在“是不是没发 keyUp”“是不是得单独发 modifier”这些方向上继续误改。

## 5. 以后再遇到类似问题的排查顺序

建议固定按这个顺序看：

1. 看 `flagsChanged` 是否收到了目标修饰键
2. 看原始 `keyDown/keyUp` 是否命中目标字母键
3. 看 `effectiveFlags` 是否真的包含 `fn + 其他修饰键`
4. 看 `Mapped event` 的目标方向键和输出 flags 是否符合预期
5. 看 `Injected target` 之后是否有带 marker 的回流事件
6. 如果 `cmd` 能用但 `ctrl/option/shift` 不能用，优先怀疑 raw flags 在输出时被抹掉了

## 6. 当前实现的经验结论

对于 `Fn + H/J/K/L -> Arrow` 这条链路，当前应坚持以下原则：

- 事件监听直接使用 `CGEventTap`
- 修饰键跟踪直接使用 `CGEventFlags`
- 命中时只注入一个目标方向键事件
- `fn` 只用于匹配，不应出现在输出事件中
- 输出 flags 应尽量保留原始 raw bits，而不是只保留抽象后的 modifier 掩码
- `Mousepad` 的价值在于验证系统 API 的正确用法，而不是提供当前项目的架构模板
