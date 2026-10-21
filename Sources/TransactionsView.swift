import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct TransactionsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var state: AppState
    @State var typeFilter: TxType?
    @State var catFilter: Category?
    @State var methodFilter: PayMethod?
    @State var confirmDelete: Transaction?

    var searching: Bool { !state.search.trimmingCharacters(in: .whitespaces).isEmpty }

    var filtered: [Transaction] {
        let q = state.search.trimmingCharacters(in: .whitespaces).lowercased()
        return store.ledger.transactions.filter { t in
            if searching {
                guard t.title.lowercased().contains(q) || t.memo.lowercased().contains(q) || t.category.label.contains(q) else { return false }
            } else if t.month != state.month { return false }
            if let f = typeFilter, t.type != f { return false }
            if let f = catFilter, t.category != f { return false }
            if let f = methodFilter, t.method != f { return false }
            return true
        }
    }

    var body: some View {
        let rows = filtered
        let groups = Dictionary(grouping: rows, by: { $0.date }).sorted { $0.key > $1.key }
        let tot = Calc.totals(rows, month: searching ? "" : state.month)

        PageScaffold(title: searching ? "검색 결과" : "입금·지출",
                     subtitle: searching ? "‘\(state.search)’ · 모든 달에서 \(rows.count)건" : "\(DateUtil.monthTitle(state.month)) · \(rows.count)건") {
            if searching {
                Button("검색 지우기") { state.search = "" }.dfButton(.secondary, small: true)
            } else {
                MonthSwitcher()
            }
        } content: {
            HStack(spacing: 10) {
                Button { state.importing = true } label: { Label("사진·PDF로 기록", systemImage: "doc.viewfinder") }
                    .dfButton(.primary)
                Button { state.newTransaction(store) } label: { Label("기록 추가", systemImage: "plus") }
                    .dfButton(.secondary)
                Spacer()
                filterMenu("유형", value: typeFilter?.label) {
                    Button("전체") { typeFilter = nil }
                    ForEach(TxType.allCases) { t in Button(t.label) { typeFilter = t } }
                }
                filterMenu("카테고리", value: catFilter?.label) {
                    Button("전체") { catFilter = nil }
                    ForEach(Category.allCases) { c in Button(c.label) { catFilter = c } }
                }
                filterMenu("결제수단", value: methodFilter?.label) {
                    Button("전체") { methodFilter = nil }
                    ForEach(PayMethod.allCases) { m in Button(m.label) { methodFilter = m } }
                }
                if !searching {
                    Button { exportCSV() } label: { Label("CSV", systemImage: "square.and.arrow.up") }
                        .dfButton(.ghost, small: true).help("이번 달 기록을 CSV로 내보내기")
                }
            }

            if !searching {
                HStack(spacing: 24) {
                    miniStat("입금", tot.income, DF.success)
                    miniStat("지출", tot.expense, DF.ink)
                    if tot.excluded > 0 { miniStat("합계 제외 (카드대금·이체)", tot.excluded, DF.helper) }
                    Spacer()
                }
            }

            if rows.isEmpty {
                CardBox {
                    EmptyState(icon: searching ? "magnifyingglass" : "tray",
                               title: searching ? "찾는 기록이 없어요" : "이 달의 기록이 없어요",
                               text: searching ? "다른 단어로 검색해보세요." : "‘기록 추가’나 ‘사진·PDF로 기록’으로 시작해보세요.")
                }
            } else {
                CardBox(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(groups, id: \.key) { g in
                            dayHeader(g.key, g.value)
                            ForEach(g.value) { t in
                                TxRow(tx: t)
                                    .padding(.horizontal, 20)
                                    .contentShape(Rectangle())
                                    .onTapGesture { state.editing = t }
                                    .contextMenu {
                                        Button("수정") { state.editing = t }
                                        Button("복제") {
                                            var c = t; c.id = UUID().uuidString; c.autoKey = nil
                                            store.add([c])
                                        }
                                        Divider()
                                        Button("삭제", role: .destructive) { confirmDelete = t }
                                    }
                                Divider1().padding(.leading, 20)
                            }
                        }
                    }
                }
            }
        }
        .confirmationDialog("이 기록을 삭제할까요?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                            presenting: confirmDelete) { t in
            Button("삭제", role: .destructive) { store.delete([t.id]) }
            Button("취소", role: .cancel) {}
        } message: { t in
            Text(t.autoKey != nil ? "자동으로 만든 기록이에요. 삭제하면 이 회차는 다시 만들지 않아요." : "\(t.date) · \(t.title) · \(Money.won(t.amount))")
        }
    }

    func filterMenu<C: View>(_ label: String, value: String?, @ViewBuilder items: () -> C) -> some View {
        Menu { items() } label: {
            HStack(spacing: 4) {
                Text(value ?? label).font(T.sans(13, value == nil ? 400 : 600))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(value == nil ? DF.label : DF.primary)
            .padding(.horizontal, 10).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 4).fill(value == nil ? DF.fill : DF.primarySoft))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }

    func miniStat(_ label: String, _ v: Int, _ c: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).font(T.sans(13)).foregroundStyle(DF.helper)
            Text(Money.won(v)).font(T.sans(16, 700)).foregroundStyle(c)
        }
    }

    func dayHeader(_ day: String, _ txs: [Transaction]) -> some View {
        let t = Calc.totals(txs, month: DateUtil.monthKey(day))
        return HStack {
            Text("\(searching ? day : DateUtil.shortDay(day)) (\(DateUtil.weekday(day)))").font(T.mono(12, 500)).foregroundStyle(DF.label)
            Spacer()
            if t.expense != 0 { Text("지출 \(Money.won(t.expense))").font(T.sans(12)).foregroundStyle(DF.helper) }
            if t.income > 0 { Text("입금 \(Money.won(t.income))").font(T.sans(12)).foregroundStyle(DF.success) }
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
        .background(DF.background)
    }

    func exportCSV() {
        let p = NSSavePanel()
        p.allowedContentTypes = [.commaSeparatedText]
        p.nameFieldStringValue = "차곡-\(state.month).csv"
        if p.runModal() == .OK, let u = p.url {
            do { try store.csv(month: state.month).write(to: u); store.toast = "CSV로 내보냈어요." }
            catch { store.toast = "내보내지 못했어요: \(error.localizedDescription)" }
        }
    }
}

