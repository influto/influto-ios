import SwiftUI

@main
struct InfluToSampleApp: App {
    @StateObject private var config = SampleConfig()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(config)
        }
    }
}
