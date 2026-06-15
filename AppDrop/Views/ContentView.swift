import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppViewModel()
    @State private var showConfirmation = false

    var body: some View {
        NavigationSplitView {
            List(model.filteredApps, selection: $model.selectedAppID) { app in
                AppRow(app: app)
                    .tag(app.id)
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 340)
            .searchable(text: $model.searchText, prompt: L10n.text("搜索应用或 Bundle ID", "Search apps or bundle IDs"))
            .overlay {
                if model.isScanning {
                    ProgressView(L10n.text("正在扫描应用", "Scanning apps"))
                        .padding()
                } else if model.filteredApps.isEmpty {
                    ContentUnavailableView(L10n.text("未找到应用", "No Apps Found"), systemImage: "app.dashed")
                }
            }
        } detail: {
            detail
                .navigationSplitViewColumnWidth(min: 520, ideal: 680)
        }
        .frame(minWidth: 900, minHeight: 560)
        .task {
            await model.refresh()
        }
        .onChange(of: model.selectedAppID) {
            Task { await model.preparePlanForSelection() }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await model.refresh(clearSelection: true) }
                } label: {
                    Label(L10n.text("刷新", "Refresh"), systemImage: "arrow.clockwise")
                }
                .disabled(model.isScanning || model.isUninstalling)

                Button(role: .destructive) {
                    showConfirmation = true
                } label: {
                    Label(L10n.text("卸载", "Uninstall"), systemImage: "trash")
                }
                .disabled(model.plan == nil || model.isPlanning || model.isUninstalling)
            }
        }
        .alert(L10n.text("移到废纸篓？", "Move to Trash?"), isPresented: $showConfirmation, presenting: model.plan) { plan in
            Button(L10n.text("移到废纸篓", "Move to Trash"), role: .destructive) {
                Task { await model.uninstallSelection() }
            }
            Button(L10n.text("取消", "Cancel"), role: .cancel) {}
        } message: { plan in
            let selected = plan.selectedResiduals(model.selectedResidualIDs)
            let systemCount = selected.filter { $0.scope == .systemReview }.count
            Text(L10n.text(
                "将移除 \(plan.app.displayName) 以及 \(selected.count) 项已勾选残留，其中系统级项目 \(systemCount) 项。",
                "This will remove \(plan.app.displayName) and \(selected.count) selected leftover item(s), including \(systemCount) system-level item(s)."
            ))
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let app = model.selectedApp {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if model.permissionStatus.needsFullDiskAccess {
                        PermissionBanner(
                            status: model.permissionStatus,
                            openSettings: { model.openFullDiskAccessSettings() }
                        )
                    }

                    AppHeader(app: model.plan?.app ?? app)

                    if let hint = (model.plan?.app ?? app).installSource.uninstallHint {
                        SourceHint(text: hint)
                    }

                    if model.isPlanning {
                        ProgressView(L10n.text("正在分析残留文件", "Scanning leftover files"))
                    } else if model.isUninstalling {
                        ProgressView(L10n.text("正在移到废纸篓", "Moving to Trash"))
                    } else if let plan = model.plan {
                        PlanSummary(plan: plan, selectedResidualIDs: model.selectedResidualIDs)
                        ResidualSection(
                            title: L10n.text("用户级残留", "User-Level Leftovers"),
                            items: plan.userResiduals,
                            emptyText: L10n.text("未发现用户级残留", "No user-level leftovers found"),
                            selectedIDs: $model.selectedResidualIDs
                        )
                        ResidualSection(
                            title: L10n.text("系统级残留", "System-Level Leftovers"),
                            items: plan.systemReviewItems,
                            emptyText: L10n.text("未发现系统级残留", "No system-level leftovers found"),
                            selectedIDs: $model.selectedResidualIDs
                        )
                    }

                    if let message = model.message {
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if let result = model.lastResult {
            VStack {
                UninstallResultView(result: result, dismiss: { model.dismissLastResult() })
                    .frame(maxWidth: 560)
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 16) {
                ContentUnavailableView(L10n.text("选择一个应用", "Select an App"), systemImage: "square.stack.3d.up")

                if let message = model.message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(28)
        }
    }
}

private struct SourceHint: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "info.circle")
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(10)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct PermissionBanner: View {
    let status: PermissionStatus
    let openSettings: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "lock.shield")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.text("建议开启完全磁盘访问", "Full Disk Access Recommended"))
                    .font(.headline)
                Text(L10n.text("部分残留目录当前不可读，开启后扫描会更完整。", "Some leftover folders are not readable. Enabling access makes scans more complete."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                openSettings()
            } label: {
                Label(L10n.text("打开设置", "Open Settings"), systemImage: "gear")
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct AppRow: View {
    let app: AppRecord

    var body: some View {
        HStack(spacing: 12) {
            AppIcon(url: app.url, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(app.displayName)
                    .lineLimit(1)
                Text(app.bundleIdentifier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct AppHeader: View {
    let app: AppRecord

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            AppIcon(url: app.url, size: 72)
            VStack(alignment: .leading, spacing: 6) {
                Text(app.displayName)
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(app.bundleIdentifier)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let source = app.installSource.displayName {
                    Label(source, systemImage: "shippingbox")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    Label("\(L10n.text("磁盘占用", "Disk Used")) \(Formatters.fileSize(app.size))", systemImage: "internaldrive")
                        .help(L10n.text(
                            "这里显示实际磁盘占用/预计可释放空间，可能小于访达显示的文件表观大小。",
                            "This shows disk usage / estimated recoverable space, which can be smaller than Finder's apparent file size."
                        ))
                    if let version = app.version {
                        Label(version, systemImage: "number")
                    }
                    if let date = app.lastModified {
                        Label(Formatters.date.string(from: date), systemImage: "calendar")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct PlanSummary: View {
    let plan: UninstallPlan
    let selectedResidualIDs: Set<ResidualItem.ID>

    private var selectedSystemCount: Int {
        plan.selectedResiduals(selectedResidualIDs).filter { $0.scope == .systemReview }.count
    }

    var body: some View {
        HStack(spacing: 20) {
            Stat(label: L10n.text("可释放", "Recoverable"), value: Formatters.fileSize(plan.totalBytes(selectedResidualIDs: selectedResidualIDs)), symbol: "externaldrive.badge.minus")
            Stat(label: L10n.text("项目", "Items"), value: "\(plan.itemCount(selectedResidualIDs: selectedResidualIDs))", symbol: "checklist")
            Stat(label: L10n.text("已选系统级", "System Selected"), value: "\(selectedSystemCount)", symbol: "exclamationmark.shield")
        }
        .padding(.vertical, 2)

        if plan.containsSensitivePaths {
            Label(L10n.text("检测到可能包含账户、Cookie 或用户资料的路径，请在卸载前复核。", "Some paths may contain account, cookie, or user-profile data. Review them before uninstalling."), systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.orange)
        }
    }
}

private struct Stat: View {
    let label: String
    let value: String
    let symbol: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ResidualSection: View {
    let title: String
    let items: [ResidualItem]
    let emptyText: String
    @Binding var selectedIDs: Set<ResidualItem.ID>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            if items.isEmpty {
                Text(emptyText)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        ResidualRow(
                            item: item,
                            isSelected: Binding(
                                get: { selectedIDs.contains(item.id) },
                                set: { isSelected in
                                    if isSelected {
                                        selectedIDs.insert(item.id)
                                    } else {
                                        selectedIDs.remove(item.id)
                                    }
                                }
                            )
                        )
                        Divider()
                    }
                }
            }
        }
    }
}

private struct ResidualRow: View {
    let item: ResidualItem
    @Binding var isSelected: Bool

    var body: some View {
        Toggle(isOn: $isSelected) {
            HStack(spacing: 12) {
                Text(item.category)
                    .frame(width: 128, alignment: .leading)
                    .lineLimit(1)
                RiskBadge(level: item.riskLevel)
                Text(item.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(Formatters.fileSize(item.size))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.checkbox)
        .padding(.vertical, 7)
    }
}

private struct RiskBadge: View {
    let level: ResidualRiskLevel

    var body: some View {
        Text(level.displayName)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
    }

    private var foreground: Color {
        switch level {
        case .normal:
            return .secondary
        case .requiresAdmin:
            return .orange
        case .high:
            return .red
        }
    }

    private var background: Color {
        switch level {
        case .normal:
            return .secondary.opacity(0.12)
        case .requiresAdmin:
            return .orange.opacity(0.12)
        case .high:
            return .red.opacity(0.12)
        }
    }
}

private struct UninstallResultView: View {
    let result: UninstallResult
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.text("卸载结果", "Uninstall Result"))
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Label(L10n.text("确认", "OK"), systemImage: "checkmark")
                }
            }

            if !result.trashed.isEmpty {
                Label(L10n.text("已移到废纸篓：\(result.trashed.count) 项", "Moved to Trash: \(result.trashed.count) item(s)"), systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }

            if !result.failed.isEmpty {
                ResultIssueList(
                    title: L10n.text("失败：\(result.failed.count) 项", "Failed: \(result.failed.count) item(s)"),
                    symbol: "exclamationmark.triangle",
                    tint: .orange,
                    items: result.failed
                )
            }

            if !result.warnings.isEmpty {
                ResultIssueList(
                    title: L10n.text("提醒：\(result.warnings.count) 项", "Warnings: \(result.warnings.count) item(s)"),
                    symbol: "info.circle",
                    tint: .secondary,
                    items: result.warnings
                )
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ResultIssueList: View {
    let title: String
    let symbol: String
    let tint: Color
    let items: [(URL, String)]

    var body: some View {
        Label(title, systemImage: symbol)
            .foregroundStyle(tint)

        ForEach(Array(items.prefix(5)), id: \.0) { item in
            VStack(alignment: .leading, spacing: 2) {
                Text(item.0.path)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.1)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

private struct AppIcon: View {
    let url: URL
    let size: CGFloat

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
