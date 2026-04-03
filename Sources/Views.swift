import SwiftUI

// MARK: - Content View

struct ContentView: View {
    @EnvironmentObject var scanner: DiskScanner
    @State private var selected: ScanCategory? = .overview

    var body: some View {
        NavigationSplitView {
            List(selection: $selected) {
                ForEach(ScanCategory.allCases) { cat in
                    HStack {
                        Label(cat.rawValue, systemImage: cat.icon)
                        Spacer()
                        if let size = sizeFor(cat), size > 0 {
                            Text(DiskScanner.fmt(size))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(cat)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            Group {
                switch selected {
                case .overview: OverviewView(selected: $selected)
                case .nodeModules: NodeModulesView()
                case .buildArtifacts: BuildArtifactsView()
                case .caches: CachesView()
                case .appData: AppDataView()
                case .applications: AppsView()
                case nil: Text("Select a category").foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { scanner.scanAll() }
    }

    func sizeFor(_ cat: ScanCategory) -> Int64? {
        switch cat {
        case .nodeModules: return scanner.totalNodeModulesSize
        case .buildArtifacts: return scanner.totalBuildArtifactsSize
        case .caches: return scanner.totalCachesSize
        case .appData: return scanner.totalAppDataSize
        default: return nil
        }
    }
}

// MARK: - Overview

struct OverviewView: View {
    @EnvironmentObject var scanner: DiskScanner
    @Binding var selected: ScanCategory?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                DiskUsageBar(used: scanner.diskUsed, total: scanner.diskTotal, free: scanner.diskFree)

                if scanner.isScanning {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(scanner.scanProgress).foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Reclaimable Space").font(.headline)

                    CategoryRow(icon: "shippingbox", name: "node_modules",
                                size: scanner.totalNodeModulesSize,
                                detail: "\(scanner.nodeModules.count) directories") {
                        selected = .nodeModules
                    }
                    CategoryRow(icon: "hammer", name: "Build Artifacts",
                                size: scanner.totalBuildArtifactsSize,
                                detail: "\(scanner.buildArtifacts.count) directories") {
                        selected = .buildArtifacts
                    }
                    CategoryRow(icon: "archivebox", name: "Caches",
                                size: scanner.totalCachesSize,
                                detail: "\(scanner.caches.count) directories") {
                        selected = .caches
                    }
                    CategoryRow(icon: "app.badge.checkmark", name: "App & Dev Data",
                                size: scanner.totalAppDataSize,
                                detail: "\(scanner.appData.count) sources") {
                        selected = .appData
                    }
                }

                HStack {
                    Text("Total Reclaimable").font(.title3.bold())
                    Spacer()
                    Text(DiskScanner.fmt(scanner.totalReclaimable))
                        .font(.title3.bold())
                        .foregroundStyle(.green)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.green.opacity(0.08)))

                HStack(spacing: 16) {
                    Button {
                        scanner.scanAll()
                    } label: {
                        Label(scanner.isScanning ? "Scanning..." : "Scan Again",
                              systemImage: "arrow.clockwise")
                    }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(scanner.isScanning)
                    .buttonStyle(.borderedProminent)

                    if let last = scanner.lastScan {
                        Text("Last scan: \(last.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(24)
        }
    }
}

struct DiskUsageBar: View {
    let used: Int64
    let total: Int64
    let free: Int64

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1.0, Double(used) / Double(total))
    }
    var color: Color {
        fraction > 0.9 ? .red : fraction > 0.75 ? .orange : .blue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Disk Usage").font(.headline)
                Spacer()
                Text("\(DiskScanner.fmt(used)) of \(DiskScanner.fmt(total)) used")
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.2))
                    RoundedRectangle(cornerRadius: 6).fill(color)
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 24)
            HStack {
                Text("\(DiskScanner.fmt(free)) free")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(fraction * 100))% used")
                    .font(.caption)
                    .foregroundStyle(fraction > 0.9 ? .red : .secondary)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2)))
    }
}

