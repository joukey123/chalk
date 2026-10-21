import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ImportRow: Identifiable, Equatable {
    var id = UUID()
    var selected = true
    var date: String
    var title: String
    var amount: Int
    var type: TxType = .expense
    var category: Category
    var guessed: Category
    var installments = 1
    var dup = false
    var source: String
    var raw: String

    var dateValid: Bool { DateUtil.isValid(date) }
    var valid: Bool { dateValid && amount > 0 }
}

struct ImportSheet: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) var dismiss

    enum Stage { case pick, working, review }
    @State var stage: Stage = .pick
    @State var progress = ""
    @State var rows: [ImportRow] = []
    @State var warnings: [String] = []
    @State var emptyPages: [String] = []
    @State var rawPages: [(String, String)] = []
    @State var cardId: String?
    @State var dropHover = false
    @State var showRaw = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("사진·PDF로 기록").font(T.subhead).foregroundStyle(DF.ink)
                    Text("파일은 이 맥 안에서만 읽고, 원본은 저장하지 않아요.").font(T.sans(12)).foregroundStyle(DF.helper)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }.dfButton(.ghost, small: true).keyboardShortcut(.cancelAction)
            }
            .padding(24)
            Divider1()
            switch stage {
            case .pick: pickView
            case .working: workingView
            case .review: reviewView
            }
        }
        .frame(width: 980, height: 720)
        .background(DF.surface)
        .onAppear { cardId = store.ledger.settings.cards.first?.id }
    }

    // MARK: 1. 파일 고르기

    var pickView: some View {
        VStack(spacing: 20) {
            Spacer()
            VStack(spacing: 14) {
                Image(systemName: "doc.viewfinder").font(.system(size: 40)).foregroundStyle(DF.primary)
                Text("카드 이용내역·영수증 사진이나 PDF를 끌어다 놓으세요").font(T.sans(17, 600)).foregroundStyle(DF.ink)
                Text("JPG · PNG · WEBP · BMP · HEIC · PDF  ·  한 번에 10개까지").font(T.mono(12)).foregroundStyle(DF.helper)
                Button { choose() } label: { Label("파일 선택", systemImage: "folder") }.dfButton(.primary).padding(.top, 6)
            }
            .frame(maxWidth: .infinity).frame(height: 300)
            .background(RoundedRectangle(cornerRadius: 12).fill(dropHover ? DF.primarySoft : DF.background))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(dropHover ? DF.primary : DF.border, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
            .onDrop(of: [.fileURL], isTargeted: $dropHover) { providers in
                loadDropped(providers); return true
            }
            VStack(alignment: .leading, spacing: 6) {
                tip("글자가 들어 있는 PDF는 글자를 그대로 읽고, 스캔한 PDF와 사진은 맥 내장 문자 인식으로 읽어요.")
                tip("비밀번호가 걸린 PDF는 비밀번호를 물어봐요. 비밀번호는 저장하지 않아요.")
                tip("사진 15MB, PDF 20MB, 파일당 30페이지(한 번에 60페이지)까지 읽어요.")
                tip("읽은 내용은 저장 전에 확인하고 고칠 수 있어요. 날짜나 금액을 못 읽은 줄은 임의로 채우지 않아요.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
        }
        .padding(.horizontal, 40)
    }

    func tip(_ s: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(DF.success).padding(.top, 4)
            Text(s).font(T.sans(13)).foregroundStyle(DF.tertiary)
        }
    }

    func choose() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        p.canChooseDirectories = false
        p.allowedContentTypes = [.pdf, .jpeg, .png, .bmp, .heic, .image] + [UTType("org.webmproject.webp")].compactMap { $0 }
        if p.runModal() == .OK { start(p.urls) }
    }

    func loadDropped(_ providers: [NSItemProvider]) {
        var urls: [URL] = []
        let group = DispatchGroup()
        let lock = NSLock()
        for pr in providers {
            group.enter()
            _ = pr.loadObject(ofClass: URL.self) { url, _ in
                if let u = url { lock.lock(); urls.append(u); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) { if !urls.isEmpty { start(urls.sorted { $0.lastPathComponent < $1.lastPathComponent }) } }
    }

    // MARK: 2. 읽는 중

    var workingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView().controlSize(.large)
            Text("읽는 중…").font(T.sans(16, 600)).foregroundStyle(DF.ink)
            Text(progress).font(T.mono(12)).foregroundStyle(DF.helper)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @MainActor func start(_ urls: [URL]) {
        stage = .working
        let today = DateUtil.todayString()
        let rules = store.ledger.settings.merchantRules
        let existing = store.ledger.transactions
        Task {
            let outcome = await Recognizer.run(urls, askPassword: { name, wrong in
                askPassword(name, wrong: wrong)
            }, progress: { p in progress = p })

            var newRows: [ImportRow] = []
            var empties: [String] = []
            var raws: [(String, String)] = []
            for page in outcome.pages {
                let label = page.page.map { "\(page.file) · \($0)p" } ?? page.file
                raws.append(("\(label) (\(page.method))", page.lines.joined(separator: "\n")))
                let cands = Parser.parse(lines: page.lines, today: today)
                if cands.isEmpty { empties.append(label) }
                for c in cands {
                    guard newRows.count < Recognizer.maxItems else { break }
                    let cat = Calc.guessCategory(c.title, rules: rules)
                    newRows.append(ImportRow(date: c.date ?? "", title: c.title, amount: c.amount ?? 0, type: c.type,
                                             category: cat, guessed: cat, installments: c.installments, source: label, raw: c.raw))
                }
            }
            var warn = outcome.warnings
            if newRows.count >= Recognizer.maxItems { warn.append("한 번에 \(Recognizer.maxItems)건까지만 가져와요.") }
            // 중복 표시: 이미 있는 기록 + 이번에 읽은 것끼리
            var seen: [Transaction] = []
            for i in newRows.indices {
                let t = asTx(newRows[i])
                if Calc.isDuplicate(t, in: existing) || Calc.isDuplicate(t, in: seen) {
                    newRows[i].dup = true; newRows[i].selected = false
                }
                seen.append(t)
                if !newRows[i].valid { newRows[i].selected = false }
            }
            rows = newRows
            warnings = warn
            emptyPages = empties
            rawPages = raws
            stage = .review
        }
    }

    @MainActor func askPassword(_ name: String, wrong: Bool) -> String? {
        let a = NSAlert()
        a.messageText = wrong ? "비밀번호가 맞지 않아요" : "비밀번호가 필요한 PDF예요"
        a.informativeText = "\(name)\n카드사 이용내역 PDF는 보통 생년월일 6자리 등을 비밀번호로 써요. 비밀번호는 저장하지 않아요."
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        a.accessoryView = field
        a.addButton(withTitle: "열기")
        a.addButton(withTitle: "건너뛰기")
        a.window.initialFirstResponder = field
        return a.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }

    func asTx(_ r: ImportRow) -> Transaction {
        Transaction(date: r.date, type: r.type, title: r.title, amount: r.amount, category: r.category,
                    method: .card, cardId: cardId, installments: r.type == .expense ? r.installments : 1)
    }

    // MARK: 3. 확인·수정

    var reviewView: some View {
        let selected = rows.filter(\.selected)
        let invalidSelected = selected.filter { !$0.valid }.count
        let total = selected.filter(\.valid).reduce(0) { $0 + ($1.type == .refund ? -$1.amount : $1.amount) }

        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Text("\(rows.count)건을 찾았어요").font(T.sans(15, 600)).foregroundStyle(DF.ink)
                        if rows.contains(where: \.dup) { Chip(text: "중복 \(rows.filter(\.dup).count)건은 선택 해제", color: DF.warning) }
                        Spacer()
                        Text("카드").font(T.sans(13)).foregroundStyle(DF.helper)
                        DFPickerBox {
                            Picker("", selection: $cardId) {
                                Text("카드 미지정").tag(String?.none)
                                ForEach(store.ledger.settings.cards) { c in Text(c.name).tag(Optional(c.id)) }
                            }
                        }
                        .frame(width: 180)
                        Button("인식한 원문") { showRaw = true }.dfButton(.ghost, small: true)
                    }
                    ForEach(warnings, id: \.self) { w in Callout(kind: .warning, text: w) }
                    if !emptyPages.isEmpty {
                        Callout(kind: .warning, title: "내역을 찾지 못한 페이지가 있어요",
                                text: emptyPages.joined(separator: ", ") + " — 누락된 거래가 있을 수 있으니 ‘인식한 원문’을 확인하고 필요하면 직접 추가해주세요.")
                    }
                    if rows.isEmpty {
                        EmptyState(icon: "doc.text.magnifyingglass", title: "거래 내역을 찾지 못했어요",
                                   text: "날짜와 금액이 함께 있는 줄을 찾지 못했어요.\n‘행 추가’로 직접 입력하거나 더 선명한 파일로 다시 시도해보세요.")
                    } else {
                        header
                        ForEach($rows) { $r in ImportRowView(row: $r) }
                    }
                    Button { addRow() } label: { Label("행 추가", systemImage: "plus") }.dfButton(.ghost, small: true)
                    Text("업로드한 내역은 카드 지출로 저장돼요. 할부는 행에서 고르고, 환불은 유형을 ‘환불’로 바꿔주세요. 바꾼 카테고리는 상호별로 기억해 다음부터 적용해요.")
                        .font(T.sans(12)).foregroundStyle(DF.helper)
                }
                .padding(24)
            }
            Divider1()
            HStack(spacing: 10) {
                Button { stage = .pick; rows = [] } label: { Label("다른 파일", systemImage: "arrow.uturn.left") }.dfButton(.ghost)
                Spacer()
                if invalidSelected > 0 {
                    Text("날짜·금액을 확인해야 하는 행이 \(invalidSelected)개 있어요").font(T.sans(13)).foregroundStyle(DF.error)
                } else if !selected.isEmpty {
                    Text("합계 \(Money.won(total))").font(T.sans(13)).foregroundStyle(DF.helper)
                }
                Button("선택한 \(selected.count)건 저장") { saveRows() }
                    .dfButton(.primary).disabled(selected.isEmpty || invalidSelected > 0).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
        }
        .sheet(isPresented: $showRaw) { rawView }
    }

    var header: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(get: { !rows.isEmpty && rows.allSatisfy(\.selected) },
                                    set: { v in for i in rows.indices { rows[i].selected = v && (rows[i].valid) } }))
                .toggleStyle(.checkbox).labelsHidden().frame(width: 20)
            Text("날짜").frame(width: 112, alignment: .leading)
            Text("상호명").frame(maxWidth: .infinity, alignment: .leading)
            Text("금액").frame(width: 150, alignment: .leading)
            Text("유형").frame(width: 84, alignment: .leading)
            Text("카테고리").frame(width: 120, alignment: .leading)
            Text("할부").frame(width: 92, alignment: .leading)
            Text("").frame(width: 28)
        }
        .font(T.overline).tracking(0.6).foregroundStyle(DF.helper)
    }

    func addRow() {
        let today = DateUtil.todayString()
        rows.append(ImportRow(date: DateUtil.monthKey(today) == state.month ? today : state.month + "-01", title: "", amount: 0,
                              category: .etc, guessed: .etc, source: "직접 추가", raw: ""))
    }

    func saveRows() {
        let chosen = rows.filter { $0.selected && $0.valid }
        let learned = chosen.filter { $0.category != $0.guessed && !$0.title.isEmpty }.map { ($0.title, $0.category) }
        store.learn(learned)
        store.add(chosen.map { asTx($0) })
        store.toast = "\(chosen.count)건을 기록했어요."
        if let first = chosen.map(\.date).max() { state.month = DateUtil.monthKey(first) }
        state.page = .transactions
        dismiss()
    }

    var rawView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("인식한 원문").font(T.subhead)
                Spacer()
                Button("닫기") { showRaw = false }.dfButton(.secondary, small: true)
            }
            .padding(20)
            Divider1()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(rawPages.enumerated()), id: \.offset) { item in
                        let p = item.element
                        VStack(alignment: .leading, spacing: 6) {
                            Text(p.0).font(T.sans(13, 600)).foregroundStyle(DF.label)
                            Text(p.1.isEmpty ? "(읽은 글자가 없어요)" : p.1)
                                .font(T.mono(12)).foregroundStyle(DF.text).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(RoundedRectangle(cornerRadius: 12).fill(DF.background))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(DF.border))
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 720, height: 600)
        .background(DF.surface)
    }
}

