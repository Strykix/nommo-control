import SwiftUI

@main
struct RazerNommoControlApp: App {
    @StateObject private var bluetooth = BluetoothManager()
    @StateObject private var lighting = LightingController()
    @StateObject private var classic = ClassicBluetoothScanner()

    var body: some Scene {
        WindowGroup("Nommo Control") {
            ContentView()
                .environmentObject(bluetooth)
                .environmentObject(lighting)
                .environmentObject(classic)
                .frame(minWidth: 940, minHeight: 620)
        }
        .windowResizability(.contentMinSize)
    }
}
