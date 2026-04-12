import SwiftUI

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var storage: StorageService
    
    var body: some View {
        Group {
            if !storage.hasCompletedOnboarding {
                OnboardingView()
            } else {
                StoryListView()
            }
        }
        .background(AppPalette.background(for: colorScheme).ignoresSafeArea())
    }
}
