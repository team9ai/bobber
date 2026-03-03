import SwiftUI

struct CompletionCardView: View {
    let action: PendingAction
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Task completed")
                    .font(.subheadline.bold())
            }

            if let desc = action.description {
                Text(desc)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button(action: onDismiss) {
                HStack {
                    Image(systemName: "eye.fill")
                    Text("Mark as read")
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.1))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.05))
        )
        .padding(.horizontal, 12)
    }
}
