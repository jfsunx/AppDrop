import Foundation

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

    var path: String {
        url.path
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
