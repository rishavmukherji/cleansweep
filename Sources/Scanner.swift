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
}

enum ScanCategory: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case nodeModules = "node_modules"
    case buildArtifacts = "Build Artifacts"
    case caches = "Caches"
    case appData = "App & Dev Data"
    case applications = "Applications"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.33percent"
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
        let numStr: String
        let mult: Double
        if t.hasSuffix("T") { numStr = String(t.dropLast()); mult = 1_099_511_627_776 }
        else if t.hasSuffix("G") { numStr = String(t.dropLast()); mult = 1_073_741_824 }
        else if t.hasSuffix("M") { numStr = String(t.dropLast()); mult = 1_048_576 }
        else if t.hasSuffix("K") { numStr = String(t.dropLast()); mult = 1024 }
        else if t.hasSuffix("B") { numStr = String(t.dropLast()); mult = 1 }
        else { numStr = t; mult = 1 }
        return Int64((Double(numStr) ?? 0) * mult)
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
        DispatchQueue.main.async { self.isScanning = true }

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

    private func _scanAppData() {
        let checks: [(String, String, String, String)] = [
            // App caches
            ("Claude VM Bundles",
             "Sandboxed environments for code execution. Re-downloads on demand.",
             "\(home)/Library/Application Support/Claude/vm_bundles", "cpu"),
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

    func scanDirectory(_ path: String, completion: @escaping ([SubItem]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let out = shell("du -sh '\(path)'/* 2>/dev/null | sort -hr")
            var items: [SubItem] = []
            for line in out.split(separator: "\n") {
                let parts = line.split(separator: "\t", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let size = parseSize(String(parts[0]))
                let p = String(parts[1])
                let name = (p as NSString).lastPathComponent
                guard size > 0 else { continue }
                items.append(SubItem(path: p, name: name, size: size))
            }
            DispatchQueue.main.async { completion(items) }
        }
    }

    func deleteSubItems(_ paths: [String]) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            for p in paths { shell("rm -rf '\(p)'") }
            _scanAppData()
            _scanDisk()
        }
    }
}
