import Foundation

enum Formatters {
    static let bytes: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    static let date: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static func fileSize(_ bytesValue: Int64) -> String {
        guard bytesValue > 0 else { return L10n.text("未知", "Unknown") }
        return bytes.string(fromByteCount: bytesValue)
    }
}