struct ImportRowView: View {
    @Binding var row: ImportRow
    @State var dateText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Toggle("", isOn: $row.selected).toggleStyle(.checkbox).labelsHidden().frame(width: 20)
                DFTextField(placeholder: "2026-10-21", text: $dateText, mono: true, invalid: !row.dateValid)
                    .frame(width: 112)
                    .onAppear { dateText = row.date }
                    .onChange(of: dateText) { v in
                        let t = v.replacingOccurrences(of: ".", with: "-").replacingOccurrences(of: "/", with: "-")
                        row.date = t
                        if row.valid && !row.dup { row.selected = true }
                    }
                DFTextField(placeholder: "상호명", text: $row.title).frame(maxWidth: .infinity)
                MoneyField(value: $row.amount, invalid: row.amount <= 0).frame(width: 150)
                    .onChange(of: row.amount) { _ in if row.valid && !row.dup { row.selected = true } }
                DFPickerBox {
                    Picker("", selection: $row.type) {
                        Text("지출").tag(TxType.expense)
                        Text("환불").tag(TxType.refund)
                    }
                }
                .frame(width: 84)
                DFPickerBox {
                    Picker("", selection: $row.category) { ForEach(Category.allCases) { c in Text(c.label).tag(c) } }
                }
                .frame(width: 120)
                DFPickerBox {
                    Picker("", selection: $row.installments) {
                        Text("일시불").tag(1)
                        ForEach(2...36, id: \.self) { n in Text("\(n)개월").tag(n) }
                    }
                }
                .frame(width: 92).disabled(row.type != .expense)
                Image(systemName: "text.quote").foregroundStyle(DF.helper).frame(width: 28)
                    .help(row.raw.isEmpty ? row.source : "\(row.source)\n\(row.raw)")
            }
            HStack(spacing: 8) {
                Spacer().frame(width: 20)
                Text(row.source).font(T.mono(11)).foregroundStyle(DF.disabled)
                if row.dup { Chip(text: "이미 있는 기록과 같아요", color: DF.warning) }
                if !row.dateValid { Text("날짜를 YYYY-MM-DD로 입력해주세요").font(T.sans(11)).foregroundStyle(DF.error) }
                if row.amount <= 0 { Text("금액을 입력해주세요").font(T.sans(11)).foregroundStyle(DF.error) }
            }
        }
        .padding(.vertical, 6)
        .opacity(row.selected ? 1 : 0.6)
    }
}
