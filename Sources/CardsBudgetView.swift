import SwiftUI

struct CardsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var state: AppState

    struct Bucket: Identifiable { var id: String; var name: String; var card: Card? }

    var body: some View {
        let l = store.ledger
        let m = state.month
        var buckets = l.settings.cards.map { Bucket(id: $0.id, name: $0.name, card: $0) }
        let cardIds = Set(l.settings.cards.map(\.id))
        let unassigned = l.transactions.contains { t in t.method == .card && (t.cardId == nil || !cardIds.contains(t.cardId ?? "")) }
        if unassigned { buckets.append(Bucket(id: "_none", name: "카드 미지정", card: nil)) }

        return PageScaffold(title: "카드 관리", subtitle: "\(DateUtil.monthTitle(m)) 사용분 기준 · 다음 달에 결제돼요") {
            MonthSwitcher()
        } content: {
            Callout(kind: .info, title: "지출과 카드 납부는 따로 계산해요",
                    text: "카드로 산 금액은 사용한 날 지출로 잡히고, 다음 달 계좌에서 빠지는 카드대금은 ‘카드대금 납부’로 기록해 총 지출에 다시 더하지 않아요. 청구 예상은 기록된 내역으로 계산한 값이라 카드사 청구서와 다를 수 있어요.")

            HStack(spacing: 16) {
                StatCard(label: "전체 청구 예상", value: Calc.cardBill(l.transactions, month: m), tint: DF.primary, note: "일시불 + 이번 달 할부 회차 − 카드 환불")
                StatCard(label: "남은 할부금", value: Calc.remainingInstallments(l.transactions, after: m), tint: DF.secondary, note: "\(DateUtil.monthTitle(m)) 이후 청구될 할부")
            }

            if buckets.isEmpty {
                CardBox {
                    EmptyState(icon: "creditcard", title: "등록된 카드가 없어요", text: "설정 › 카드에서 카드 이름과 결제일을 추가하면\n카드별 청구 예상과 결제일을 보여드려요.")
                }
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                    ForEach(buckets) { b in CardPanel(bucket: b, month: m) }
                }
            }
        }
    }
}

struct CardPanel: View {
    @EnvironmentObject var store: Store
    var bucket: CardsView.Bucket
    var month: String

    var body: some View {
        let txs = store.ledger.transactions
        let none = bucket.card == nil
        let validIds = Set(store.ledger.settings.cards.map(\.id))
        let mine = txs.filter { t in
            guard t.method == .card else { return false }
            if none { return t.cardId == nil || !validIds.contains(t.cardId!) }
            return t.cardId == bucket.id
        }
        let bill = mine.reduce(0) { $0 + Calc.billPortion($1, month: month) }
        let lump = mine.filter { $0.type == .expense && $0.installments <= 1 && $0.month == month }.reduce(0) { $0 + $1.amount }
        let refunds = mine.filter { $0.type == .refund && $0.month == month }.reduce(0) { $0 + $1.amount }
        let active = mine.filter { t in
            t.type == .expense && t.installments > 1 && (0..<t.installments).contains(DateUtil.monthDiff(t.month, month))
        }
        let instThisMonth = active.reduce(0) { $0 + Calc.billPortion($1, month: month) }
        let remaining = Calc.remainingInstallments(mine, after: month)

        CardBox(elevated: true) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "creditcard.fill").foregroundStyle(none ? DF.helper : DF.primary)
                    Text(bucket.name).font(T.sans(16, 700)).foregroundStyle(DF.ink)
                    Spacer()
                    if let c = bucket.card {
                        Pill(text: "결제 \(Calc.paymentDate(card: c, usageMonth: month))")
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Overline("청구 예상")
                    Text(Money.won(bill)).font(T.number(28)).foregroundStyle(DF.primary)
                }
                VStack(spacing: 8) {
                    line("일시불 사용", lump)
                    line("할부 회차 (\(active.count)건)", instThisMonth)
                    if refunds > 0 { line("카드 환불", -refunds) }
                    Divider1()
                    line("이후 남은 할부금", remaining, color: DF.secondary)
                }
                if !active.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Overline("진행 중인 할부")
                        ForEach(active) { t in
                            let idx = DateUtil.monthDiff(t.month, month)
                            HStack(spacing: 8) {
                                Text(t.title).font(T.sans(13)).foregroundStyle(DF.text).lineLimit(1)
                                Spacer()
                                Text("\(idx + 1)/\(t.installments)회").font(T.mono(12)).foregroundStyle(DF.secondary)
                                Text(Money.won(Calc.billPortion(t, month: month))).font(T.sans(13, 600)).foregroundStyle(DF.ink)
                            }
                            Bar(ratio: Double(idx + 1) / Double(t.installments), color: DF.secondary, height: 4)
                        }
                    }
                }
                if none {
                    Text("기록을 열어 카드를 지정하면 카드별로 나뉘어요.").font(T.sans(12)).foregroundStyle(DF.helper)
                }
            }
        }
    }

    func line(_ label: String, _ v: Int, color: Color = DF.ink) -> some View {
        HStack {
            Text(label).font(T.sans(13)).foregroundStyle(DF.tertiary)
            Spacer()
            Text(v < 0 ? "−" + Money.won(-v) : Money.won(v)).font(T.sans(14, 600)).foregroundStyle(color)
        }
    }
}

