import SwiftUI

struct DecisionCardView: View {
    let action: PendingAction
    let onChoice: (String) -> Void
    @State private var customText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let question = action.question {
                Text(question)
                    .font(.subheadline)
            }

            if let options = action.options {
                ForEach(options) { option in
                    Button(action: { onChoice(option.key) }) {
                        HStack {
                            Text(option.label)
                            Spacer()
                            if let desc = option.description {
                                Text(desc)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.blue.opacity(0.1))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                TextField("Other...", text: $customText)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                Button("Send") {
                    onChoice(customText)
                }
                .disabled(customText.isEmpty)
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
