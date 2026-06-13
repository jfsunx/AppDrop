import Foundation

struct ResidualScanner {
    private let fileManager = FileManager.default

    func makePlan(for app: AppRecord) async -> UninstallPlan {
        let userItems = uniqueExistingItems(from: userCandidates(for: app), scope: .user)
        let systemItems = uniqueExistingItems(from: systemReviewCandidates(for: app), scope: .systemReview)
        let sensitive = userItems.contains { isSensitivePath($0.path) }
        return UninstallPlan(app: app, userResiduals: userItems, systemReviewItems: systemItems, containsSensitivePaths: sensitive)
    }

    private func userCandidates(for app: AppRecord) -> [Candidate] {
        let home = fileManager.homeDirectoryForCurrentUser
        let library = home.appendingPathComponent("Library")
        let names = nameVariants(for: app.displayName)
        let bundleID = isReverseDNS(app.bundleIdentifier) ? app.bundleIdentifier : nil
        var candidates: [Candidate] = []

        for name in names where name.count >= 2 {
            candidates.append(contentsOf: [
                Candidate(library.appendingPathComponent("Application Support/\(name)"), "Application Support"),
                Candidate(library.appendingPathComponent("Caches/\(name)"), "缓存"),
                Candidate(library.appendingPathComponent("Logs/\(name)"), "日志"),
                Candidate(library.appendingPathComponent("Preferences/\(name)"), "偏好设置"),
                Candidate(library.appendingPathComponent("Preferences/\(name).plist"), "偏好设置"),
                Candidate(library.appendingPathComponent("Saved Application State/\(name).savedState"), "窗口状态"),
                Candidate(library.appendingPathComponent("Services/\(name).workflow"), "服务"),
                Candidate(library.appendingPathComponent("QuickLook/\(name).qlgenerator"), "Quick Look"),
                Candidate(library.appendingPathComponent("Internet Plug-Ins/\(name).plugin"), "插件"),
                Candidate(library.appendingPathComponent("PreferencePanes/\(name).prefPane"), "偏好面板"),
                Candidate(library.appendingPathComponent("Input Methods/\(name).app"), "输入法"),
                Candidate(library.appendingPathComponent("Screen Savers/\(name).saver"), "屏幕保护程序"),
                Candidate(library.appendingPathComponent("Frameworks/\(name).framework"), "框架"),
                Candidate(home.appendingPathComponent(".config/\(name)"), "配置"),
                Candidate(home.appendingPathComponent(".cache/\(name)"), "缓存"),
                Candidate(home.appendingPathComponent(".local/share/\(name)"), "应用数据"),
                Candidate(home.appendingPathComponent(".\(name)"), "隐藏配置")
            ])
        }

        if let bundleID {
            candidates.append(contentsOf: [
                Candidate(library.appendingPathComponent("Application Support/\(bundleID)"), "Application Support"),
                Candidate(library.appendingPathComponent("Caches/\(bundleID)"), "缓存"),
                Candidate(library.appendingPathComponent("Logs/\(bundleID)"), "日志"),
                Candidate(library.appendingPathComponent("Preferences/\(bundleID).plist"), "偏好设置"),
                Candidate(library.appendingPathComponent("Preferences/\(bundleID)"), "偏好设置"),
                Candidate(library.appendingPathComponent("Saved Application State/\(bundleID).savedState"), "窗口状态"),
                Candidate(library.appendingPathComponent("Containers/\(bundleID)"), "容器"),
                Candidate(library.appendingPathComponent("WebKit/\(bundleID)"), "WebKit"),
                Candidate(library.appendingPathComponent("HTTPStorages/\(bundleID)"), "HTTP Storage"),
                Candidate(library.appendingPathComponent("HTTPStorages/\(bundleID).binarycookies"), "Cookies"),
                Candidate(library.appendingPathComponent("Cookies/\(bundleID).binarycookies"), "Cookies"),
                Candidate(library.appendingPathComponent("Application Scripts/\(bundleID)"), "脚本"),
                Candidate(library.appendingPathComponent("Autosave Information/\(bundleID)"), "自动保存"),
                Candidate(library.appendingPathComponent("SyncedPreferences/\(bundleID).plist"), "同步偏好"),
                Candidate(library.appendingPathComponent("Caches/com.apple.nsurlsessiond/Downloads/\(bundleID)"), "下载缓存")
            ])

            candidates.append(contentsOf: byHostPreferences(bundleID: bundleID, library: library))
            candidates.append(contentsOf: launchAgents(bundleID: bundleID, library: library))
            candidates.append(contentsOf: boundaryMatchedChildren(root: library.appendingPathComponent("Group Containers"), bundleID: bundleID, category: "Group Container"))
            candidates.append(contentsOf: boundaryMatchedChildren(root: library.appendingPathComponent("Containers"), bundleID: bundleID, category: "容器扩展"))
            candidates.append(contentsOf: boundaryMatchedChildren(root: library.appendingPathComponent("Application Scripts"), bundleID: bundleID, category: "脚本扩展"))
            candidates.append(contentsOf: sharedFileLists(bundleID: bundleID, library: library))
        }

        candidates.append(contentsOf: diagnosticReports(for: app, directory: library.appendingPathComponent("Logs/DiagnosticReports"), scopeTitle: "诊断报告"))
        return candidates
    }

