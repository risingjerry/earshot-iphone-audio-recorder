import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var library: Library
    @State private var pendingDelete: Recording?
    @State private var pickingFolder = false
    @State private var exportFolder = Export.folderDisplayName
    @State private var standby = Standby.enabled

    var body: some View {
        NavigationStack {
            List {
                Section {
                    RecordControls(broadcast: library.liveBroadcast)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } footer: {
                    Text("现场对话：用麦克风录身边的人说话。手机声音：录正在播放的视频、直播、会议、通话，只录声音不存画面；想把自己说的话也录进去，在弹出的面板里打开麦克风。")
                }

                Section {
                    Button { pickingFolder = true } label: {
                        LabeledContent("存到 iCloud", value: exportFolder ?? "未选择")
                    }
                    NavigationLink("设置 Action Button") { ActionButtonHelp() }
                    Toggle("待命模式", isOn: Binding(get: { standby }, set: { standby = $0; Standby.enabled = $0 }))
                    if standby {
                        TimelineView(.periodic(from: .now, by: 2)) { _ in
                            if Standby.isRunning {
                                Label(Standby.armed ? "待命中 · 正在录" : "待命中：按 Action Button 开始录",
                                      systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            } else {
                                Button("开启待命（点一次「开始直播」）") { AppState.shared.picker.tap() }
                            }
                        }
                    }
                } footer: {
                    Text(exportFolder == nil
                         ? "选 iCloud 云盘里一个和 Mac 共享的文件夹，录音会自动存进它的「录音」子文件夹，Mac 不在家也能收到并写好纪要。"
                         : "录完自动存进去；Mac 写好的纪要和文字稿会出现在同一个文件夹里。")
                         + Text("\n待命模式：录屏只开一次、一直在后台等着（不存任何声音，顶上红点常亮），之后看视频、直播时按一下 Action Button 就开始录，不用再点「开始直播」。")
                }

                if library.items.isEmpty {
                    Section { Text("还没有录音").foregroundStyle(.secondary) }
                } else {
                    Section("录音") {
                        ForEach(library.items) { item in
                            NavigationLink(value: item.id) { Row(item: item) }
                                .swipeActions {
                                    Button("删除", role: .destructive) { pendingDelete = item }
                                }
                        }
                    }
                }
            }
            .navigationTitle("Earshot")
            .navigationDestination(for: String.self) { id in
                if let item = library.items.first(where: { $0.id == id }) { DetailView(item: item) }
            }
            .refreshable { library.reload() }
            .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
                guard case .success(let url) = result else { return }
                try? Export.setFolder(url)
                exportFolder = Export.folderDisplayName
                library.reload()
            }
            .confirmationDialog("删除这条录音？", isPresented: Binding(get: { pendingDelete != nil },
                                                                 set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    if let item = pendingDelete { library.delete(item) }
                    pendingDelete = nil
                }
            } message: {
                Text("只删手机上的这份；已经传到 Mac 的不受影响。")
            }
        }
    }
}

private struct Row: View {
    let item: Recording

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: item.info.isConversation ? "mic.fill" : "iphone.radiowaves.left.and.right")
                    .foregroundStyle(item.info.isConversation ? Color.accentColor : .indigo)
                    .font(.subheadline)
                Text(item.title).font(.body.weight(.medium)).lineLimit(1)
                Spacer()
                Status(item: item)
            }
            Text("\(Format.date(item.info.startedAt)) · \(Format.minutes(item.info.duration)) · \(Format.sources(item.info))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}

struct Status: View {
    let item: Recording

    var body: some View {
        if item.isLive {
            Label("录音中", systemImage: "circle.fill").foregroundStyle(.red)
                .font(.caption).labelStyle(.titleAndIcon)
        } else if item.mac != nil {
            Label("已整理", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                .font(.caption)
        } else {
            Text("待整理").font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct ActionButtonHelp: View {
    var body: some View {
        List {
            Section {
                Text("1. 打开 设置 › 操作按钮")
                Text("2. 左右滑到「快捷指令」，点「选择快捷指令」")
                Text("3. 在「App」里找到 Earshot，选「录音」")
            } header: { Text("设置一次") }
            Section {
                Label("手机在放声音（视频、直播、会议、通话）→ 打开 Earshot 并弹出录屏面板，点一下「开始直播」就开始录这个声音。苹果规定这一下必须你自己点。", systemImage: "iphone.radiowaves.left.and.right")
                Label("没在放声音 → 直接用麦克风录现场对话，不用打开 App，灵动岛显示计时。", systemImage: "mic.fill")
                Label("录音中再按一次 → 停止。", systemImage: "stop.fill")
                Label("开了待命模式并开启待命后：手机在放声音时按一下直接开始录，不弹面板。", systemImage: "bolt.fill")
            } header: { Text("按一下会怎样") }
        }
        .navigationTitle("Action Button")
        .navigationBarTitleDisplayMode(.inline)
    }
}