struct CategoryRow: View {
    let icon: String
    let name: String
    let size: Int64
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(.accentColor)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).fontWeight(.medium)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(DiskScanner.fmt(size))
                    .font(.title3)
                    .foregroundStyle(size > 5_368_709_120 ? .red : size > 1_073_741_824 ? .orange : .primary)
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.2)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Node Modules

struct NodeModulesView: View {
    @EnvironmentObject var scanner: DiskScanner
    @State private var selected = Set<UUID>()
    @State private var showConfirm = false

    var selectedSize: Int64 {
        scanner.nodeModules.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("node_modules").font(.title2.bold())
                    Text("\(scanner.nodeModules.count) directories \u{00B7} \(DiskScanner.fmt(scanner.totalNodeModulesSize)) total")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Select Inactive (60+ days)") { selectInactive() }
                    .buttonStyle(.bordered)
                Button("Select All") { selected = Set(scanner.nodeModules.map(\.id)) }
                    .buttonStyle(.bordered)
                Button("Delete Selected (\(DiskScanner.fmt(selectedSize)))") { showConfirm = true }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(selected.isEmpty)
            }
            .padding()

            Divider()

            HStack {
                Text("").frame(width: 24)
                Text("Repository").fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Size").fontWeight(.semibold).frame(width: 80, alignment: .trailing)
                Text("Last Commit").fontWeight(.semibold).frame(width: 110, alignment: .trailing)
            }
            .padding(.horizontal).padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            List {
                ForEach(scanner.nodeModules) { item in
                    HStack {
                        Toggle("", isOn: Binding(
                            get: { selected.contains(item.id) },
                            set: { val in
                                if val { selected.insert(item.id) } else { selected.remove(item.id) }
                            }
                        ))
                        .toggleStyle(.checkbox)
                        .frame(width: 24)

                        Text(item.repoName)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)

                        Text(DiskScanner.fmt(item.size))
                            .monospacedDigit()
                            .frame(width: 80, alignment: .trailing)
                            .foregroundStyle(.secondary)

                        Text(item.lastCommitDate)
                            .frame(width: 110, alignment: .trailing)
                            .foregroundStyle(isOld(item.lastCommitDate) ? .red : .secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.plain)
        }
        .alert("Delete node_modules?", isPresented: $showConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete \(selected.count) folders", role: .destructive) {
                scanner.deleteNodeModules(ids: selected)
                selected.removeAll()
            }
        } message: {
            Text("This will delete \(selected.count) node_modules folder(s) totaling \(DiskScanner.fmt(selectedSize)).\n\nRun npm/pnpm install to reinstall when needed.")
        }
    }

    private func selectInactive() {
        for item in scanner.nodeModules {
            if isOld(item.lastCommitDate) { selected.insert(item.id) }
        }
    }

    private func isOld(_ dateStr: String) -> Bool {
        guard dateStr != "Unknown" else { return true }
        let cutoff = Calendar.current.date(byAdding: .day, value: -60, to: Date())!
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.date(from: dateStr).map { $0 < cutoff } ?? true
    }
}

// MARK: - Build Artifacts

struct BuildArtifactsView: View {
    @EnvironmentObject var scanner: DiskScanner
    @State private var selected = Set<UUID>()
    @State private var showConfirm = false

    var selectedSize: Int64 {
        scanner.buildArtifacts.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Build Artifacts").font(.title2.bold())
                    Text("\(scanner.buildArtifacts.count) directories \u{00B7} \(DiskScanner.fmt(scanner.totalBuildArtifactsSize)) total")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Select All") { selected = Set(scanner.buildArtifacts.map(\.id)) }
                    .buttonStyle(.bordered)
                Button("Delete Selected (\(DiskScanner.fmt(selectedSize)))") { showConfirm = true }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(selected.isEmpty)
            }
            .padding()

            Divider()