struct TxRow: View {
    @EnvironmentObject var store: Store
    var tx: Transaction
    var compact = false
    @State var hover = false

    var body: some View {
        let cardName = tx.cardId.flatMap { id in store.ledger.settings.cards.first { $0.id == id }?.name }
        HStack(spacing: 12) {
            if compact {
                Text(DateUtil.shortDay(tx.date)).font(T.mono(12)).foregroundStyle(DF.helper).frame(width: 40, alignment: .leading)
            }
            TypeBadge(type: tx.type)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(tx.title.isEmpty ? "(내용 없음)" : tx.title).font(T.sans(compact ? 14 : 15, 500)).foregroundStyle(DF.ink).lineLimit(1)
                    if tx.autoKey != nil { Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 10)).foregroundStyle(DF.helper).help("자동 기록") }
                    if tx.installments > 1 { Pill(text: "\(tx.installments)개월") }
                }
                if !compact {
                    HStack(spacing: 6) {
                        Text(tx.method == .card ? (cardName ?? "카드") : tx.method.label).font(T.sans(12)).foregroundStyle(DF.helper)
                        if !tx.memo.isEmpty { Text("· \(tx.memo)").font(T.sans(12)).foregroundStyle(DF.helper).lineLimit(1) }
                    }
                }
            }
            Spacer(minLength: 8)
            if tx.type == .expense || tx.type == .refund { Chip(text: tx.category.label, color: DF.category(tx.category)) }
            Text(amountText).font(T.sans(compact ? 14 : 15, 600)).foregroundStyle(DF.amountColor(tx.type))
                .frame(minWidth: compact ? 90 : 120, alignment: .trailing)
        }
        .frame(minHeight: compact ? 44 : 56)
        .background(hover && !compact ? DF.line.opacity(0.6) : .clear)
        .onHover { hover = $0 }
    }

    var amountText: String {
        switch tx.type {
        case .income: return "+" + Money.won(tx.amount)
        case .refund: return "+" + Money.won(tx.amount)
        case .expense: return "−" + Money.won(tx.amount)
        default: return Money.won(tx.amount)
        }
    }
}

