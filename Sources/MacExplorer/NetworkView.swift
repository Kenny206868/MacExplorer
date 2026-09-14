import SwiftUI
import Foundation
import ExplorerCore

struct DiscoveredServer: Identifiable {
    let id: String
    let name: String
    let host: String
}

@MainActor final class NetworkDiscovery: NSObject, ObservableObject, NetServiceBrowserDelegate, NetServiceDelegate {
    @Published var servers: [DiscoveredServer] = []
    @Published var error: String?
    private let browser = NetServiceBrowser()
    private var services: [NetService] = []
    func start() { browser.delegate = self; browser.searchForServices(ofType: "_smb._tcp.", inDomain: "local.") }
    func stop() { browser.stop(); services.forEach { $0.stop() }; services = [] }
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) { services.append(service); service.delegate = self; service.resolve(withTimeout: 8) }
    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) { services.removeAll { $0 == service }; servers.removeAll { $0.id == service.name + service.domain } }
    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) { error = "Bonjour discovery is unavailable. You can still connect using a server address. \(errorDict)" }
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let host = sender.hostName else { return }
        let id = sender.name + sender.domain
        servers.removeAll { $0.id == id }; servers.append(DiscoveredServer(id: id, name: sender.name, host: host)); servers.sort { $0.name < $1.name }
    }
}

struct NetworkView: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @StateObject private var discovery = NetworkDiscovery()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack { Text("Network").font(.system(size: 27, weight: .semibold)); Spacer(); Button("Connect to Server…") { workspace.sheet = .connect }.buttonStyle(.borderedProminent) }
                Text("Discover local SMB servers or connect directly to a share. Authentication and mounting are handled by macOS.").font(.callout).foregroundStyle(.secondary)
                if let error = discovery.error { Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.secondary) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))], spacing: 14) {
                    ForEach(discovery.servers) { server in
                        Button { NativeIntegration.connect("smb://" + server.host, owner: workspace) } label: {
                            HStack(spacing: 14) { Image(systemName: "server.rack").font(.system(size: 30)).foregroundStyle(.tint); VStack(alignment: .leading, spacing: 5) { Text(server.name).fontWeight(.medium); Text(server.host).font(.caption).foregroundStyle(.secondary) }; Spacer() }.padding(18).background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain)
                    }
                }
                if discovery.servers.isEmpty { ContentUnavailableView("No advertised SMB servers", systemImage: "network", description: Text("Discovery depends on Bonjour advertisements and local-network permission. A server can still be reached directly even if it does not appear here.")) }
                Text("Mounted network volumes also appear under This Mac and in the navigation tree.").font(.caption).foregroundStyle(.secondary)
            }.padding(27)
        }.onAppear { discovery.start() }.onDisappear { discovery.stop() }
    }
}
