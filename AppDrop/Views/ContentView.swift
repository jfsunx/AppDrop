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
            .searchable(text: $model.searchText, prompt: "搜索应用或 Bundle ID")
            .overlay {
                if model.isScanning {
                    ProgressView("正在扫描应用")
                        .padding()
                } else if model.filteredApps.isEmpty {
                    ContentUnavailableView("未找到应用", systemImage: "app.dashed")
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
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(model.isScanning)

                Button(role: .destructive) {
                    showConfirmation = true
                } label: {
                    Label("卸载", systemImage: "trash")
                }
                .disabled(model.plan == nil || model.isPlanning)
            }
        }
        .alert("移到废纸篓？", isPresented: $showConfirmation, presenting: model.plan) { plan in
            Button("移到废纸篓", role: .destructive) {
                Task { await model.uninstallSelection() }
            }
            Button("取消", role: .cancel) {}
        } message: { plan in
            let selected = plan.selectedResiduals(model.selectedResidualIDs)
            let systemCount = selected.filter { $0.scope == .systemReview }.count
            Text("将移除 \(plan.app.displayName) 以及 \(selected.count) 项已勾选残留，其中系统级项目 \(systemCount) 项。")
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

                    AppHeader(app: app)

                    if model.isPlanning {
                        ProgressView("正在分析残留文件")
                    } else if let plan = model.plan {
                        PlanSummary(plan: plan, selectedResidualIDs: model.selectedResidualIDs)
                        ResidualSection(
                            title: "用户级残留",
                            items: plan.userResiduals,
                            emptyText: "未发现用户级残留",
                            selectedIDs: $model.selectedResidualIDs
                        )
                        ResidualSection(
                            title: "系统级残留",
                            items: plan.systemReviewItems,
                            emptyText: "未发现系统级残留",
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
        } else {
            ContentUnavailableView("选择一个应用", systemImage: "square.stack.3d.up")
        }
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
                Text("建议开启完全磁盘访问")
                    .font(.headline)
                Text("部分残留目录当前不可读，开启后扫描会更完整。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                openSettings()
            } label: {
                Label("打开设置", systemImage: "gear")
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
                HStack(spacing: 12) {
                    Label(Formatters.fileSize(app.size), systemImage: "internaldrive")
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
            Stat(label: "可释放", value: Formatters.fileSize(plan.totalBytes(selectedResidualIDs: selectedResidualIDs)), symbol: "externaldrive.badge.minus")
            Stat(label: "项目", value: "\(plan.itemCount(selectedResidualIDs: selectedResidualIDs))", symbol: "checklist")
            Stat(label: "已选系统级", value: "\(selectedSystemCount)", symbol: "exclamationmark.shield")
        }
        .padding(.vertical, 2)

        if plan.containsSensitivePaths {
            Label("检测到可能包含账户、Cookie 或用户资料的路径，请在卸载前复核。", systemImage: "exclamationmark.triangle")
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
