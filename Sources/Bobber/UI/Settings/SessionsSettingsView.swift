import SwiftUI

struct SessionsSettingsView: View {
    @Binding var config: BobberConfig
    let onConfigChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Sessions").font(.title2).fontWeight(.semibold)

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Stale timeout:")
                        TextField("", value: $config.sessions.staleTimeoutMinutes, format: .number)
                            .frame(width: 60)
                            .onChange(of: config.sessions.staleTimeoutMinutes) { _ in
                                config.sessions.staleTimeoutMinutes = max(1, config.sessions.staleTimeoutMinutes)
                                onConfigChanged()
                            }
                        Text("minutes")
                            .foregroundColor(.secondary)
                    }
                    Text("Sessions with no events for this long are marked stale.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Divider()

                    HStack {
                        Text("Keep completed:")
                        TextField("", value: $config.sessions.keepCompletedCount, format: .number)
                            .frame(width: 60)
                            .onChange(of: config.sessions.keepCompletedCount) { _ in
                                config.sessions.keepCompletedCount = max(0, config.sessions.keepCompletedCount)
                                onConfigChanged()
                            }
                        Text("sessions")
                            .foregroundColor(.secondary)
                    }
                    Text("Maximum number of completed sessions to keep in history.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
            }

            Spacer()
        }
    }
}
