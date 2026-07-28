import Foundation
import SwiftUI

// MARK: - Models

struct NodeModuleItem: Identifiable, Hashable {
    let id = UUID()
    let path: String
    let repoName: String
    let size: Int64
    let lastCommitDate: String

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

struct BuildArtifactItem: Identifiable, Hashable {
    let id = UUID()
    let path: String
    let repoName: String
    let size: Int64
    let artifactType: String
    let lastCommitDate: String

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

struct CacheItem: Identifiable {
    let id = UUID()
    let path: String
    let name: String
    let size: Int64
}

struct AppDataItem: Identifiable {
    let id = UUID()
    let name: String
    let desc: String
    let path: String
    let size: Int64
    let cleanPath: String
    let icon: String
}

struct AppItem: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let size: Int64
}

struct SubItem: Identifiable {
    let id = UUID()
    let path: String
    let name: String
    let size: Int64
    var isDirectory: Bool = true
    var referencingRepos: [String]? = nil
    var note: String? = nil
    var warning: String? = nil
    var deleteShellCommand: String? = nil
}

enum FolderKind {
    case regular
    case cloudSynced
}

struct FolderItem: Identifiable {
    let id = UUID()
    let name: String        // display label, e.g. "~/Library/CloudStorage"
    let path: String        // absolute path
    let size: Int64         // real on-disk bytes (allocated blocks)
    let isDirectory: Bool   // false for large top-level files (not drillable)
    let kind: FolderKind
    let note: String?       // guidance shown inline (esp. for cloud-synced)
}

enum ScanCategory: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case largestFolders = "Largest Folders"
    case nodeModules = "node_modules"
    case buildArtifacts = "Build Artifacts"
    case caches = "Caches"
    case appData = "App & Dev Data"
    case applications = "Applications"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.33percent"
        case .largestFolders: return "internaldrive"
        case .nodeModules: return "shippingbox"
        case .buildArtifacts: return "hammer"
        case .caches: return "archivebox"
        case .appData: return "app.badge.checkmark"
        case .applications: return "square.grid.2x2"
        }
    }
}

// MARK: - Scanner

class DiskScanner: ObservableObject {
    @Published var nodeModules: [NodeModuleItem] = []
    @Published var buildArtifacts: [BuildArtifactItem] = []
    @Published var caches: [CacheItem] = []
    @Published var appData: [AppDataItem] = []
    @Published var applications: [AppItem] = []
    @Published var largestFolders: [FolderItem] = []
    @Published var isLoadingLargestFolders = false
    private var largestFoldersLoaded = false
    @Published var isScanning = false
    @Published var scanProgress = ""
    @Published var diskTotal: Int64 = 0
    @Published var diskUsed: Int64 = 0
    @Published var diskFree: Int64 = 0
    @Published var lastScan: Date?

    var totalNodeModulesSize: Int64 { nodeModules.reduce(0) { $0 + $1.size } }
    var totalBuildArtifactsSize: Int64 { buildArtifacts.reduce(0) { $0 + $1.size } }
    var totalCachesSize: Int64 { caches.reduce(0) { $0 + $1.size } }
    var totalAppDataSize: Int64 { appData.reduce(0) { $0 + $1.size } }
    var totalReclaimable: Int64 {
        totalNodeModulesSize + totalBuildArtifactsSize + totalCachesSize + totalAppDataSize
    }
    var cloudSyncedFolders: [FolderItem] { largestFolders.filter { $0.kind == .cloudSynced } }
    var totalCloudSyncedSize: Int64 { cloudSyncedFolders.reduce(0) { $0 + $1.size } }

    private let home = FileManager.default.homeDirectoryForCurrentUser.path

    // MARK: - Shell