// MARK: - 예산

struct BudgetView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var state: AppState
    @State var total = 0
    @State var perCat: [Category: Int] = [:]
    @State var loaded = false

    var dirty: Bool {
        total != store.ledger.settings.totalBudget ||
        Category.allCases.contains { (perCat[$0] ?? 0) != store.ledger.settings.budget($0) }
    }

    var body: some View {
        let m = state.month
        let tot = Calc.totals(store.ledger.transactions, month: m)
        let by = Calc.byCategory(store.ledger.transactions, month: m)
        let catSum = Category.allCases.reduce(0) { $0 + (perCat[$1] ?? 0) }

        PageScaffold(title: "예산 관리", subtitle: "\(DateUtil.monthTitle(m)) 지출과 비교해요 · 예산은 매달 같은 금액으로 적용돼요") {
            MonthSwitcher()
        } content: {
            CardBox {
                HStack(alignment: .top, spacing: 32) {
                    Field(label: "전체 월 예산", helper: catSum > 0 ? "카테고리 예산 합계 \(Money.won(catSum))" : "0원이면 예산을 쓰지 않아요") {
                        MoneyField(value: $total).frame(width: 220)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Overline("이번 달 사용")
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(Money.won(tot.expense)).font(T.number(24)).foregroundStyle(DF.ink)
                            if total > 0 { Text("/ \(Money.won(total))").font(T.sans(14)).foregroundStyle(DF.helper) }
                        }
                        if total > 0 {
                            let r = Double(tot.expense) / Double(total)
                            Bar(ratio: r, color: r > 1 ? DF.error : r > 0.85 ? DF.warning : DF.primary)
                            Text(r > 1 ? "\(Money.won(tot.expense - total)) 초과했어요" : "\(Money.won(total - tot.expense)) 남았어요 · \(Int(r * 100))% 사용")
                                .font(T.sans(12)).foregroundStyle(r > 1 ? DF.error : DF.helper)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            CardBox(padding: 0) {
                VStack(spacing: 0) {
                    HStack {
                        Text("카테고리").frame(width: 150, alignment: .leading)
                        Text("예산").frame(width: 200, alignment: .leading)
                        Text("사용률")
                        Spacer()
                        Text("이번 달 지출").frame(width: 120, alignment: .trailing)
                    }
                    .font(T.overline).tracking(0.6).foregroundStyle(DF.helper)
                    .padding(.horizontal, 24).frame(height: 40)
                    .background(DF.background)
                    ForEach(Category.allCases) { c in
                        let spent = max(0, by[c] ?? 0)
                        let b = perCat[c] ?? 0
                        HStack(spacing: 0) {
                            HStack(spacing: 8) {
                                Circle().fill(DF.category(c)).frame(width: 8, height: 8)
                                Text(c.label).font(T.sans(14, 500)).foregroundStyle(DF.ink)
                            }
                            .frame(width: 150, alignment: .leading)
                            MoneyField(value: Binding(get: { perCat[c] ?? 0 }, set: { perCat[c] = $0 }))
                                .frame(width: 180).padding(.trailing, 20)
                            if b > 0 {
                                let r = Double(spent) / Double(b)
                                HStack(spacing: 10) {
                                    Bar(ratio: r, color: r > 1 ? DF.error : r > 0.85 ? DF.warning : DF.category(c), height: 6)
                                    Text("\(Int(r * 100))%").font(T.mono(12)).foregroundStyle(r > 1 ? DF.error : DF.helper).frame(width: 44, alignment: .trailing)
                                }
                            } else {
                                Text("예산 없음").font(T.sans(12)).foregroundStyle(DF.disabled)
                                Spacer()
                            }
                            Text(Money.won(spent)).font(T.sans(14, 600)).foregroundStyle(b > 0 && spent > b ? DF.error : DF.ink)
                                .frame(width: 120, alignment: .trailing)
                        }
                        .padding(.horizontal, 24).frame(height: 56)
                        Divider1()
                    }
                }
            }

            HStack {
                Spacer()
                if dirty { Text("저장하지 않은 변경이 있어요").font(T.sans(13)).foregroundStyle(DF.warning) }
                Button("되돌리기") { reset() }.dfButton(.ghost).disabled(!dirty)
                Button("예산 저장") {
                    store.updateSettings { s in
                        s.totalBudget = total
                        s.categoryBudgets = Dictionary(uniqueKeysWithValues: Category.allCases.compactMap { c in
                            (perCat[c] ?? 0) > 0 ? (c.rawValue, perCat[c] ?? 0) : nil
                        })
                    }
                    store.toast = "예산을 저장했어요."
                }
                .dfButton(.primary).disabled(!dirty)
            }
        }
        .onAppear { if !loaded { reset(); loaded = true } }
    }

    func reset() {
        total = store.ledger.settings.totalBudget
        perCat = Dictionary(uniqueKeysWithValues: Category.allCases.map { ($0, store.ledger.settings.budget($0)) })
    }
}