            HStack {
                Text("").frame(width: 24)
                Text("Project").fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Type").fontWeight(.semibold).frame(width: 70, alignment: .trailing)
                Text("Size").fontWeight(.semibold).frame(width: 80, alignment: .trailing)
                Text("Last Commit").fontWeight(.semibold).frame(width: 110, alignment: .trailing)
            }
            .padding(.horizontal).padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            List {
                ForEach(scanner.buildArtifacts) { item in
                    HStack {
                        Toggle("", isOn: Binding(
                            get: { selected.contains(item.id) },
                            set: { val in
                                if val { selected.insert(item.id) } else { selected.remove(item.id) }
                            }
                        ))
                        .toggleStyle(.checkbox)
                        .frame(width: 24)

                        Text(item.repoName)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)

                        Text(item.artifactType)
                            .font(.caption)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.gray.opacity(0.2)))
                            .frame(width: 70, alignment: .trailing)

                        Text(DiskScanner.fmt(item.size))
                            .monospacedDigit()
                            .frame(width: 80, alignment: .trailing)
                            .foregroundStyle(.secondary)

                        Text(item.lastCommitDate)
                            .frame(width: 110, alignment: .trailing)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.plain)
        }
        .alert("Delete build artifacts?", isPresented: $showConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete \(selected.count) folders", role: .destructive) {
                scanner.deleteBuildArtifacts(ids: selected)
                selected.removeAll()
            }
        } message: {
            Text("This will delete \(selected.count) build artifact folder(s) totaling \(DiskScanner.fmt(selectedSize)).\n\nThey rebuild automatically on next dev/build.")
        }
    }
}

// MARK: - Caches

struct CachesView: View {
    @EnvironmentObject var scanner: DiskScanner
    @State private var showClearAll = false
    @State private var itemToDelete: CacheItem?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Caches").font(.title2.bold())
                    Text("\(scanner.caches.count) directories \u{00B7} \(DiskScanner.fmt(scanner.totalCachesSize)) total")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Clear All Caches") { showClearAll = true }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(scanner.caches.isEmpty)
            }
            .padding()

            Divider()

            List(scanner.caches) { item in
                HStack {
                    Text(item.name).lineLimit(1)
                    Spacer()
                    Text(DiskScanner.fmt(item.size))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Button("Delete") { itemToDelete = item }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .padding(.vertical, 4)
            }
            .listStyle(.plain)
        }
        .alert("Clear all caches?", isPresented: $showClearAll) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) { scanner.clearAllCaches() }
        } message: {
            Text("Delete all app caches (\(DiskScanner.fmt(scanner.totalCachesSize)))?\n\nApps rebuild caches as needed. Some system caches are protected and won't be removed.")
        }
        .alert("Delete cache?", isPresented: Binding(
            get: { itemToDelete != nil },
            set: { if !$0 { itemToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { itemToDelete = nil }
            Button("Delete", role: .destructive) {
                if let item = itemToDelete { scanner.deleteCache(item) }
                itemToDelete = nil
            }
        } message: {
            if let item = itemToDelete {
                Text("Delete \(item.name) (\(DiskScanner.fmt(item.size)))?")
            }
        }
    }
}

// MARK: - App & Dev Data

struct AppDataCard: View {
    let item: AppDataItem
    let onClean: () -> Void
    let onTap: () -> Void

    private var sizeColor: Color {
        if item.size > 1_073_741_824 { return .red }
        if item.size > 104_857_600 { return .orange }
        return .secondary
    }

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: item.icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name).fontWeight(.semibold)
                Text(item.desc).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            Text(DiskScanner.fmt(item.size))
                .font(.title3)
                .monospacedDigit()
                .foregroundColor(sizeColor)

            Button("Clean All") { onClean() }
                .buttonStyle(.bordered)
                .disabled(item.size == 0)

            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(Color.gray.opacity(0.2)))
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

struct AppDataView: View {
    @EnvironmentObject var scanner: DiskScanner
    @State private var itemToClean: AppDataItem?
    @State private var drillDownItem: AppDataItem?

    private var isShowingAlert: Binding<Bool> {
        Binding(
            get: { itemToClean != nil },
            set: { if !$0 { itemToClean = nil } }
        )
    }

    var body: some View {
        Group {
            if let item = drillDownItem {
                AppDataDetailView(item: item, onBack: { drillDownItem = nil })
            } else {
                mainList
            }
        }
    }

