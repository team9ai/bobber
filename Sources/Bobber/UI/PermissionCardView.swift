import SwiftUI

struct PermissionCardView: View {
    let action: PendingAction
    let onDecision: (PermissionDecision) -> Void
    @State private var isEditing: Bool = false
    @State private var editedCommand: String = ""
    @State private var customMessage: String = ""
    @State private var showCustomInput: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Allow this \(action.tool ?? "tool") command?")
                .font(.subheadline)
                .foregroundColor(.secondary)

            if let command = action.command {
                if isEditing {
                    TextEditor(text: $editedCommand)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 60, maxHeight: 100)
                        .cornerRadius(6)
                } else {
                    Text(command)
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.08))
                        .cornerRadius(6)
                }
            }

            if let desc = action.description {
                Text(desc)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            Button(isEditing ? "Done editing" : "Edit command...") {
                if !isEditing { editedCommand = action.command ?? "" }
                isEditing.toggle()
            }
            .font(.caption)
            .buttonStyle(.plain)
            .foregroundColor(.blue)

            VStack(spacing: 6) {
                ActionButton(label: "Yes", icon: "checkmark.circle.fill", color: .green) {
                    onDecision(.allow)
                }
                ActionButton(label: "Yes, for this project", icon: "folder.fill", color: .blue) {
                    onDecision(.allowForProject)
                }
                ActionButton(label: "No", icon: "xmark.circle.fill", color: .red) {
                    onDecision(.deny)
                }
                if showCustomInput {
                    HStack {
                        TextField("Tell Claude what to do instead...", text: $customMessage)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                        Button("Send") {
                            onDecision(.custom(customMessage))
                        }
                        .disabled(customMessage.isEmpty)
                    }
                } else {
                    ActionButton(label: "Tell Claude instead...", icon: "text.bubble.fill", color: .orange) {
                        showCustomInput = true
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.05))
        )
        .padding(.horizontal, 12)
    }
}

struct ActionButton: View {
    let label: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(label)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(color.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }
}
