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

            Text("这是一个面向 macOS 的后台快捷键工具。第一版会提供菜单栏入口、权限引导、自启动开关，以及键盘映射服务的工程骨架。")
                .foregroundStyle(.secondary)

            GroupBox("开始前需要知道") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. 实际键盘监听功能后续会依赖系统权限。")
                    Text("2. 你可以现在就决定是否启用开机启动。")
                    Text("3. 这版工程骨架已经把菜单栏、设置和状态管理接好。")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Toggle("开机启动", isOn: $enableLaunchAtLogin)

            HStack {
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
