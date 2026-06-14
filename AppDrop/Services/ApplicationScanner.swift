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
        guard let info = appInfo(for: url) else { return nil }

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
            size: 0,
            lastModified: values?.contentModificationDate,
            isProtected: protection.isProtected,
            protectionReason: protection.reason,
            installSource: installSource(for: url, bundleIdentifier: bundleIdentifier)
        )
    }

    private func appInfo(for url: URL) -> [String: Any]? {
        let directCandidates = [
            url.appendingPathComponent("Contents/Info.plist"),
            url.appendingPathComponent("Info.plist")
        ]

        for candidate in directCandidates {
            if let info = loadInfoPlist(at: candidate) {
                return info
            }
        }

        let wrappedBundleURL = url.appendingPathComponent("WrappedBundle")
        if let destination = try? fileManager.destinationOfSymbolicLink(atPath: wrappedBundleURL.path) {
            let targetURL: URL
            if destination.hasPrefix("/") {
                targetURL = URL(fileURLWithPath: destination)
            } else {
                targetURL = url.appendingPathComponent(destination)
            }

            if let info = appInfoInBundle(at: targetURL.standardizedFileURL) {
                return info
            }
        }

        let wrapperURL = url.appendingPathComponent("Wrapper")
        guard let children = try? fileManager.contentsOfDirectory(
            at: wrapperURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for child in children where child.pathExtension == "app" {
            if let info = appInfoInBundle(at: child) {
                return info
            }
        }

        return nil
    }

    private func appInfoInBundle(at url: URL) -> [String: Any]? {
        let candidates = [
            url.appendingPathComponent("Contents/Info.plist"),
            url.appendingPathComponent("Info.plist")
        ]

        for candidate in candidates {
            if let info = loadInfoPlist(at: candidate) {
                return info
            }
        }

        return nil
    }

    private func loadInfoPlist(at url: URL) -> [String: Any]? {
        guard
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
            let info = plist as? [String: Any]
        else {
            return nil
        }

        return info
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
            return (true, L10n.text("系统应用受保护", "System app is protected"))
        }

        let critical = [
            "com.apple.safari", "loginwindow", "dock", "finder", "systempreferences",
            "systemsettings", "controlcenter", "backgroundtaskmanagement", "tcc"
        ]

        let normalized = bundleIdentifier.lowercased()
        if critical.contains(where: { normalized.contains($0) }) {
            return (true, L10n.text("关键系统组件受保护", "Critical system component is protected"))
        }

        return (false, nil)
    }

    private func installSource(for url: URL, bundleIdentifier: String) -> AppInstallSource {
        let path = url.standardizedFileURL.path
        let resolvedPath = url.resolvingSymlinksInPath().standardizedFileURL.path
        let home = fileManager.homeDirectoryForCurrentUser.standardizedFileURL.path

        if path.hasPrefix("\(home)/Library/Application Support/Setapp/Applications") ||
            resolvedPath.hasPrefix("\(home)/Library/Application Support/Setapp/Applications") {
            return .setapp
        }

        if let caskName = caskName(from: resolvedPath) ?? caskName(from: path) {
            return .homebrewCask(caskName)
        }

        if bundleIdentifier.hasPrefix("com.apple.") {
            return .apple
        }

        return .regular
    }

    private func caskName(from path: String) -> String? {
        guard let range = path.range(of: "/Caskroom/") else { return nil }
        let rest = path[range.upperBound...]
        guard let firstComponent = rest.split(separator: "/").first else { return nil }
        return String(firstComponent)
    }
}