    @discardableResult
    private func shell(_ command: String) -> String {
        let process = Process()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        do { try process.run(); process.waitUntilExit() }
        catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Size helpers

    func parseSize(_ s: String) -> Int64 {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t != "0B" else { return 0 }
        let suffixes: [(String, Double)] = [
            ("TB", 1_099_511_627_776), ("GB", 1_073_741_824),
            ("MB", 1_048_576), ("kB", 1024), ("KB", 1024),
            ("T", 1_099_511_627_776), ("G", 1_073_741_824),
            ("M", 1_048_576), ("K", 1024), ("B", 1),
        ]
        for (suffix, mult) in suffixes where t.hasSuffix(suffix) {
            let numStr = String(t.dropLast(suffix.count))
            return Int64((Double(numStr) ?? 0) * mult)
        }
        return Int64(Double(t) ?? 0)
    }

    static func fmt(_ bytes: Int64) -> String {
        let b = Double(bytes)
        if b >= 1_000_000_000 { return String(format: "%.1f GB", b / 1_000_000_000) }
        if b >= 1_000_000 { return String(format: "%.0f MB", b / 1_000_000) }
        if b >= 1_000 { return String(format: "%.0f KB", b / 1_000) }
        return "\(bytes) B"
    }

    // MARK: - Scan all

    func scanAll() {
        guard !isScanning else { return }
        DispatchQueue.main.async {
            self.isScanning = true
            self.largestFoldersLoaded = false   // invalidate; reloads lazily on next visit
        }

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            setProgress("Checking disk...")
            _scanDisk()
            setProgress("Scanning node_modules...")
            _scanNodeModules()
            setProgress("Scanning build artifacts...")
            _scanBuildArtifacts()
            setProgress("Scanning caches...")
            _scanCaches()
            setProgress("Scanning app & dev data...")
            _scanAppData()
            setProgress("Scanning applications...")
            _scanApplications()

            DispatchQueue.main.async {
                self.isScanning = false
                self.scanProgress = ""
                self.lastScan = Date()
            }
        }
    }

    private func setProgress(_ msg: String) {
        DispatchQueue.main.async { self.scanProgress = msg }
    }

    // MARK: - Individual scans

