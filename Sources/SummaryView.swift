import SwiftUI
import Charts

struct SummaryView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var state: AppState

    var body: some View {
        let l = store.ledger
        let m = state.month
        let today = DateUtil.todayString()
        let tot = Calc.totals(l.transactions, month: m)
        let bill = Calc.cardBill(l.transactions, month: m)
        let budget = l.settings.totalBudget

        PageScaffold(title: "월간 요약", subtitle: "\(DateUtil.monthTitle(m)) 1일 ~ \(DateUtil.daysIn(m))일 · 사용일 기준") {
            MonthSwitcher()
        } content: {
            Callout(kind: .info, title: "이번 달 한줄평", text: Calc.oneLiner(l, month: m), icon: "lightbulb.fill")

            HStack(spacing: 16) {
                StatCard(label: "총 입금", value: tot.income, tint: DF.success, note: "월급·입금 합계")
                StatCard(label: "총 지출", value: tot.expense, tint: DF.ink,
                         note: tot.refund > 0 ? "환불 \(Money.won(tot.refund)) 차감" : "카드대금·이체 제외")
                StatCard(label: "카드 청구 예상", value: bill, tint: DF.primary, note: "일시불 + 이번 달 할부 회차")
                if budget > 0 {
                    StatCard(label: "예산 잔액", value: budget - tot.expense, tint: budget - tot.expense < 0 ? DF.error : DF.ink,
                             note: "예산 \(Money.won(budget))", ratio: Double(tot.expense) / Double(budget))
                } else {
                    StatCard(label: "예산 잔액", value: nil, tint: DF.helper, note: "예산 관리에서 예산을 정해보세요")
                }
            }

            HStack(alignment: .top, spacing: 16) {
                CardBox {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionTitle(title: "누적 지출", subtitle: "이번 달과 지난달 같은 날짜까지 비교")
                        CumulativeChart(month: m, today: today)
                    }
                }
                .frame(maxWidth: .infinity)
                CardBox {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionTitle(title: "카테고리별 지출")
                        CategoryBreakdown(month: m)
                    }
                }
                .frame(width: 380)
            }

            HStack(alignment: .top, spacing: 16) {
                CardBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            SectionTitle(title: "최근 기록")
                            Spacer()
                            Button("전체 보기") { state.page = .transactions }.dfButton(.ghost, small: true)
                        }
                        let recent = Array(Calc.inMonth(l.transactions, m).prefix(7))
                        if recent.isEmpty {
                            EmptyState(icon: "tray", title: "기록이 없어요", text: "입금·지출에서 기록을 추가하거나\n카드 내역을 사진·PDF로 올려보세요.")
                        } else {
                            VStack(spacing: 0) {
                                ForEach(recent) { t in
                                    TxRow(tx: t, compact: true).onTapGesture { state.editing = t }
                                    if t.id != recent.last?.id { Divider1() }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                UpcomingCard(month: m, today: today).frame(width: 380)
            }
        }
    }
}

struct StatCard: View {
    var label: String
    var value: Int?
    var tint: Color
    var note: String
    var ratio: Double? = nil

    var body: some View {
        CardBox(padding: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Overline(label)
                if let v = value {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(v < 0 ? "−" + Money.plain(-v) : Money.plain(v)).font(T.number(26)).foregroundStyle(tint)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text("원").font(T.sans(14, 500)).foregroundStyle(DF.helper)
                    }
                } else {
                    Text("—").font(T.number(26)).foregroundStyle(DF.disabled)
                }
                if let r = ratio {
                    Bar(ratio: r, color: r > 1 ? DF.error : r > 0.85 ? DF.warning : DF.primary, height: 6)
                }
                Text(note).font(T.sans(12)).foregroundStyle(DF.helper).lineLimit(1)
            }
        }
    }
}

struct CumulativeChart: View {
    @EnvironmentObject var store: Store
    var month: String
    var today: String

    struct Point: Identifiable { var id: String { "\(series)-\(day)" }; var day: Int; var value: Int; var series: String }

