import SwiftUI
import TipKit

@main
struct MyApp: App {
    @StateObject private var storage = StorageService()

    init() {
        do {
            try Tips.configure([
                .displayFrequency(.immediate)
            ])
        } catch {
            print("TipKit configuration failed: \(error.localizedDescription)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(storage)
        }
    }
}
