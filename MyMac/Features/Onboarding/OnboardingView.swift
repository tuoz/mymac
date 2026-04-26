import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState

    let coordinator: AppCoordinator
    let initialLaunchAtLoginEnabled: Bool

    @State private var enableLaunchAtLogin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("欢迎使用 MyMac")
                .font(.largeTitle)
                .bold()

            Text("这是一个面向 macOS 的后台快捷键工具。现在它会尝试把 Fn + H/J/K/L 映射成方向键，并通过 Fn + Space 切换 Roman 与非 Roman 输入法。")
                .foregroundStyle(.secondary)

            GroupBox("开始前需要知道") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. MyMac 需要 Accessibility 权限才能拦截并重发按键事件。")
                    Text("2. 你可以现在就决定是否启用开机启动。")
                    Text("3. 菜单栏、设置和运行状态会随着权限与监听状态实时更新。")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Toggle("开机启动", isOn: $enableLaunchAtLogin)

            HStack {
                Button("请求权限") {
                    Task {
                        await coordinator.requestPermissions()
                    }
                }

                Button("打开系统设置") {
                    coordinator.openSystemSettings()
                }

                Spacer()

                Button("完成并开始使用") {
                    Task {
                        await coordinator.completeOnboarding(enableLaunchAtLogin: enableLaunchAtLogin)
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 540, minHeight: 380, alignment: .topLeading)
        .task {
            enableLaunchAtLogin = initialLaunchAtLoginEnabled
        }
    }
}
