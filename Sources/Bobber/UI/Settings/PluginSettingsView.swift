import SwiftUI

struct PluginSettingsView: View {
    @ObservedObject var claudeCLIManager: ClaudeCLIManager

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Plugin").font(.title2).fontWeight(.semibold)

            GroupBox {
                HStack(spacing: 12) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 12, height: 12)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(statusTitle).fontWeight(.medium)
                        Text(statusDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(8)
            }

            GroupBox("Actions") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        switch claudeCLIManager.pluginStatus {
                        case .notInstalled, .cliNotFound, .unknown:
                            Button("Install Plugin") {
                                claudeCLIManager.installPlugin { _ in }
                            }
                            .disabled(claudeCLIManager.pluginStatus == .cliNotFound || claudeCLIManager.isRunningOperation)
                        case .installed:
                            Button("Reinstall") {
                                claudeCLIManager.reinstallPlugin { _ in }
                            }
                            .disabled(claudeCLIManager.isRunningOperation)
                            Button("Uninstall") {
                                claudeCLIManager.uninstallPlugin { _ in }
                            }
                            .disabled(claudeCLIManager.isRunningOperation)
                        case .installedDisabled:
                            Button("Enable") {
                                claudeCLIManager.enablePlugin { _ in }
                            }
                            .disabled(claudeCLIManager.isRunningOperation)
                            Button("Uninstall") {
                                claudeCLIManager.uninstallPlugin { _ in }
                            }
                            .disabled(claudeCLIManager.isRunningOperation)
                        case .updateAvailable(_, _):
                            Button("Update") {
                                claudeCLIManager.updatePlugin { _ in }
                            }
                            .disabled(claudeCLIManager.isRunningOperation)
                            Button("Uninstall") {
                                claudeCLIManager.uninstallPlugin { _ in }
                            }
                            .disabled(claudeCLIManager.isRunningOperation)
                        }

                        if claudeCLIManager.isRunningOperation {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    Button("Refresh Status") {
                        claudeCLIManager.checkPluginStatus()
                    }
                    .disabled(claudeCLIManager.isRunningOperation)
                }
                .padding(8)
            }

            if !claudeCLIManager.operationLog.isEmpty {
                GroupBox("Log") {
                    ScrollView {
                        Text(claudeCLIManager.operationLog)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 120)
                    .padding(8)
                }
            }

            Spacer()
        }
        .onAppear {
            claudeCLIManager.checkPluginStatus()
        }
    }

    private var statusColor: Color {
        switch claudeCLIManager.pluginStatus {
        case .installed: return .green
        case .updateAvailable: return .orange
        case .installedDisabled: return .yellow
        case .notInstalled, .unknown: return .red
        case .cliNotFound: return .gray
        }
    }

    private var statusTitle: String {
        switch claudeCLIManager.pluginStatus {
        case .installed: return "Installed & Active"
        case .installedDisabled: return "Installed (Disabled)"
        case .updateAvailable(let local, let remote): return "Update Available (\(local) -> \(remote))"
        case .notInstalled: return "Not Installed"
        case .cliNotFound: return "Claude CLI Not Found"
        case .unknown: return "Checking..."
        }
    }

    private var statusDescription: String {
        switch claudeCLIManager.pluginStatus {
        case .installed: return "Bobber plugin is active in Claude Code."
        case .installedDisabled: return "Plugin is installed but disabled. Enable it in Claude Code with /plugin."
        case .updateAvailable: return "A newer version is available."
        case .notInstalled: return "Plugin not installed. Click Install to set up."
        case .cliNotFound: return "Set Claude CLI path in General settings first."
        case .unknown: return "Detecting plugin status..."
        }
    }
}
