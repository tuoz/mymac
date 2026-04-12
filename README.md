# MyMac

MyMac 是一个轻量的 macOS 后台菜单栏工具，专注把 `Fn + H/J/K/L` 映射成方向键，让你更顺手地在键盘主区完成移动操作。

它会尽量保留 `Cmd`、`Shift`、`Option`、`Control` 等其他修饰键，所以你可以继续自然组合使用，比如 `Fn + Cmd + H`、`Fn + Shift + L`。

## 特性

- 菜单栏常驻，默认无 Dock 图标
- `Fn + H/J/K/L` 映射为 `Left/Down/Up/Right`
- 保留其他修饰键，便于组合操作
- 支持开机启动
- 首次启动引导与权限提示

## 系统要求

- macOS 14.0 或更高版本
- Xcode（支持 Swift 6）
- 需要开启 Accessibility 权限

## 快速开始

1. 用 Xcode 打开 `MyMac.xcodeproj`
2. 运行应用
3. 按提示在系统设置中授予 Accessibility 权限
4. 在菜单栏或设置页中启用键盘映射
5. 直接使用 `Fn + H/J/K/L`

## 映射规则

| 输入 | 输出 |
| --- | --- |
| `Fn + H` | `Left` |
| `Fn + J` | `Down` |
| `Fn + K` | `Up` |
| `Fn + L` | `Right` |

## 本地构建

```bash
xcodebuild -project MyMac.xcodeproj -scheme MyMac -configuration Debug build
```

运行测试：

```bash
xcodebuild test -project MyMac.xcodeproj -scheme MyMac -destination 'platform=macOS'
```

## 说明

个人自用