    private func systemReviewCandidates(for app: AppRecord) -> [Candidate] {
        guard isReverseDNS(app.bundleIdentifier) || app.displayName.count >= 2 else { return [] }
        let library = URL(fileURLWithPath: "/Library")
        let names = nameVariants(for: app.displayName)
        var candidates: [Candidate] = []

        for name in names where name.count >= 2 {
            candidates.append(contentsOf: [
                Candidate(library.appendingPathComponent("Application Support/\(name)"), "系统 Application Support"),
                Candidate(library.appendingPathComponent("Caches/\(name)"), "系统缓存"),
                Candidate(library.appendingPathComponent("Logs/\(name)"), "系统日志"),
                Candidate(library.appendingPathComponent("Preferences/\(name).plist"), "系统偏好"),
                Candidate(library.appendingPathComponent("Frameworks/\(name).framework"), "系统框架"),
                Candidate(library.appendingPathComponent("Internet Plug-Ins/\(name).plugin"), "系统插件"),
                Candidate(library.appendingPathComponent("Input Methods/\(name).app"), "系统输入法"),
                Candidate(library.appendingPathComponent("QuickLook/\(name).qlgenerator"), "系统 Quick Look"),
                Candidate(library.appendingPathComponent("PreferencePanes/\(name).prefPane"), "系统偏好面板"),
                Candidate(library.appendingPathComponent("Screen Savers/\(name).saver"), "系统屏保")
            ])
        }

        if isReverseDNS(app.bundleIdentifier) {
            let bundleID = app.bundleIdentifier
            candidates.append(contentsOf: [
                Candidate(library.appendingPathComponent("Application Support/\(bundleID)"), "系统 Application Support"),
                Candidate(library.appendingPathComponent("LaunchAgents/\(bundleID).plist"), "系统 LaunchAgent"),
                Candidate(library.appendingPathComponent("LaunchDaemons/\(bundleID).plist"), "系统 LaunchDaemon"),
                Candidate(library.appendingPathComponent("Preferences/\(bundleID).plist"), "系统偏好"),
                Candidate(library.appendingPathComponent("Receipts/\(bundleID).bom"), "安装收据"),
                Candidate(library.appendingPathComponent("Receipts/\(bundleID).plist"), "安装收据"),
                Candidate(library.appendingPathComponent("Caches/\(bundleID)"), "系统缓存"),
                Candidate(library.appendingPathComponent("Logs/\(bundleID)"), "系统日志")
            ])
        }

        candidates.append(contentsOf: diagnosticReports(for: app, directory: library.appendingPathComponent("Logs/DiagnosticReports"), scopeTitle: "系统诊断报告"))
        return candidates
    }

    private func uniqueExistingItems(from candidates: [Candidate], scope: ResidualItem.Scope) -> [ResidualItem] {
        var seen = Set<String>()
        var items: [ResidualItem] = []

        for candidate in candidates {
            let url = candidate.url.standardizedFileURL
            let path = url.path
            guard seen.insert(path).inserted else { continue }
            guard fileManager.fileExists(atPath: path) else { continue }

            if scope == .user {
                guard isSafeUserCandidate(url) else { continue }
                guard !belongsToIndependentCLI(url) else { continue }
            }

            items.append(ResidualItem(
                id: path,
                url: url,
                title: url.lastPathComponent,
                category: candidate.category,
                size: allocatedSize(of: url),
                scope: scope
            ))
        }

        return items.sorted {
            $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending
        }
    }

    private func byHostPreferences(bundleID: String, library: URL) -> [Candidate] {
        let root = library.appendingPathComponent("Preferences/ByHost")
        guard let children = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        return children
            .filter { $0.lastPathComponent.hasPrefix(bundleID + ".") && $0.pathExtension == "plist" }
            .map { Candidate($0, "ByHost 偏好") }
    }

    private func launchAgents(bundleID: String, library: URL) -> [Candidate] {
        let root = library.appendingPathComponent("LaunchAgents")
        guard let children = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        return children
            .filter {
                let name = $0.deletingPathExtension().lastPathComponent
                return $0.pathExtension == "plist" && (name == bundleID || name.hasPrefix(bundleID + "."))
            }
            .map { Candidate($0, "LaunchAgent") }
    }

    private func boundaryMatchedChildren(root: URL, bundleID: String, category: String) -> [Candidate] {
        guard let children = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        return children
            .filter { nameHasBundleBoundary($0.lastPathComponent, bundleID: bundleID) }
            .map { Candidate($0, category) }
    }

    private func sharedFileLists(bundleID: String, library: URL) -> [Candidate] {
        let root = library.appendingPathComponent("Application Support/com.apple.sharedfilelist")
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        var result: [Candidate] = []

        for case let url as URL in enumerator {
            if url.lastPathComponent == "\(bundleID).sfl4" {
                result.append(Candidate(url, "最近项目"))
            }
        }

        return result
    }

