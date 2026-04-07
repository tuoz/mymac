import SwiftUI

struct SettingsView: View {
    let coordinator: AppCoordinator

    var body: some View {
        TabView {
            GeneralSettingsView(coordinator: coordinator)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            PermissionsSettingsView(coordinator: coordinator)
                .tabItem {
                    Label("Permissions", systemImage: "lock.shield")
                }

            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 420)
    }
}

private struct GeneralSettingsView: View {
    @Environment(AppState.self) private var appState

    let coordinator: AppCoordinator

    var body: some View {
        Form {
            Toggle("启用键盘映射", isOn: Binding(
                get: { appState.isKeyboardMappingEnabled },
                set: { newValue in
                    Task {
                        await coordinator.setKeyboardMappingEnabled(newValue)
                    }
                }
            ))

            Toggle("开机启动", isOn: Binding(
                get: { coordinator.isLaunchAtLoginToggleOn },
                set: { newValue in
                    coordinator.setLaunchAtLoginEnabled(newValue)
                }
            ))

            LabeledContent("当前状态", value: appState.runtimeStatus.displayName)
            LabeledContent("权限", value: appState.permissionSummary)
        }
        .formStyle(.grouped)
    }
}

private struct PermissionsSettingsView: View {
    @Environment(AppState.self) private var appState

    let coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("核心权限状态") {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Accessibility", value: appState.permissions.accessibility.displayName)
                    LabeledContent("Input Monitoring", value: appState.permissions.inputMonitoring.displayName)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("MyMac 现在会尝试建立真实键盘监听与事件注入链路；权限不完整时，状态会回落到明确的不可用提示。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Button("请求权限") {
                    Task {
                        await coordinator.requestPermissions()
                    }
                }

                Button("打开系统设置") {
                    coordinator.openSystemSettings(for: coordinator.preferredSettingsPermissionKind())
                }

                Button("重新检测") {
                    Task {
                        await coordinator.refreshPermissions()
                    }
                }
            }

            Spacer()
        }
    }
}

private struct AboutSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MyMac")
                .font(.largeTitle)
                .bold()
            Text("A macOS keyboard utility skeleton for Fn + HJKL remapping.")
                .foregroundStyle(.secondary)
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