    var body: some View {
        let txs = store.ledger.transactions
        let isCurrent = DateUtil.monthKey(today) == month
        let lastDay = isCurrent ? (Int(today.suffix(2)) ?? 1) : DateUtil.daysIn(month)
        let prev = DateUtil.addMonths(month, -1)
        let cur = Calc.cumulative(txs, month: month, upTo: lastDay)
        let prv = Calc.cumulative(txs, month: prev)
        let pts: [Point] = cur.enumerated().map { Point(day: $0.offset + 1, value: $0.element, series: "이번 달") }
            + prv.enumerated().map { Point(day: $0.offset + 1, value: $0.element, series: "지난달") }
        let prevSame = prv.isEmpty ? 0 : prv[min(lastDay, prv.count) - 1]
        let diff = (cur.last ?? 0) - prevSame

        VStack(alignment: .leading, spacing: 10) {
            Chart(pts) { p in
                LineMark(x: .value("일", p.day), y: .value("누적", p.value))
                    .foregroundStyle(by: .value("구분", p.series))
                    .lineStyle(StrokeStyle(lineWidth: p.series == "이번 달" ? 2.5 : 1.5, dash: p.series == "이번 달" ? [] : [4, 3]))
                    .interpolationMethod(.monotone)
            }
            .chartForegroundStyleScale(["이번 달": DF.primary, "지난달": DF.disabled])
            .chartXScale(domain: 1...31)
            .chartYAxis {
                AxisMarks(position: .leading) { v in
                    AxisGridLine().foregroundStyle(DF.line)
                    AxisValueLabel { if let n = v.as(Int.self) { Text(n >= 10_000 ? "\(n / 10_000)만" : "\(n)").font(T.mono(11)) } }
                }
            }
            .chartXAxis {
                AxisMarks(values: [1, 5, 10, 15, 20, 25, 30]) { v in
                    AxisValueLabel { if let n = v.as(Int.self) { Text("\(n)일").font(T.mono(11)) } }
                }
            }
            .chartLegend(position: .top, alignment: .trailing)
            .frame(height: 220)

            if (prv.last ?? 0) > 0 && (cur.last ?? 0) > 0 {
                Text(diff >= 0 ? "지난달 같은 날보다 \(Money.won(diff)) 더 썼어요." : "지난달 같은 날보다 \(Money.won(-diff)) 덜 썼어요.")
                    .font(T.sans(13)).foregroundStyle(diff > 0 ? DF.error : DF.success)
            }
        }
    }
}

struct CategoryBreakdown: View {
    @EnvironmentObject var store: Store
    var month: String
    var body: some View {
        let by = Calc.byCategory(store.ledger.transactions, month: month)
        let items = Category.allCases.map { ($0, max(0, by[$0] ?? 0)) }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
        let total = max(1, items.reduce(0) { $0 + $1.1 })
        if items.isEmpty {
            EmptyState(icon: "chart.pie", title: "아직 지출이 없어요", text: "지출을 기록하면 비중을 보여드려요.")
        } else {
            VStack(spacing: 14) {
                // 비중 막대
                GeometryReader { g in
                    HStack(spacing: 2) {
                        ForEach(items, id: \.0) { item in
                            Rectangle().fill(DF.category(item.0)).frame(width: max(2, g.size.width * CGFloat(item.1) / CGFloat(total) - 2))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .frame(height: 10)
                ForEach(items, id: \.0) { item in
                    let c = item.0, v = item.1
                    HStack(spacing: 10) {
                        Circle().fill(DF.category(c)).frame(width: 8, height: 8)
                        Text(c.label).font(T.sans(14)).foregroundStyle(DF.text)
                        Spacer()
                        Text("\(Int((Double(v) / Double(total) * 100).rounded()))%").font(T.mono(12)).foregroundStyle(DF.helper)
                        Text(Money.won(v)).font(T.sans(14, 600)).foregroundStyle(DF.ink).frame(minWidth: 96, alignment: .trailing)
                    }
                }
            }
        }
    }
}

struct UpcomingCard: View {
    @EnvironmentObject var store: Store
    var month: String
    var today: String
    var body: some View {
        let ups = Calc.upcoming(store.ledger, month: month, today: today)
        let daily = Calc.dailyBudget(store.ledger, month: month, today: today)
        CardBox {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: "예정된 돈의 흐름", subtitle: month == DateUtil.monthKey(today) ? "오늘 이후 이번 달" : nil)
                if let d = daily {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Overline("남은 기간 하루 예산")
                            Text(Money.won(d)).font(T.number(20)).foregroundStyle(DF.primary)
                        }
                        Spacer()
                        Text("고정지출 예정분 제외").font(T.caption).foregroundStyle(DF.helper)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(DF.primarySoft))
                }
                if ups.isEmpty {
                    Text(month < DateUtil.monthKey(today) ? "지난 달이에요." : "남은 예정이 없어요. 설정에서 월급·고정지출·카드 결제일을 등록하면 여기에 보여요.")
                        .font(T.sans(13)).foregroundStyle(DF.helper).fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: 0) {
                        ForEach(ups) { u in
                            HStack(spacing: 10) {
                                Text(DateUtil.shortDay(u.date)).font(T.mono(13)).foregroundStyle(DF.helper).frame(width: 44, alignment: .leading)
                                TypeBadge(type: u.kind)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(u.title).font(T.sans(14, 500)).foregroundStyle(DF.ink).lineLimit(1)
                                    Text(u.note).font(T.sans(11)).foregroundStyle(DF.helper)
                                }
                                Spacer()
                                Text(Money.won(u.amount)).font(T.sans(14, 600)).foregroundStyle(DF.amountColor(u.kind))
                            }
                            .frame(minHeight: 48)
                            if u.id != ups.last?.id { Divider1() }
                        }
                    }
                }
            }
        }
    }
}
