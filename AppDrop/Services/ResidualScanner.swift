import Foundation

struct ResidualScanner {
    private let fileManager = FileManager.default

    func makePlan(for app: AppRecord) async -> UninstallPlan {
        let measuredApp = app.size > 0 ? app : app.withSize(allocatedSize(of: app.url))
        let userItems = uniqueExistingItems(from: userCandidates(for: app), scope: .user)
        let systemItems = uniqueExistingItems(from: systemReviewCandidates(for: app), scope: .systemReview)
        let sensitive = userItems.contains { isSensitivePath($0.path) }
        return UninstallPlan(app: measuredApp, userResiduals: userItems, systemReviewItems: systemItems, containsSensitivePaths: sensitive)
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
                Candidate(library.appendingPathComponent("Caches/\(name)"), L10n.text("缓存", "Caches")),
                Candidate(library.appendingPathComponent("Logs/\(name)"), L10n.text("日志", "Logs")),
                Candidate(library.appendingPathComponent("Preferences/\(name)"), L10n.text("偏好设置", "Preferences")),
                Candidate(library.appendingPathComponent("Preferences/\(name).plist"), L10n.text("偏好设置", "Preferences")),
                Candidate(library.appendingPathComponent("Saved Application State/\(name).savedState"), L10n.text("窗口状态", "Saved State")),
                Candidate(library.appendingPathComponent("Services/\(name).workflow"), L10n.text("服务", "Services")),
                Candidate(library.appendingPathComponent("QuickLook/\(name).qlgenerator"), "Quick Look"),
                Candidate(library.appendingPathComponent("Internet Plug-Ins/\(name).plugin"), L10n.text("插件", "Plug-ins")),
                Candidate(library.appendingPathComponent("PreferencePanes/\(name).prefPane"), L10n.text("偏好面板", "Preference Pane")),
                Candidate(library.appendingPathComponent("Input Methods/\(name).app"), L10n.text("输入法", "Input Method")),
                Candidate(library.appendingPathComponent("Screen Savers/\(name).saver"), L10n.text("屏幕保护程序", "Screen Saver")),
                Candidate(library.appendingPathComponent("Frameworks/\(name).framework"), L10n.text("框架", "Framework")),
                Candidate(home.appendingPathComponent(".config/\(name)"), L10n.text("配置", "Config")),
                Candidate(home.appendingPathComponent(".cache/\(name)"), L10n.text("缓存", "Caches")),
                Candidate(home.appendingPathComponent(".local/share/\(name)"), L10n.text("应用数据", "Application Data")),
                Candidate(home.appendingPathComponent(".\(name)"), L10n.text("隐藏配置", "Hidden Config"))
            ])
        }

        if let bundleID {
            candidates.append(contentsOf: [
                Candidate(library.appendingPathComponent("Application Support/\(bundleID)"), "Application Support"),
                Candidate(library.appendingPathComponent("Caches/\(bundleID)"), L10n.text("缓存", "Caches")),
                Candidate(library.appendingPathComponent("Logs/\(bundleID)"), L10n.text("日志", "Logs")),
                Candidate(library.appendingPathComponent("Preferences/\(bundleID).plist"), L10n.text("偏好设置", "Preferences")),
                Candidate(library.appendingPathComponent("Preferences/\(bundleID)"), L10n.text("偏好设置", "Preferences")),
                Candidate(library.appendingPathComponent("Saved Application State/\(bundleID).savedState"), L10n.text("窗口状态", "Saved State")),
                Candidate(library.appendingPathComponent("Containers/\(bundleID)"), L10n.text("容器", "Container")),
                Candidate(library.appendingPathComponent("WebKit/\(bundleID)"), "WebKit"),
                Candidate(library.appendingPathComponent("HTTPStorages/\(bundleID)"), "HTTP Storage"),
                Candidate(library.appendingPathComponent("HTTPStorages/\(bundleID).binarycookies"), "Cookies"),
                Candidate(library.appendingPathComponent("Cookies/\(bundleID).binarycookies"), "Cookies"),
                Candidate(library.appendingPathComponent("Application Scripts/\(bundleID)"), L10n.text("脚本", "Scripts")),
                Candidate(library.appendingPathComponent("Autosave Information/\(bundleID)"), L10n.text("自动保存", "Autosave")),
                Candidate(library.appendingPathComponent("SyncedPreferences/\(bundleID).plist"), L10n.text("同步偏好", "Synced Preferences")),
                Candidate(library.appendingPathComponent("Caches/com.apple.nsurlsessiond/Downloads/\(bundleID)"), L10n.text("下载缓存", "Download Cache"))
            ])

            candidates.append(contentsOf: byHostPreferences(bundleID: bundleID, library: library))
            candidates.append(contentsOf: launchAgents(bundleID: bundleID, library: library))
            candidates.append(contentsOf: boundaryMatchedChildren(root: library.appendingPathComponent("Group Containers"), bundleID: bundleID, category: "Group Container"))
            candidates.append(contentsOf: boundaryMatchedChildren(root: library.appendingPathComponent("Containers"), bundleID: bundleID, category: L10n.text("容器扩展", "Container Extension")))
            candidates.append(contentsOf: boundaryMatchedChildren(root: library.appendingPathComponent("Application Scripts"), bundleID: bundleID, category: L10n.text("脚本扩展", "Script Extension")))
            candidates.append(contentsOf: sharedFileLists(bundleID: bundleID, library: library))
        }

        candidates.append(contentsOf: diagnosticReports(for: app, directory: library.appendingPathComponent("Logs/DiagnosticReports"), scopeTitle: L10n.text("诊断报告", "Diagnostic Report")))
        return candidates
    }

    private func systemReviewCandidates(for app: AppRecord) -> [Candidate] {
        guard isReverseDNS(app.bundleIdentifier) || app.displayName.count >= 2 else { return [] }
        let library = URL(fileURLWithPath: "/Library")
        let names = nameVariants(for: app.displayName)
        var candidates: [Candidate] = []

        for name in names where name.count >= 2 {
            candidates.append(contentsOf: [
                Candidate(library.appendingPathComponent("Application Support/\(name)"), L10n.text("系统 Application Support", "System Application Support"), riskLevel: .requiresAdmin),
                Candidate(library.appendingPathComponent("Caches/\(name)"), L10n.text("系统缓存", "System Caches"), riskLevel: .requiresAdmin),
                Candidate(library.appendingPathComponent("Logs/\(name)"), L10n.text("系统日志", "System Logs"), riskLevel: .requiresAdmin),
                Candidate(library.appendingPathComponent("Preferences/\(name).plist"), L10n.text("系统偏好", "System Preferences"), riskLevel: .requiresAdmin),
                Candidate(library.appendingPathComponent("Frameworks/\(name).framework"), L10n.text("系统框架", "System Framework"), riskLevel: .high),
                Candidate(library.appendingPathComponent("Internet Plug-Ins/\(name).plugin"), L10n.text("系统插件", "System Plug-in"), riskLevel: .high),
                Candidate(library.appendingPathComponent("Input Methods/\(name).app"), L10n.text("系统输入法", "System Input Method"), riskLevel: .high),
                Candidate(library.appendingPathComponent("QuickLook/\(name).qlgenerator"), L10n.text("系统 Quick Look", "System Quick Look"), riskLevel: .requiresAdmin),
                Candidate(library.appendingPathComponent("PreferencePanes/\(name).prefPane"), L10n.text("系统偏好面板", "System Preference Pane"), riskLevel: .high),
                Candidate(library.appendingPathComponent("Screen Savers/\(name).saver"), L10n.text("系统屏保", "System Screen Saver"), riskLevel: .requiresAdmin)
            ])
        }

        if isReverseDNS(app.bundleIdentifier) {
            let bundleID = app.bundleIdentifier
            candidates.append(contentsOf: [
                Candidate(library.appendingPathComponent("Application Support/\(bundleID)"), L10n.text("系统 Application Support", "System Application Support"), riskLevel: .requiresAdmin),
                Candidate(library.appendingPathComponent("LaunchAgents/\(bundleID).plist"), L10n.text("系统 LaunchAgent", "System LaunchAgent"), riskLevel: .requiresAdmin),
                Candidate(library.appendingPathComponent("LaunchDaemons/\(bundleID).plist"), L10n.text("系统 LaunchDaemon", "System LaunchDaemon"), riskLevel: .high),
                Candidate(library.appendingPathComponent("Preferences/\(bundleID).plist"), L10n.text("系统偏好", "System Preferences"), riskLevel: .requiresAdmin),
                Candidate(library.appendingPathComponent("Receipts/\(bundleID).bom"), L10n.text("安装收据", "Install Receipt"), riskLevel: .requiresAdmin),
                Candidate(library.appendingPathComponent("Receipts/\(bundleID).plist"), L10n.text("安装收据", "Install Receipt"), riskLevel: .requiresAdmin),
                Candidate(library.appendingPathComponent("Caches/\(bundleID)"), L10n.text("系统缓存", "System Caches"), riskLevel: .requiresAdmin),
                Candidate(library.appendingPathComponent("Logs/\(bundleID)"), L10n.text("系统日志", "System Logs"), riskLevel: .requiresAdmin)
            ])
        }

        candidates.append(contentsOf: diagnosticReports(
            for: app,
            directory: library.appendingPathComponent("Logs/DiagnosticReports"),
            scopeTitle: L10n.text("系统诊断报告", "System Diagnostic Report"),
            riskLevel: .requiresAdmin
        ))
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
                scope: scope,
                riskLevel: candidate.riskLevel
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
            .map { Candidate($0, L10n.text("ByHost 偏好", "ByHost Preferences")) }
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
                result.append(Candidate(url, L10n.text("最近项目", "Recent Items")))
            }
        }

        return result
    }

    private func diagnosticReports(
        for app: AppRecord,
        directory: URL,
        scopeTitle: String,
        riskLevel: ResidualRiskLevel = .normal
    ) -> [Candidate] {
        guard let executable = app.executableName, executable.count >= 3 else { return [] }
        guard let children = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }

        return children.filter { url in
            let name = url.lastPathComponent
            let hasPrefix = name.hasPrefix(executable + ".") || name.hasPrefix(executable + "_") || name.hasPrefix(executable + "-")
            let isDiagnostic = ["ips", "crash", "spin", "diag"].contains(url.pathExtension)
            return hasPrefix && isDiagnostic
        }
        .map { Candidate($0, scopeTitle, riskLevel: riskLevel) }
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
        let riskLevel: ResidualRiskLevel

        init(_ url: URL, _ category: String, riskLevel: ResidualRiskLevel = .normal) {
            self.url = url
            self.category = category
            self.riskLevel = riskLevel
        }
    }
}