    private var mainList: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("App & Dev Data").font(.title2.bold())
                    Text("\(DiskScanner.fmt(scanner.totalAppDataSize)) total across \(scanner.appData.count) sources")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()

            Divider()

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(scanner.appData) { item in
                        AppDataCard(
                            item: item,
                            onClean: { itemToClean = item },
                            onTap: { drillDownItem = item }
                        )
                    }
                }
                .padding()
            }
        }
        .alert("Clean \(itemToClean?.name ?? "")?", isPresented: isShowingAlert) {
            Button("Cancel", role: .cancel) { itemToClean = nil }
            Button("Clean", role: .destructive) {
                if let item = itemToClean { scanner.cleanAppData(item) }
                itemToClean = nil
            }
        } message: {
            Text(itemToClean.map { "\($0.desc)\n\nThis will free \(DiskScanner.fmt($0.size))." } ?? "")
        }
    }
}

struct AppDataDetailView: View {
    @EnvironmentObject var scanner: DiskScanner
    let item: AppDataItem
    let onBack: () -> Void
    @State private var contents: [SubItem] = []
    @State private var selected = Set<UUID>()
    @State private var isScanning = true
    @State private var showConfirm = false

    var selectedSize: Int64 {
        contents.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        VStack(spacing: 0) {
            detailHeader
            Divider()
            detailActions
            Divider()
            detailList
        }
        .onAppear {
            scanner.scanDirectory(item.path) { items in
                contents = items
                isScanning = false
            }
        }
        .alert("Delete selected items?", isPresented: $showConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete \(selected.count) items", role: .destructive) {
                let paths = contents.filter { selected.contains($0.id) }.map(\.path)
                scanner.deleteSubItems(paths)
                contents.removeAll { selected.contains($0.id) }
                selected.removeAll()
            }
        } message: {
            Text("Delete \(selected.count) item(s) totaling \(DiskScanner.fmt(selectedSize))?")
        }
    }

    private var detailHeader: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
            }
            .buttonStyle(.plain)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(item.name).font(.title2.bold())
                Text("\(DiskScanner.fmt(item.size)) total")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private var detailActions: some View {
        HStack {
            Button("Select All") { selected = Set(contents.map(\.id)) }
                .buttonStyle(.bordered)
            Button("Deselect All") { selected.removeAll() }
                .buttonStyle(.bordered)
                .disabled(selected.isEmpty)
            Spacer()
            Button("Delete Selected (\(DiskScanner.fmt(selectedSize)))") { showConfirm = true }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(selected.isEmpty)
        }
        .padding(.horizontal).padding(.vertical, 8)
    }

    @ViewBuilder
    private var detailList: some View {
        if isScanning {
            Spacer()
            ProgressView("Scanning contents...")
            Spacer()
        } else if contents.isEmpty {
            Spacer()
            Text("No scannable contents found").foregroundStyle(.secondary)
            Spacer()
        } else {
            List {
                ForEach(contents) { sub in
                    HStack {
                        Toggle("", isOn: Binding(
                            get: { selected.contains(sub.id) },
                            set: { v in if v { selected.insert(sub.id) } else { selected.remove(sub.id) } }
                        ))
                        .toggleStyle(.checkbox)
                        .frame(width: 24)

                        Text(sub.name)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(DiskScanner.fmt(sub.size))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.plain)
        }
    }
}

// MARK: - Applications

struct AppsView: View {
    @EnvironmentObject var scanner: DiskScanner

    var totalSize: Int64 { scanner.applications.reduce(0) { $0 + $1.size } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Applications").font(.title2.bold())
                    Text("\(scanner.applications.count) apps \u{00B7} \(DiskScanner.fmt(totalSize)) total")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Uninstall apps via Finder or Launchpad")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            List(scanner.applications) { app in
                HStack {
                    Text(app.name).lineLimit(1)
                    Spacer()
                    Text(DiskScanner.fmt(app.size))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
            .listStyle(.plain)
        }
    }
}
