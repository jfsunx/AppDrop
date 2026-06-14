import Foundation

enum AppInstallSource: Hashable {
    case regular
    case apple
    case homebrewCask(String?)
    case setapp

    var displayName: String? {
        switch self {
        case .regular:
            return nil
        case .apple:
            return "Apple"
        case .homebrewCask(let caskName):
            if let caskName, !caskName.isEmpty {
                return "Homebrew Cask: \(caskName)"
            }
            return "Homebrew Cask"
        case .setapp:
            return "Setapp"
        }
    }

    var uninstallHint: String? {
        switch self {
        case .regular, .apple:
            return nil
        case .homebrewCask(let caskName):
            if let caskName, !caskName.isEmpty {
                return L10n.text(
                    "此应用看起来来自 Homebrew Cask。若想同步清理 Homebrew 元数据，可考虑在终端运行 brew uninstall --cask \(caskName)。",
                    "This app appears to come from Homebrew Cask. To also update Homebrew metadata, consider running brew uninstall --cask \(caskName) in Terminal."
                )
            }
            return L10n.text(
                "此应用看起来来自 Homebrew Cask。若想同步清理 Homebrew 元数据，可考虑使用 brew uninstall --cask。",
                "This app appears to come from Homebrew Cask. To also update Homebrew metadata, consider using brew uninstall --cask."
            )
        case .setapp:
            return L10n.text(
                "此应用看起来来自 Setapp。若仍在订阅或管理中，也可以通过 Setapp 处理卸载。",
                "This app appears to come from Setapp. If it is still managed by Setapp, you can also uninstall it there."
            )
        }
    }
}

struct AppRecord: Identifiable, Hashable {
    let id: String
    let url: URL
    let displayName: String
    let bundleIdentifier: String
    let executableName: String?
    let version: String?
    let size: Int64
    let lastModified: Date?
    let isProtected: Bool
    let protectionReason: String?
    let installSource: AppInstallSource

    var path: String {
        url.path
    }

    func withSize(_ newSize: Int64) -> AppRecord {
        AppRecord(
            id: id,
            url: url,
            displayName: displayName,
            bundleIdentifier: bundleIdentifier,
            executableName: executableName,
            version: version,
            size: newSize,
            lastModified: lastModified,
            isProtected: isProtected,
            protectionReason: protectionReason,
            installSource: installSource
        )
    }
}

enum ResidualRiskLevel: String, Hashable {
    case normal
    case requiresAdmin
    case high

    var displayName: String {
        switch self {
        case .normal:
            return L10n.text("普通", "Normal")
        case .requiresAdmin:
            return L10n.text("需权限", "Needs Access")
        case .high:
            return L10n.text("高风险", "High Risk")
        }
    }
}

struct ResidualItem: Identifiable, Hashable {
    enum Scope: String {
        case user
        case systemReview
    }

    let id: String
    let url: URL
    let title: String
    let category: String
    let size: Int64
    let scope: Scope
    let riskLevel: ResidualRiskLevel

    var path: String {
        url.path
    }
}

struct UninstallPlan: Hashable {
    let app: AppRecord
    let userResiduals: [ResidualItem]
    let systemReviewItems: [ResidualItem]
    let containsSensitivePaths: Bool

    var removableItems: [ResidualItem] {
        userResiduals + systemReviewItems
    }

    func totalBytes(selectedResidualIDs: Set<ResidualItem.ID>) -> Int64 {
        app.size + removableItems
            .filter { selectedResidualIDs.contains($0.id) }
            .reduce(Int64(0)) { $0 + $1.size }
    }

    func itemCount(selectedResidualIDs: Set<ResidualItem.ID>) -> Int {
        1 + removableItems.filter { selectedResidualIDs.contains($0.id) }.count
    }

    func selectedResiduals(_ selectedResidualIDs: Set<ResidualItem.ID>) -> [ResidualItem] {
        removableItems.filter { selectedResidualIDs.contains($0.id) }
    }
}

struct UninstallResult {
    let trashed: [URL]
    let failed: [(URL, String)]
}