    private func diagnosticReports(for app: AppRecord, directory: URL, scopeTitle: String) -> [Candidate] {
        guard let executable = app.executableName, executable.count >= 3 else { return [] }
        guard let children = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }

        return children.filter { url in
            let name = url.lastPathComponent
            let hasPrefix = name.hasPrefix(executable + ".") || name.hasPrefix(executable + "_") || name.hasPrefix(executable + "-")
            let isDiagnostic = ["ips", "crash", "spin", "diag"].contains(url.pathExtension)
            return hasPrefix && isDiagnostic
        }
        .map { Candidate($0, scopeTitle) }
    }

    private func nameVariants(for appName: String) -> [String] {
        let trimmed = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var names: [String] = [
            trimmed,
            trimmed.replacingOccurrences(of: " ", with: ""),
            trimmed.replacingOccurrences(of: " ", with: "_"),
            trimmed.replacingOccurrences(of: " ", with: "-"),
            trimmed.lowercased(),
            trimmed.replacingOccurrences(of: " ", with: "").lowercased(),
            trimmed.replacingOccurrences(of: " ", with: "_").lowercased(),
            trimmed.replacingOccurrences(of: " ", with: "-").lowercased()
        ]

        let suffixes = [" Nightly", " Beta", " Alpha", " Dev", " Canary", " Preview", " Insider", " Developer Edition", " Technology Preview"]
        for suffix in suffixes where trimmed.hasSuffix(suffix) {
            let base = String(trimmed.dropLast(suffix.count))
            if base.count > 2 {
                names.append(base)
                names.append(base.lowercased())
            }
        }

        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }

    private func isReverseDNS(_ value: String) -> Bool {
        let pattern = #"^[A-Za-z0-9][A-Za-z0-9-]*(\.[A-Za-z0-9][A-Za-z0-9-]*)+$"#
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    private func nameHasBundleBoundary(_ name: String, bundleID: String) -> Bool {
        guard name.contains(bundleID) else { return false }
        if name == bundleID { return true }
        return name.hasPrefix(bundleID + ".") || name.hasPrefix(bundleID + "-") || name.hasSuffix("." + bundleID)
    }

    private func isSafeUserCandidate(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let home = fileManager.homeDirectoryForCurrentUser.standardizedFileURL.path
        let allowedPrefixes = [
            "\(home)/Library/",
            "\(home)/.config/",
            "\(home)/.cache/",
            "\(home)/.local/share/",
            "\(home)/."
        ]

        guard allowedPrefixes.contains(where: { path.hasPrefix($0) }) else { return false }

        let forbiddenExact = [
            "\(home)", "\(home)/Library", "\(home)/Library/Application Support",
            "\(home)/Library/Caches", "\(home)/Library/Logs", "\(home)/Library/Preferences",
            "\(home)/Library/Containers", "\(home)/Library/Group Containers",
            "\(home)/.config", "\(home)/.cache", "\(home)/.local/share"
        ]

        guard !forbiddenExact.contains(path) else { return false }

        let protectedFragments = [
            "com.apple.Settings", "com.apple.SystemSettings", "com.apple.controlcenter",
            "com.apple.finder", "com.apple.dock", "Keychains", "Mobile Documents",
            "Library/Mail", "Library/Accounts", "Library/Calendars", "Library/Contacts"
        ]

        return !protectedFragments.contains(where: { path.contains($0) })
    }

    private func belongsToIndependentCLI(_ url: URL) -> Bool {
        let home = fileManager.homeDirectoryForCurrentUser.standardizedFileURL.path
        let parent = url.deletingLastPathComponent().standardizedFileURL.path
        let base = url.lastPathComponent.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        let cliNames = ["claude", "opencode", "codex", "gemini"]
        let protectedParents = [home, "\(home)/.config", "\(home)/.local/share", "\(home)/.cache"]
        return cliNames.contains(base) && protectedParents.contains(parent)
    }

    private func isSensitivePath(_ path: String) -> Bool {
        let fragments = [
            "/.ssh/", "/.gnupg/", "/Documents/", "/Desktop/", "/Downloads/",
            "/Pictures/", "/Movies/", "/Music/", "/Cookies/", "/Accounts/",
            "/.aws/", "/.kube/", "/credentials/", "/secrets/", "/User Data/"
        ]
        return fragments.contains(where: { path.localizedCaseInsensitiveContains($0) })
    }

    private func allocatedSize(of url: URL) -> Int64 {
        var total: Int64 = 0
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey]

        if let values = try? url.resourceValues(forKeys: keys),
           let size = values.fileAllocatedSize ?? values.totalFileAllocatedSize {
            total += Int64(size)
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles],
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

    private struct Candidate {
        let url: URL
        let category: String

        init(_ url: URL, _ category: String) {
            self.url = url
            self.category = category
        }
    }
}
