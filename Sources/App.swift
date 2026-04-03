import SwiftUI

@main
struct CleanSweepApp: App {
    @StateObject private var scanner = DiskScanner()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(scanner)
                .frame(minWidth: 800, minHeight: 500)
        }
        .defaultSize(width: 950, height: 650)
    }
}
