import SwiftUI

/// 设置 › 词表: the switches for 改正听错的词, and the word list itself (`Vocabulary`): each word,
/// what it has been heard as, where it came from and how often it fixed a line.
struct WordListSettings: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var vocabulary: Vocabulary
    @ObservedObject var ling: LingClient
    @State private var importing = false
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard {
                SettingsRow(title: L("会中改正听错的词"),
                            detail: ling.usable ? L("走 \(ling.provider.name)，只发文字") : L("接上 AI 服务后才会改")) {
                    Toggle("会中改正听错的词", isOn: $settings.fixMisheard)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small).tint(Palette.ink)
                }
                SettingsRow(title: L("没见过的名字和专称先问我"), detail: L("关掉就只改词表里的词和同音错字"), divider: false) {
                    Toggle("没见过的名字和专称先问我", isOn: $settings.askNames)
                        .toggleStyle(.switch).labelsHidden().controlSize(.small).tint(Palette.ink)
                        .disabled(!settings.fixMisheard)
                }
            }

            HStack(spacing: 10) {
                Text("词").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.secondary)
                if !vocabulary.terms.isEmpty {
                    Text("\(vocabulary.terms.count)").font(.system(size: 12).monospacedDigit()).foregroundStyle(Palette.tertiary)
                }
                Spacer()
                if vocabulary.terms.count > 12 {
                    TextField("搜索词表", text: $query).textFieldStyle(.roundedBorder).frame(width: 160).controlSize(.small)
                }
                SoftButton(L("粘贴导入…"), dark: true) { importing = true }
            }
            .padding(.top, 4)

            if vocabulary.terms.isEmpty {
                Text("还没有词。把常用的人名、产品名贴进来，会中就照这些写法改")
                    .font(.system(size: 12)).foregroundStyle(Palette.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
            } else {
                SettingsCard {
                    let list = shown
                    ForEach(Array(list.enumerated()), id: \.element.word) { i, t in
                        WordRow(term: t, divider: i < list.count - 1) { vocabulary.remove(t.word) }
                    }
                }
            }
            Text("最多 \(Vocabulary.limit) 个，满了优先用最近的。只存在这台 Mac 上")
                .font(.system(size: 11)).foregroundStyle(Palette.tertiary)
        }
        .sheet(isPresented: $importing) { WordImportSheet(vocabulary: vocabulary) }
    }

    /// Most recently useful first, then the rest by when they were added.
    private var shown: [Vocabulary.Term] {
        let q = Vocabulary.key(query)
        let all = vocabulary.terms.reversed().sorted { ($0.used ?? .distantPast) > ($1.used ?? .distantPast) }
        guard !q.isEmpty else { return all }
        return all.filter { Vocabulary.key($0.word).contains(q) || $0.heard.contains { Vocabulary.key($0).contains(q) } }
    }
}

private struct WordRow: View {
    let term: Vocabulary.Term
    let divider: Bool
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Text(term.word).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
                    .frame(width: 140, alignment: .leading).lineLimit(1)
                FlowLayout(spacing: 4) {
                    ForEach(term.heard, id: \.self) { h in
                        Text(h).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Palette.fill))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(term.source == "live" ? L("会中确认") : L("你加的"))
                    .font(.system(size: 11)).foregroundStyle(term.source == "live" ? Palette.accentInk : Palette.tertiary)
                    .lineLimit(1).fixedSize().frame(minWidth: 60, alignment: .leading)
                Text(term.fixes > 0 ? L("改过 \(term.fixes) 次") : L("还没用上"))
                    .font(.system(size: 11).monospacedDigit()).foregroundStyle(Palette.tertiary)
                    .lineLimit(1).fixedSize().frame(minWidth: 64, alignment: .leading)
                Button(action: onRemove) {
                    Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(Palette.tertiary)
                }
                .buttonStyle(.plain).help(L("从词表里删掉")).opacity(hovering ? 1 : 0.35)
            }
            .padding(.horizontal, 16).frame(minHeight: 40)
            if divider { Divider().padding(.leading, 16) }
        }
        .onHover { hovering = $0 }
    }
}

/// 粘贴导入: many words at once, each line one word, heard forms after "=". Lines that can't be
/// taken are reported by number; the rest go in.
private struct WordImportSheet: View {
    @ObservedObject var vocabulary: Vocabulary
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var result: Vocabulary.ImportResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("粘贴导入").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.ink)
            Text("一行一个。常被听错的词，写在 = 后面").font(.system(size: 12)).foregroundStyle(Palette.secondary)
            TextEditor(text: $text)
                .font(.system(size: 13)).frame(height: 180)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(verbatim: "Uniswap V3\nMorpho = 莫拉、莫法\n巡检")
                            .font(.system(size: 13)).foregroundStyle(Palette.placeholder).padding(.leading, 5).padding(.top, 1)
                            .allowsHitTesting(false)
                    }
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.line, lineWidth: 1))
            if let r = result {
                VStack(alignment: .leading, spacing: 4) {
                    Text("新增 \(r.added) · 更新 \(r.updated) · 跳过 \(r.skipped.count)")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.ink)
                    if !r.skipped.isEmpty {
                        Text("第 \(r.skipped.map(String.init).joined(separator: "、")) 行没加进去：超过 40 个字")
                            .font(.system(size: 11)).foregroundStyle(Palette.accentInk)
                    }
                }
            }
            HStack {
                Spacer()
                SoftButton(result == nil ? L("取消") : L("完成")) { dismiss() }
                if result == nil {
                    SoftButton(L("导入"), dark: true) {
                        result = vocabulary.importText(text)
                        text = ""
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(20).frame(width: 420)
    }
}
