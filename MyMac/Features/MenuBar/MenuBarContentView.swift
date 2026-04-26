import SwiftUI

struct MenuBarContentView: View {
    @Environment(AppState.self) private var appState

    let coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label(appState.runtimeStatus.displayName, systemImage: appState.menuBarSystemImage)
                    .font(.headline)
                Text("权限：\(appState.permissionSummary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("开机启动：\(appState.launchAtLoginStatus.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Toggle("启用方向键映射", isOn: Binding(
                get: { appState.isKeyboardMappingEnabled },
                set: { newValue in
                    Task {
                        await coordinator.setKeyboardMappingEnabled(newValue)
                    }
                }
            ))

            Toggle("启用输入法切换", isOn: Binding(
                get: { appState.isInputSourceSwitchingEnabled },
                set: { newValue in
                    Task {
                        await coordinator.setInputSourceSwitchingEnabled(newValue)
                    }
                }
            ))

            Toggle("开机启动", isOn: Binding(
                get: { coordinator.isLaunchAtLoginToggleOn },
                set: { newValue in
                    coordinator.setLaunchAtLoginEnabled(newValue)
                }
            ))

            Divider()

            Button("打开设置") {
                coordinator.showSettings()
            }

            Button("退出") {
                coordinator.quit()
            }
        }
        .padding(12)
        .frame(width: 280)
    }
}