    private func _scanDisk() {
        let url = URL(fileURLWithPath: "/")
        do {
            let vals = try url.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey
            ])
            let total = Int64(vals.volumeTotalCapacity ?? 0)
            let free = vals.volumeAvailableCapacityForImportantUsage ?? 0
            DispatchQueue.main.async {
                self.diskTotal = total
                self.diskFree = free
                self.diskUsed = total - free
            }
        } catch {}
    }

    private func _scanNodeModules() {
        let out = shell(
            "find '\(home)' -maxdepth 6 -name 'node_modules' -type d "
            + "-not -path '*/Library/*' "
            + "-not -path '*/.npm/*' "
            + "-not -path '*/.vscode/*' "
            + "-not -path '*/.pnpm-store/*' "
            + "-not -path '*/.mintlify/*' "
            + "-not -path '*/.next/*' "
            + "-not -path '*/node_modules/*/node_modules/*' 2>/dev/null"
        )

        var items: [NodeModuleItem] = []
        for line in out.split(separator: "\n") where !line.isEmpty {
            let path = String(line)
            let repoPath = path.replacingOccurrences(of: "/node_modules", with: "")
            let segments = repoPath.split(separator: "/")
            let repoName = segments.suffix(2).joined(separator: "/")
            let sizeStr = shell("du -sh '\(path)' 2>/dev/null | cut -f1")
            let size = parseSize(sizeStr)
            guard size > 1_048_576 else { continue }
            let commit = shell("git -C '\(repoPath)' log -1 --format='%ai' 2>/dev/null | cut -d' ' -f1")
            items.append(NodeModuleItem(
                path: path, repoName: repoName, size: size,
                lastCommitDate: commit.isEmpty ? "Unknown" : commit
            ))
        }
        DispatchQueue.main.async { self.nodeModules = items.sorted { $0.size > $1.size } }
    }

    private func _scanBuildArtifacts() {
        let out = shell(
            "find '\(home)' -maxdepth 6 -type d "
            + "\\( -name '.next' -o -name '.turbo' \\) "
            + "-not -path '*/Library/*' "
            + "-not -path '*/node_modules/*' "
            + "-not -path '*/.npm/*' 2>/dev/null"
        )

        var items: [BuildArtifactItem] = []
        for line in out.split(separator: "\n") where !line.isEmpty {
            let path = String(line)
            let dirName = (path as NSString).lastPathComponent
            let parentPath = (path as NSString).deletingLastPathComponent
            let segments = parentPath.split(separator: "/")
            let repoName = segments.suffix(2).joined(separator: "/")
            let sizeStr = shell("du -sh '\(path)' 2>/dev/null | cut -f1")
            let size = parseSize(sizeStr)
            guard size > 1_048_576 else { continue }
            let commit = shell("git -C '\(parentPath)' log -1 --format='%ai' 2>/dev/null | cut -d' ' -f1")
            items.append(BuildArtifactItem(
                path: path, repoName: repoName, size: size,
                artifactType: dirName,
                lastCommitDate: commit.isEmpty ? "Unknown" : commit
            ))
        }
        DispatchQueue.main.async { self.buildArtifacts = items.sorted { $0.size > $1.size } }
    }

    private func _scanCaches() {
        let out = shell("du -sh '\(home)/Library/Caches'/* 2>/dev/null | sort -hr")
        var items: [CacheItem] = []
        for line in out.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let size = parseSize(String(parts[0]))
            let path = String(parts[1])
            let name = path.split(separator: "/").last.map(String.init) ?? path
            guard size > 1_048_576 else { continue }
            items.append(CacheItem(path: path, name: name, size: size))
        }
        DispatchQueue.main.async { self.caches = items }
    }

    // Claude Desktop can be installed as multiple named profiles (Claude, Claude-Work,
    // Claude-Personal, ...), each with its own vm_bundles directory of several GB. Discover
    // them all instead of hardcoding the single default path.
    private func claudeVMBundleChecks() -> [(String, String, String, String)] {
        let appSupport = "\(home)/Library/Application Support"
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: appSupport) else {
            return []
        }
        var result: [(String, String, String, String)] = []
        for entry in entries.sorted() where entry == "Claude" || entry.hasPrefix("Claude-") {
            let vmPath = "\(appSupport)/\(entry)/vm_bundles"
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: vmPath, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            let profile = entry == "Claude" ? "" : String(entry.dropFirst("Claude-".count))
            let name = profile.isEmpty ? "Claude VM Bundles" : "Claude VM Bundles — \(profile)"
            let desc = profile.isEmpty
                ? "Sandboxed environments for code execution. Re-downloads on demand."
                : "Sandboxed environments for the \(profile) Claude profile. Re-downloads on demand."
            result.append((name, desc, vmPath, "cpu"))
        }
        return result
    }

    private func _scanAppData() {
        let checks: [(String, String, String, String)] = claudeVMBundleChecks() + [
            // App caches
            ("WhatsApp Media",
             "Cached media files. Originals stay on your phone.",
             "\(home)/Library/Group Containers/group.net.whatsapp.WhatsApp.shared/Message/Media", "message"),
            ("OrbStack / Docker",
             "Container images, volumes, and build cache.",
             "\(home)/Library/Group Containers/HUAQ24HBR6.dev.orbstack", "shippingbox"),
            ("Spotify Cache",
             "Cached songs and streaming data.",
             "\(home)/Library/Caches/com.spotify.client", "music.note"),
            ("Telegram Cache",
             "Cached media and files from Telegram.",
             "\(home)/Library/Caches/ru.keepcoder.Telegram", "paperplane"),
            // Dev tool caches
            ("pnpm Store",
             "Global pnpm package store. Packages re-download as needed.",
             "\(home)/Library/pnpm/store", "cube"),
            ("npm Cache",
             "Cached npm packages. npm repopulates as needed.",
             "\(home)/.npm/_cacache", "cube"),
            ("Yarn Cache",
             "Cached Yarn packages. Yarn repopulates as needed.",
             "\(home)/Library/Caches/Yarn", "cube"),
            ("Homebrew Cache",
             "Downloaded formula bottles. brew repopulates as needed.",
             "\(home)/Library/Caches/Homebrew", "mug"),
            ("CocoaPods Cache",
             "Cached pod specs and downloads.",
             "\(home)/Library/Caches/CocoaPods", "cube.box"),
            ("Go Module Cache",
             "Cached Go module source code.",
             "\(home)/go/pkg/mod", "cube"),
            ("Cargo Registry",
             "Cached Rust crate source code and build artifacts.",
             "\(home)/.cargo/registry", "cube"),
            ("pip Cache",
             "Cached Python packages.",
             "\(home)/Library/Caches/pip", "cube"),
            ("Gradle Cache",
             "Cached Gradle/Android build dependencies.",
             "\(home)/.gradle/caches", "cube"),
            // System
            ("Trash",
             "Files in your Trash. Empty to reclaim space permanently.",
             "\(home)/.Trash", "trash"),
            ("Xcode Derived Data",
             "Build artifacts from Xcode projects. Rebuilds as needed.",
             "\(home)/Library/Developer/Xcode/DerivedData", "hammer"),
        ]

        var items: [AppDataItem] = []
        for (name, desc, path, icon) in checks {
            let exists = FileManager.default.fileExists(atPath: path)
            guard exists else { continue }
            let sizeStr = shell("du -sh '\(path)' 2>/dev/null | cut -f1")
            let size = parseSize(sizeStr)
            guard size > 0 else { continue }
            items.append(AppDataItem(
                name: name, desc: desc, path: path,
                size: size, cleanPath: path, icon: icon
            ))
        }
        DispatchQueue.main.async { self.appData = items.sorted { $0.size > $1.size } }
    }

    private func _scanApplications() {
        let out = shell("du -sh /Applications/*.app 2>/dev/null | sort -hr")
        var items: [AppItem] = []
        for line in out.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let size = parseSize(String(parts[0]))
            let path = String(parts[1])
            let name = path.replacingOccurrences(of: "/Applications/", with: "")
                .replacingOccurrences(of: ".app", with: "")
            items.append(AppItem(name: name, path: path, size: size))
        }
        DispatchQueue.main.async { self.applications = items }
    }

    // Surfaces the true biggest consumers of disk space regardless of the curated
    // reclaimable allowlist — so cloud drives, media, and personal data can't hide.
    // `du` counts allocated blocks, so cloud placeholders (online-only files) count as
    // ~0; only data actually materialized on disk is reported.
    //
    // Lazy: this walks the whole home directory (including huge cloud-sync trees), which
    // is far heavier than the curated scans, so it runs only when the user opens the
    // Largest Folders tab — never as part of scanAll().
    func loadLargestFolders(force: Bool = false) {
        guard !isLoadingLargestFolders else { return }
        guard force || !largestFoldersLoaded else { return }
        DispatchQueue.main.async { self.isLoadingLargestFolders = true }
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let items = _computeLargestFolders()
            DispatchQueue.main.async {
                self.largestFolders = items
                self.isLoadingLargestFolders = false
                self.largestFoldersLoaded = true
            }
        }
    }

    private func _computeLargestFolders() -> [FolderItem] {
        let library = "\(home)/Library"
        let cloudStorageRoot = "\(home)/Library/CloudStorage"
        let mobileDocsRoot = "\(home)/Library/Mobile Documents"
        // Top-level home entries (visible + hidden) with ~/Library expanded one level,
        // since Library is a catch-all where the largest data usually hides.
        let out = shell(
            "setopt null_glob 2>/dev/null; "
            + "{ du -sh '\(home)'/* '\(home)'/.[!.]* 2>/dev/null | grep -v '/Library$'; "
            + "du -sh '\(library)'/* 2>/dev/null; } | sort -rh"
        )

        let fm = FileManager.default
        var items: [FolderItem] = []
        for line in out.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let size = parseSize(String(parts[0]))
            let path = String(parts[1])
            guard size > 104_857_600 else { continue }   // hide < 100 MB

            let display = path.hasPrefix(home)
                ? "~" + path.dropFirst(home.count)
                : path

            var isDir: ObjCBool = false
            let exists = fm.fileExists(atPath: path, isDirectory: &isDir)
            let isDirectory = exists && isDir.boolValue

            var kind: FolderKind = .regular
            var note: String? = nil
            if path.hasPrefix(cloudStorageRoot) {
                kind = .cloudSynced
                note = "Cloud-synced files kept on this Mac. Deleting here also removes them "
                    + "from the cloud. To reclaim safely: in Finder, right-click a folder → "
                    + "\"Make available online only\" (or turn off \"Available offline\")."
            } else if path.hasPrefix(mobileDocsRoot) {
                kind = .cloudSynced
                note = "iCloud Drive files kept on this Mac. To reclaim: System Settings → "
                    + "[your name] → iCloud → turn on \"Optimize Mac Storage,\" or remove "
                    + "downloads in Finder."
            }

            items.append(FolderItem(
                name: display, path: path, size: size,
                isDirectory: isDirectory, kind: kind, note: note
            ))
            if items.count >= 40 { break }
        }
        return items
    }

    // MARK: - Clean actions

    func deleteNodeModules(ids: Set<UUID>) {
        let targets = nodeModules.filter { ids.contains($0.id) }
        DispatchQueue.main.async {
            self.nodeModules.removeAll { ids.contains($0.id) }
        }
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            for item in targets { shell("rm -rf '\(item.path)'") }
            _scanDisk()
        }
    }

    func deleteBuildArtifacts(ids: Set<UUID>) {
        let targets = buildArtifacts.filter { ids.contains($0.id) }
        DispatchQueue.main.async {
            self.buildArtifacts.removeAll { ids.contains($0.id) }
        }
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            for item in targets { shell("rm -rf '\(item.path)'") }
            _scanDisk()
        }
    }

    func deleteCache(_ item: CacheItem) {
        DispatchQueue.main.async {
            self.caches.removeAll { $0.id == item.id }
        }
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            shell("rm -rf '\(item.path)'")
            _scanDisk()
        }
    }

    func clearAllCaches() {
        DispatchQueue.main.async { self.caches.removeAll() }
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            shell("rm -rf '\(home)/Library/Caches'/* 2>/dev/null")
            _scanCaches()
            _scanDisk()
        }
    }

    func cleanAppData(_ item: AppDataItem) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            if item.name.contains("Docker") {
                shell("docker system prune -af 2>/dev/null")
            } else if item.name == "Trash" {
                shell("rm -rf '\(item.cleanPath)'/* 2>/dev/null")
            } else {
                shell("rm -rf '\(item.cleanPath)'/* 2>/dev/null")
            }
            _scanAppData()
            _scanDisk()
        }
    }

    func scanPnpmStore(_ storePath: String, completion: @escaping ([SubItem]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let duOut = shell("du -sh '\(storePath)'/* 2>/dev/null | sort -hr")
            var versions: [(name: String, path: String, size: Int64)] = []
            for line in duOut.split(separator: "\n") {
                let parts = line.split(separator: "\t", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let size = parseSize(String(parts[0]))
                let p = String(parts[1])
                let name = (p as NSString).lastPathComponent
                guard size > 0 else { continue }
                versions.append((name, p, size))
            }

            let modOut = shell(
                "find '\(home)' -maxdepth 6 -name '.modules.yaml' -path '*/node_modules/*' "
                + "-not -path '*/Library/*' "
                + "-not -path '*/node_modules/*/node_modules/*' 2>/dev/null "
                + "| xargs grep -H storeDir 2>/dev/null"
            )

            var versionToRepos: [String: [String]] = [:]
            for line in modOut.split(separator: "\n") where !line.isEmpty {
                let s = String(line)
                guard let colonIdx = s.firstIndex(of: ":") else { continue }
                let modPath = String(s[..<colonIdx])
                let matchLine = String(s[s.index(after: colonIdx)...])
                guard let storeDir = Self.parseStoreDir(matchLine) else { continue }
                let versionName = (storeDir as NSString).lastPathComponent

                let repoPath = modPath.replacingOccurrences(of: "/node_modules/.modules.yaml", with: "")
                let segments = repoPath.split(separator: "/")
                let repoName = segments.suffix(2).joined(separator: "/")

                versionToRepos[versionName, default: []].append(repoName)
            }

            var items: [SubItem] = []
            for v in versions {
                let repos = (versionToRepos[v.name] ?? []).sorted()
                items.append(SubItem(path: v.path, name: v.name, size: v.size, referencingRepos: repos))
            }
            DispatchQueue.main.async { completion(items) }
        }
    }

    private static func parseStoreDir(_ line: String) -> String? {
        guard let range = line.range(of: "storeDir") else { return nil }
        let after = line[range.upperBound...]
        guard let colonIdx = after.firstIndex(of: ":") else { return nil }
        var value = String(after[after.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("\"") {
            value.removeFirst()
            if let q = value.firstIndex(of: "\"") { value = String(value[..<q]) }
        } else {
            if value.hasSuffix(",") { value.removeLast() }
            value = value.trimmingCharacters(in: .whitespaces)
        }
        return value.isEmpty ? nil : value
    }

    func scanClaudeVMBundles(_ rootPath: String, completion: @escaping ([SubItem]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let bundlePath = "\(rootPath)/claudevm.bundle"
            let warmPath = "\(rootPath)/warm"

            struct Entry { let file: String; let name: String; let note: String }
            let bundleEntries: [Entry] = [
                Entry(file: "rootfs.img",
                      name: "rootfs.img (live VM filesystem)",
                      note: "The running VM disk. Delete to force re-extraction from rootfs.img.zst on next sandbox use (no download)."),
                Entry(file: "rootfs.img.zst",
                      name: "rootfs.img.zst (compressed seed)",
                      note: "Compressed base image used to rebuild rootfs.img. Delete to force a fresh download (~2 GB) on next sandbox use."),
                Entry(file: "sessiondata.img",
                      name: "sessiondata.img (session overlay)",
                      note: "Writable overlay for the current/last sandbox session. Delete to reset session VM state only."),
                Entry(file: "efivars.fd",
                      name: "efivars.fd (UEFI variables)",
                      note: "VM firmware state. Tiny — only useful as part of clearing the whole bundle."),
            ]

            let openSet = openFilesIn(bundlePath)
            let liveWarning = "Claude VM is running and holds this file open. Deleting succeeds, but disk space won't actually free until every Claude Code session exits and the VM shuts down."

            var items: [SubItem] = []

            for entry in bundleEntries {
                let p = "\(bundlePath)/\(entry.file)"
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: p),
                      let size = attrs[.size] as? Int64, size > 0 else { continue }
                let isLive = openSet.contains(p)
                items.append(SubItem(
                    path: p, name: entry.name, size: size,
                    note: entry.note,
                    warning: isLive ? liveWarning : nil,
                    deleteShellCommand: "rm -f '\(p)'"
                ))
            }

            if FileManager.default.fileExists(atPath: warmPath) {
                let sizeStr = shell("du -sh '\(warmPath)' 2>/dev/null | cut -f1")
                let size = parseSize(sizeStr)
                if size > 0 {
                    items.append(SubItem(
                        path: warmPath,
                        name: "warm/ (pre-warmed VM cache)",
                        size: size,
                        note: "Cached pre-built layer for faster VM boot. Safe to clear; regenerates as needed.",
                        deleteShellCommand: "rm -rf '\(warmPath)'"
                    ))
                }
            }

            items.sort { $0.size > $1.size }
            DispatchQueue.main.async { completion(items) }
        }
    }

    private func openFilesIn(_ directory: String) -> Set<String> {
        let out = shell("/usr/sbin/lsof +D '\(directory)' 2>/dev/null | /usr/bin/awk 'NR>1 {for(i=9;i<=NF;i++) printf \"%s%s\", $i, (i==NF?\"\\n\":\" \")}'")
        return Set(out.split(separator: "\n").map(String.init))
    }

    func isOrbStackRunning() -> Bool {
        return FileManager.default.fileExists(atPath: "\(home)/.orbstack/run/docker.sock")
    }

    private func resolveDockerBin() -> String? {
        let candidates = [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "\(home)/.orbstack/bin/docker",
        ]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
            return c
        }
        return nil
    }

    func startOrbStack() {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            shell("/usr/bin/open -a OrbStack")
        }
    }

    func scanOrbStack(completion: @escaping ([SubItem], Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            guard isOrbStackRunning(), let docker = resolveDockerBin() else {
                DispatchQueue.main.async { completion([], false) }
                return
            }

            var items: [SubItem] = []
            let composeKey = "com.docker.compose.project="

            // Images
            let imagesOut = shell("'\(docker)' images --format '{{.ID}}|{{.Repository}}|{{.Tag}}|{{.Size}}' 2>/dev/null")
            for line in imagesOut.split(separator: "\n") {
                let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                guard parts.count == 4 else { continue }
                let id = parts[0], repo = parts[1], tag = parts[2]
                let size = parseSize(parts[3])
                guard size > 0 else { continue }
                let isDangling = (repo == "<none>" || tag == "<none>")
                let display = isDangling ? "\(id) (dangling)" : "\(repo):\(tag)"
                items.append(SubItem(
                    path: id,
                    name: "Image: \(display)",
                    size: size,
                    note: isDangling ? "Untagged image. Usually safe to remove." : nil,
                    deleteShellCommand: "'\(docker)' rmi -f '\(id)' 2>/dev/null"
                ))
            }

            // Containers (all)
            let containersOut = shell(
                "'\(docker)' ps -a --size --format '{{.ID}}|{{.Names}}|{{.Image}}|{{.Status}}|{{.Size}}|{{.Labels}}' 2>/dev/null"
            )
            for line in containersOut.split(separator: "\n") {
                let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                guard parts.count == 6 else { continue }
                let id = parts[0], name = parts[1], image = parts[2], status = parts[3]
                let sizeStr = parts[4].split(separator: " ").first.map(String.init) ?? "0B"
                let size = parseSize(sizeStr)
                let labels = parts[5]
                let project = labels.split(separator: ",")
                    .first(where: { $0.hasPrefix(composeKey) })
                    .map { String($0.dropFirst(composeKey.count)) }
                let running = status.lowercased().hasPrefix("up")
                var noteParts = ["image: \(image)"]
                if let p = project { noteParts.append("project: \(p)") }
                noteParts.append(running ? "running" : "stopped")
                items.append(SubItem(
                    path: id,
                    name: "Container: \(name)",
                    size: size,
                    note: noteParts.joined(separator: " · "),
                    deleteShellCommand: "'\(docker)' rm -f '\(id)' 2>/dev/null"
                ))
            }

            let volumesOut = shell(
                "'\(docker)' system df -v --format '{{range .Volumes}}{{.Name}}|{{.Size}}|{{.Labels}}\n{{end}}' 2>/dev/null"
            )
            for line in volumesOut.split(separator: "\n") {
                let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                guard parts.count >= 2 else { continue }
                let name = parts[0]
                let size = parseSize(parts[1])
                guard size > 0 else { continue }
                let labels = parts.count > 2 ? parts[2] : ""
                let project = labels.split(separator: ",")
                    .first(where: { $0.hasPrefix(composeKey) })
                    .map { String($0.dropFirst(composeKey.count)) }
                items.append(SubItem(
                    path: name,
                    name: "Volume: \(name)",
                    size: size,
                    note: project.map { "project: \($0)" },
                    deleteShellCommand: "'\(docker)' volume rm '\(name)' 2>/dev/null"
                ))
            }

            // Build cache (aggregate)
            let bcOut = shell(
                "'\(docker)' system df --format '{{.Type}}|{{.Size}}' 2>/dev/null | grep -i 'build cache' | head -1"
            )
            if let line = bcOut.split(separator: "\n").first {
                let parts = line.split(separator: "|").map(String.init)
                if parts.count >= 2 {
                    let bcSize = parseSize(parts[1])
                    if bcSize > 0 {
                        items.append(SubItem(
                            path: "build-cache",
                            name: "Build Cache",
                            size: bcSize,
                            note: "All buildkit cache layers. Clearing forces rebuild from scratch on next docker build.",
                            deleteShellCommand: "'\(docker)' builder prune -af 2>/dev/null"
                        ))
                    }
                }
            }

            items.sort { $0.size > $1.size }
            DispatchQueue.main.async { completion(items, true) }
        }
    }

    func scanDirectory(_ path: String, completion: @escaping ([SubItem]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let out = shell("du -sh '\(path)'/* 2>/dev/null | sort -hr")
            let fm = FileManager.default
            var items: [SubItem] = []
            for line in out.split(separator: "\n") {
                let parts = line.split(separator: "\t", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let size = parseSize(String(parts[0]))
                let p = String(parts[1])
                let name = (p as NSString).lastPathComponent
                guard size > 0 else { continue }
                var isDir: ObjCBool = false
                let isDirectory = fm.fileExists(atPath: p, isDirectory: &isDir) && isDir.boolValue
                items.append(SubItem(path: p, name: name, size: size, isDirectory: isDirectory))
            }
            DispatchQueue.main.async { completion(items) }
        }
    }

    func deleteSubItems(_ items: [SubItem]) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            for item in items {
                if let cmd = item.deleteShellCommand {
                    shell(cmd)
                } else {
                    shell("rm -rf '\(item.path)'")
                }
            }
            _scanAppData()
            _scanDisk()
        }
    }
}