// MARK: - 기록 추가·수정

struct TransactionEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    var original: Transaction
    @State var tx: Transaction
    @State var date: Date
    @State var categoryTouched = false
    @State var tried = false
    @State var confirmDelete = false

    init(original: Transaction) {
        self.original = original
        _tx = State(initialValue: original)
        _date = State(initialValue: DateUtil.date(original.date) ?? Date())
        _categoryTouched = State(initialValue: !original.title.isEmpty)
    }

    var isNew: Bool { !store.ledger.transactions.contains { $0.id == original.id } }
    var cards: [Card] { store.ledger.settings.cards }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(isNew ? "기록 추가" : "기록 수정").font(T.subhead).foregroundStyle(DF.ink)
                Spacer()
                if tx.autoKey != nil { Chip(text: "자동 기록") }
            }
            .padding(24)
            Divider1()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Field(label: "유형") {
                        HStack(spacing: 6) {
                            ForEach(TxType.allCases) { t in
                                Button { setType(t) } label: {
                                    Text(t.label).font(T.sans(13, tx.type == t ? 600 : 400))
                                        .foregroundStyle(tx.type == t ? DF.badgeColors(t).1 : DF.label)
                                        .padding(.horizontal, 10).frame(height: 30)
                                        .background(RoundedRectangle(cornerRadius: 6).fill(tx.type == t ? DF.badgeColors(t).0 : DF.fill))
                                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(tx.type == t ? DF.badgeColors(t).1.opacity(0.5) : .clear))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if tx.type == .cardPayment || tx.type == .transfer {
                        Callout(kind: .info, text: tx.type == .cardPayment
                                ? "카드대금 납부는 이미 사용일에 지출로 잡힌 금액이라 총 지출에 다시 더하지 않아요."
                                : "내 계좌끼리 옮긴 돈은 입금·지출 합계에서 빠져요.")
                    }
                    HStack(alignment: .top, spacing: 16) {
                        Field(label: tx.type == .income ? "입금일" : "사용일") {
                            DatePicker("", selection: $date, displayedComponents: .date)
                                .labelsHidden().datePickerStyle(.field)
                                .environment(\.locale, Locale(identifier: "ko_KR"))
                                .environment(\.timeZone, DateUtil.tz)
                                .frame(height: 36)
                        }
                        .frame(width: 170)
                        Field(label: "금액", error: tried && tx.amount <= 0 ? "금액을 입력해주세요" : nil) {
                            MoneyField(value: $tx.amount, invalid: tried && tx.amount <= 0)
                        }
                    }
                    Field(label: tx.type == .income ? "입금 내역" : "상호명·내용") {
                        DFTextField(placeholder: tx.type == .income ? "예: 월급, 용돈" : "예: 스타벅스 역삼점", text: $tx.title)
                            .onChange(of: tx.title) { new in
                                if !categoryTouched { tx.category = Calc.guessCategory(new, rules: store.ledger.settings.merchantRules) }
                            }
                    }
                    if tx.type == .expense || tx.type == .refund {
                        Field(label: "카테고리") {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                                ForEach(Category.allCases) { c in
                                    Button { tx.category = c; categoryTouched = true } label: {
                                        HStack(spacing: 6) {
                                            Circle().fill(DF.category(c)).frame(width: 7, height: 7)
                                            Text(c.label).font(T.sans(13, tx.category == c ? 600 : 400))
                                        }
                                        .foregroundStyle(tx.category == c ? DF.primary : DF.label)
                                        .frame(maxWidth: .infinity).frame(height: 32)
                                        .background(RoundedRectangle(cornerRadius: 6).fill(tx.category == c ? DF.primarySoft : DF.fill))
                                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(tx.category == c ? DF.primary : .clear))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    HStack(alignment: .top, spacing: 16) {
                        Field(label: "결제수단") {
                            DFPickerBox {
                                Picker("", selection: $tx.method) {
                                    ForEach(PayMethod.allCases) { m in Text(m.label).tag(m) }
                                }
                            }
                        }
                        if tx.method == .card {
                            Field(label: "카드", helper: cards.isEmpty ? "설정에서 카드를 추가할 수 있어요" : nil) {
                                DFPickerBox {
                                    Picker("", selection: $tx.cardId) {
                                        Text("카드 미지정").tag(String?.none)
                                        ForEach(cards) { c in Text(c.name).tag(Optional(c.id)) }
                                    }
                                }
                            }
                            if tx.type == .expense {
                                Field(label: "할부") {
                                    DFPickerBox {
                                        Picker("", selection: $tx.installments) {
                                            Text("일시불").tag(1)
                                            ForEach(2...36, id: \.self) { n in Text("\(n)개월").tag(n) }
                                        }
                                    }
                                }
                                .frame(width: 120)
                            }
                        }
                    }
                    if tx.type == .expense && tx.method == .card && tx.installments > 1 && tx.amount > 0 {
                        let per = Calc.installmentPortion(amount: tx.amount, count: tx.installments, index: 0)
                        let last = Calc.installmentPortion(amount: tx.amount, count: tx.installments, index: tx.installments - 1)
                        Text("구매 총액은 이번 달 지출에 잡히고, 카드 청구는 매달 \(Money.won(per))" + (last != per ? " (마지막 회차 \(Money.won(last)))" : "") + "씩 나뉘어요.")
                            .font(T.sans(12)).foregroundStyle(DF.secondary)
                    }
                    Field(label: "메모") {
                        DFTextField(placeholder: "선택 입력", text: $tx.memo)
                    }
                }
                .padding(24)
            }

            Divider1()
            HStack {
                if !isNew {
                    Button("삭제") { confirmDelete = true }.dfButton(.destructive)
                }
                Spacer()
                Button("취소") { dismiss() }.dfButton(.ghost).keyboardShortcut(.cancelAction)
                Button(isNew ? "추가" : "저장") { save() }.dfButton(.primary).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
        }
        .frame(width: 600, height: 680)
        .background(DF.surface)
        .confirmationDialog("이 기록을 삭제할까요?", isPresented: $confirmDelete) {
            Button("삭제", role: .destructive) { store.delete([original.id]); dismiss() }
        } message: {
            Text(original.autoKey != nil ? "자동으로 만든 기록이에요. 삭제하면 이 회차는 다시 만들지 않아요." : "삭제한 기록은 백업 폴더에서만 되찾을 수 있어요.")
        }
    }

    func setType(_ t: TxType) {
        tx.type = t
        switch t {
        case .income, .transfer, .cardPayment:
            tx.method = .account; tx.installments = 1
        case .expense, .refund:
            if tx.method == .account && tx.type != original.type { tx.method = .card }
        }
        if t != .expense { tx.installments = 1 }
    }

    func save() {
        tried = true
        guard tx.amount > 0 else { return }
        var t = tx
        t.date = DateUtil.string(date)
        t.title = t.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.method != .card { t.cardId = nil; t.installments = 1 }
        if t.type != .expense { t.installments = 1 }
        if (t.type == .expense || t.type == .refund) && !t.title.isEmpty
            && t.category != Calc.guessCategory(t.title, rules: [:]) {
            store.learn([(t.title, t.category)])
        }
        store.upsert(t)
        dismiss()
    }
}
