import WidgetKit
import SwiftUI

struct VaultEntry: TimelineEntry { let date: Date }
struct VaultProvider: TimelineProvider {
    func placeholder(in context: Context) -> VaultEntry { VaultEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (VaultEntry) -> Void) { completion(VaultEntry(date: Date())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<VaultEntry>) -> Void) {
        completion(Timeline(entries: [VaultEntry(date: Date())], policy: .never))
    }
}
struct VaultWidgetView: View {
    let entry: VaultEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "lock.shield.fill").font(.title)
            Text("Safe Vault").font(.headline)
            Text("Your private space. One tap away.").font(.caption)
            Spacer(minLength: 0)
            Text("Open vault →").font(.caption.bold())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .foregroundStyle(.white)
        .containerBackground(Color(red: 17/255, green: 45/255, blue: 50/255), for: .widget)
        .widgetURL(URL(string: "safevault://home"))
    }
}
@main
struct SafeVaultHomeWidget: Widget {
    let kind = "SafeVaultHomeWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: VaultProvider()) { entry in VaultWidgetView(entry: entry) }
            .configurationDisplayName("Safe Vault")
            .description("Open your vault without exposing personal information.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
