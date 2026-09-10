import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var bluetooth: BluetoothManager

    var body: some View {
        NavigationSplitView {
            DeviceListView()
                .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        } detail: {
            TabView {
                LightingView()
                    .tabItem { Label("Éclairage", systemImage: "lightbulb") }
                ExplorerView()
                    .tabItem { Label("Explorateur GATT", systemImage: "list.bullet.indent") }
                ClassicDevicesView()
                    .tabItem { Label("Bluetooth classique", systemImage: "hifispeaker") }
                LogView()
                    .tabItem { Label("Journal", systemImage: "text.alignleft") }
            }
            .padding(12)
        }
        .navigationTitle(bluetooth.connectedPeripheral?.name ?? "Nommo Control")
    }
}
