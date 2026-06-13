import AppKit
import Foundation

struct PermissionStatus: Equatable {
    let inaccessiblePaths: [String]

    static let allowed = PermissionStatus(inaccessiblePaths: [])

    var needsFullDiskAccess: Bool {
        !inaccessiblePaths.isEmpty
    }
}

struct PermissionService {
    private let fileManager = FileManager.default

    func checkPrivacyAccess() -> PermissionStatus {
        let home = fileManager.homeDirectoryForCurrentUser
        let paths = [
            home.appendingPathComponent("Library/Application Support"),
            home.appendingPathComponent("Library/Containers"),
            home.appendingPathComponent("Library/Group Containers"),
            home.appendingPathComponent("Library/Cookies"),
            home.appendingPathComponent("Library/Saved Application State"),
            home.appendingPathComponent("Library/Preferences/ByHost")
        ]

        let blocked = paths.compactMap { url -> String? in
            guard fileManager.fileExists(atPath: url.path) else { return nil }

            do {
                _ = try fileManager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
                return nil
            } catch {
                return url.path
            }
        }

        return PermissionStatus(inaccessiblePaths: blocked)
    }

    func openFullDiskAccessSettings() {
        let urls = [
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"),
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")
        ].compactMap { $0 }

        for url in urls where NSWorkspace.shared.open(url) {
            return
        }
    }
}
