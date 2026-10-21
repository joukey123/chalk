import Foundation

/// "예시로 둘러보기"에서 쓰는 가상의 기록. 파일에 저장하지 않는다.
enum SampleData {
    static func make(today: String = DateUtil.todayString()) -> Ledger {
        var l = Ledger()
        let card1 = Card(id: "demo-card-1", name: "신한 Deep Dream", payDay: 14)
        let card2 = Card(id: "demo-card-2", name: "현대 M", payDay: 25)
        l.settings.cards = [card1, card2]
        let thisMonth = DateUtil.monthKey(today)
        let prev = DateUtil.addMonths(thisMonth, -1)
        l.settings.salary = SalarySetting(enabled: true, title: "월급", amount: 3_200_000, day: 25, startMonth: prev)
        l.settings.fixed = [
            FixedExpense(id: "demo-fx-1", name: "월세", amount: 550_000, day: 5, category: .housing, method: .account, startMonth: prev),
            FixedExpense(id: "demo-fx-2", name: "휴대폰 요금", amount: 59_000, day: 20, category: .housing, method: .card, cardId: card1.id, startMonth: prev),
            FixedExpense(id: "demo-fx-3", name: "넷플릭스", amount: 17_000, day: 28, category: .culture, method: .card, cardId: card2.id, startMonth: prev),
        ]
        l.settings.totalBudget = 1_800_000
        l.settings.categoryBudgets = [Category.food.rawValue: 400_000, Category.shopping.rawValue: 250_000,
                                      Category.cafe.rawValue: 80_000, Category.transport.rawValue: 120_000,
                                      Category.culture.rawValue: 60_000]

        let todayDay = Int(today.suffix(2)) ?? 15
        func d(_ m: String, _ day: Int) -> String { DateUtil.clampedDay(m, day) }
        func add(_ m: String, _ day: Int, _ title: String, _ amt: Int, _ c: Category, card: Card? = card1,
                 type: TxType = .expense, inst: Int = 1, method: PayMethod = .card) {
            if m == thisMonth && day > todayDay { return }
            l.transactions.append(Transaction(id: "demo-\(l.transactions.count)", date: d(m, day), type: type, title: title,
                                              amount: amt, category: c, method: method, cardId: method == .card ? card?.id : nil,
                                              installments: inst))
        }
        for m in [prev, thisMonth] {
            let p = m == prev
            add(m, 2, "스타벅스 역삼점", 6_300, .cafe)
            add(m, 3, "배달의민족", p ? 23_500 : 31_000, .food)
            add(m, 4, "카카오T 택시", 12_800, .transport, card: card2)
            add(m, 6, "쿠팡", p ? 48_900 : 89_000, .shopping)
            add(m, 8, "이마트 성수점", 76_400, .food, card: card2)
            add(m, 9, "메가커피", 3_200, .cafe)
            add(m, 11, "올리브영", 32_000, .shopping, card: card2)
            add(m, 12, "배달의민족", 27_900, .food)
            add(m, 14, "\(card1.name) 대금", 412_000, .etc, type: .cardPayment, method: .account)
            add(m, 15, "약국", 8_500, .health)
            add(m, 17, "요기요", p ? 19_000 : 34_500, .food)
            add(m, 19, "CGV 용산", 30_000, .culture, card: card2)
            add(m, 21, "티머니 충전", 50_000, .transport)
            add(m, 23, "투썸플레이스", p ? 9_800 : 15_600, .cafe)
            add(m, 26, "적금 계좌로 이체", 500_000, .etc, type: .transfer, method: .account)
            add(m, 27, "무신사", 129_000, .shopping, card: card2)
        }
        add(thisMonth, 7, "애플스토어 (아이패드)", 899_000, .shopping, inst: 6)
        add(thisMonth, 10, "쿠팡 반품 환불", 18_000, .shopping, type: .refund)
        l.settingsUpdatedAt = 1
        // 월급·고정지출 자동 기록
        l.transactions += Calc.pendingAutoRecords(l, today: today)
        l.transactions = Sync.sortTx(l.transactions)
        return l
    }
}
