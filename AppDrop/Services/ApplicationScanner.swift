import AppKit
import Foundation

actor ApplicationScanner {
    private let fileManager = FileManager.default

    func scanInstalledApps() async -> [AppRecord] {
        var found: [AppRecord] = []
        var seenPaths = Set<String>()

        for root in scanRoots() {
            for appURL in collectAppBundles(in: root.url, maxDepth: root.depth) {
                let path = appURL.standardizedFileURL.path
                guard seenPaths.insert(path).inserted else { continue }
                guard let app = makeRecord(for: appURL) else { continue }
                guard !app.isProtected else { continue }
                found.append(app)
            }
        }

        return found.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private func scanRoots() -> [(url: URL, depth: Int)] {
        let home = fileManager.homeDirectoryForCurrentUser
        return [
            (URL(fileURLWithPath: "/Applications"), 3),
            (home.appendingPathComponent("Applications"), 3),
            (URL(fileURLWithPath: "/opt/homebrew/Caskroom"), 4),
            (URL(fileURLWithPath: "/usr/local/Caskroom"), 4),
            (home.appendingPathComponent("Library/Application Support/Setapp/Applications"), 3)
        ]
    }

    private func collectAppBundles(in root: URL, maxDepth: Int) -> [URL] {
        guard fileManager.fileExists(atPath: root.path) else { return [] }

        var result: [URL] = []
        var queue: [(url: URL, depth: Int)] = [(root, 0)]

        while let current = queue.first {
            queue.removeFirst()

            guard current.depth <= maxDepth else { continue }
            guard let children = try? fileManager.contentsOfDirectory(
                at: current.url,
                includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for child in children {
                if child.pathExtension == "app" {
                    result.append(child)
                    continue
                }

                guard current.depth < maxDepth else { continue }
                guard (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                queue.append((child, current.depth + 1))
            }
        }

        return result
    }

    private func makeRecord(for url: URL) -> AppRecord? {
        let infoURL = url.appendingPathComponent("Contents/Info.plist")
        guard
            let data = try? Data(contentsOf: infoURL),
            let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
            let info = plist as? [String: Any]
        else {
            return nil
        }

        let fileName = url.deletingPathExtension().lastPathComponent
        let bundleIdentifier = (info["CFBundleIdentifier"] as? String) ?? "unknown"
        let bundleDisplayName = info["CFBundleDisplayName"] as? String
        let bundleName = info["CFBundleName"] as? String
        let displayName = sanitizedDisplayName(bundleDisplayName ?? bundleName ?? fileName, fallback: fileName)
        let executableName = info["CFBundleExecutable"] as? String
        let version = (info["CFBundleShortVersionString"] as? String) ?? (info["CFBundleVersion"] as? String)
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        let protection = protectionStatus(for: url, bundleIdentifier: bundleIdentifier)

        return AppRecord(
            id: url.standardizedFileURL.path,
            url: url,
            displayName: displayName,
            bundleIdentifier: bundleIdentifier,
            executableName: executableName,
            version: version,
            size: allocatedSize(of: url),
            lastModified: values?.contentModificationDate,
            isProtected: protection.isProtected,
            protectionReason: protection.reason
        )
    }

    private func sanitizedDisplayName(_ value: String, fallback: String) -> String {
        let trimmed = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty || trimmed.hasPrefix("/") {
            return fallback
        }
        return trimmed.replacingOccurrences(of: ".app", with: "")
    }

    private func protectionStatus(for url: URL, bundleIdentifier: String) -> (isProtected: Bool, reason: String?) {
        let path = url.standardizedFileURL.path

        if path.hasPrefix("/System/Applications") {
            return (true, "系统应用受保护")
        }

        if bundleIdentifier.hasPrefix("com.apple.") {
            return (true, "Apple 系统组件受保护")
        }

        let critical = [
            "loginwindow", "dock", "finder", "systempreferences", "systemsettings",
            "controlcenter", "backgroundtaskmanagement", "tcc"
        ]

        let normalized = bundleIdentifier.lowercased()
        if critical.contains(where: { normalized.contains($0) }) {
            return (true, "关键系统组件受保护")
        }

        return (false, nil)
    }

    private func allocatedSize(of url: URL) -> Int64 {
        var total: Int64 = 0
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey]

        if let values = try? url.resourceValues(forKeys: keys),
           let totalSize = values.totalFileAllocatedSize,
           totalSize > 0 {
            total += Int64(totalSize)
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: nil
        ) else {
            return total
        }

        for case let item as URL in enumerator {
            guard let values = try? item.resourceValues(forKeys: keys) else { continue }
            if values.isRegularFile == true {
                total += Int64(values.fileAllocatedSize ?? values.totalFileAllocatedSize ?? 0)
            }
        }

        return total
    }
}
