import SwiftUI

struct PhotoRowView: View {
    let job: PhotoJob
    @Binding var isSelectedForWriting: Bool

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: $isSelectedForWriting)
                .labelsHidden()
                .accessibilityLabel("选择 \(job.displayName)")
                .accessibilityValue(isSelectedForWriting ? "已选择" : "未选择")
                .accessibilityHint("控制批量导出或写入原照片时是否包含这张照片")
            Image(systemName: statusIcon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(statusColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(job.displayName)
                    .lineLimit(1)
                Text(job.status.label)
                    .font(.caption)
                    .foregroundStyle(job.status == .failed ? .red : .secondary)
            }
            Spacer()
            if isSelectedForWriting {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusIcon: String {
        switch job.status {
        case .waiting: return "clock"
        case .recognizing, .writing: return "hourglass"
        case .ready: return "doc.text.magnifyingglass"
        case .completed: return "checkmark.circle.fill"
        case .exported: return "square.and.arrow.up.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch job.status {
        case .completed, .exported: return .green
        case .failed: return .red
        case .recognizing, .writing: return .blue
        default: return .secondary
        }
    }
}
