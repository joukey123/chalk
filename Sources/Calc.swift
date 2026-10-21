import Foundation

/// 금액 계산 규칙 (웹 버전과 같은 기준)
/// - 한 달 = 1일 ~ 말일, 사용일 기준
/// - 총 지출 = 지출 − 환불 (카드대금 납부·내 계좌 이체 제외)
/// - 카드 청구 예상 = 그 달 일시불 + 그 달 할부 회차 − 그 달 카드 환불
enum Calc {

    struct MonthTotals: Equatable {
        var income = 0
        var expense = 0     // 환불 차감 후
        var refund = 0
        var excluded = 0    // 카드대금·이체 (합계 제외)
    }

    static func inMonth(_ txs: [Transaction], _ month: String) -> [Transaction] {
        txs.filter { $0.month == month }
    }

    static func totals(_ txs: [Transaction], month: String) -> MonthTotals {
        var t = MonthTotals()
        for x in txs where x.month == month {
            switch x.type {
            case .income: t.income += x.amount
            case .expense: t.expense += x.amount
            case .refund: t.refund += x.amount
            case .transfer, .cardPayment: t.excluded += x.amount
            }
        }
        t.expense -= t.refund
        return t
    }

    /// 카테고리별 순지출 (지출 − 환불)
    static func byCategory(_ txs: [Transaction], month: String) -> [Category: Int] {
        var r: [Category: Int] = [:]
        for x in txs where x.month == month {
            if x.type == .expense { r[x.category, default: 0] += x.amount }
            if x.type == .refund { r[x.category, default: 0] -= x.amount }
        }
        return r
    }

    // MARK: 할부

    /// i번째 회차(0부터) 금액. 나누어떨어지지 않는 원 단위는 마지막 회차에.
    static func installmentPortion(amount: Int, count: Int, index: Int) -> Int {
        let n = max(1, count)
        guard index >= 0, index < n else { return 0 }
        let base = amount / n
        return index == n - 1 ? amount - base * (n - 1) : base
    }

    /// 이 거래가 해당 월 카드 청구에 더하는 금액
    static func billPortion(_ x: Transaction, month: String) -> Int {
        guard x.method == .card else { return 0 }
        switch x.type {
        case .expense:
            let idx = DateUtil.monthDiff(x.month, month)
            return installmentPortion(amount: x.amount, count: x.installments, index: idx)
        case .refund:
            return x.month == month ? -x.amount : 0
        default:
            return 0
        }
    }

    /// cardId == nil 이면 모든 카드. unassigned == true 면 카드 미지정만.
    static func cardBill(_ txs: [Transaction], month: String, cardId: String? = nil, unassigned: Bool = false) -> Int {
        txs.reduce(0) { sum, x in
            if unassigned { if x.cardId != nil { return sum } }
            else if let c = cardId, x.cardId != c { return sum }
            return sum + billPortion(x, month: month)
        }
    }

    /// 해당 월 이후에 남은 할부금
    static func remainingInstallments(_ txs: [Transaction], after month: String, cardId: String? = nil) -> Int {
        var sum = 0
        for x in txs where x.type == .expense && x.method == .card && x.installments > 1 {
            if let c = cardId, x.cardId != c { continue }
            let done = DateUtil.monthDiff(x.month, month) // 이번 달까지 진행한 회차 index
            guard done >= 0 else { sum += x.amount; continue } // 아직 시작 전(미래 구매)
            for i in (done + 1)..<max(done + 1, x.installments) { sum += installmentPortion(amount: x.amount, count: x.installments, index: i) }
        }
        return sum
    }

    /// 사용 월의 카드값이 빠져나가는 날 (다음 달 결제일, 말일 보정)
    static func paymentDate(card: Card, usageMonth: String) -> String {
        DateUtil.clampedDay(DateUtil.addMonths(usageMonth, 1), card.payDay)
    }

    // MARK: 자동 기록 (월급·고정지출)

    static func salaryKey(_ month: String) -> String { "salary:\(month)" }
    static func fixedKey(_ id: String, _ month: String) -> String { "fixed:\(id):\(month)" }

    /// 오늘까지 지난 예정일 중 아직 없는 회차를 만든다. 삭제한 회차는 다시 만들지 않는다.
    static func pendingAutoRecords(_ ledger: Ledger, today: String) -> [Transaction] {
        let existing = Set(ledger.transactions.compactMap { $0.autoKey })
        let skipped = Set(ledger.skippedAutoKeys)
        let thisMonth = DateUtil.monthKey(today)
        var out: [Transaction] = []

        func months(from start: String) -> [String] {
            guard DateUtil.isValidMonth(start) else { return [] }
            var first = start
            if DateUtil.monthDiff(first, thisMonth) > 120 { first = DateUtil.addMonths(thisMonth, -120) }
            let n = DateUtil.monthDiff(first, thisMonth)
            guard n >= 0 else { return [] }
            return (0...n).map { DateUtil.addMonths(first, $0) }
        }

        let s = ledger.settings.salary
        if s.enabled && s.amount > 0 {
            for m in months(from: s.startMonth) {
                let key = salaryKey(m), day = DateUtil.clampedDay(m, s.day)
                guard day <= today, !existing.contains(key), !skipped.contains(key) else { continue }
                out.append(Transaction(date: day, type: .income, title: s.title.isEmpty ? "월급" : s.title,
                                       amount: s.amount, category: .etc, method: .account, autoKey: key))
            }
        }
        for f in ledger.settings.fixed where f.active && f.amount > 0 {
            for m in months(from: f.startMonth) {
                let key = fixedKey(f.id, m), day = DateUtil.clampedDay(m, f.day)
                guard day <= today, !existing.contains(key), !skipped.contains(key) else { continue }
                out.append(Transaction(date: day, type: .expense, title: f.name, amount: f.amount,
                                       category: f.category, method: f.method,
                                       cardId: f.method == .card ? f.cardId : nil, autoKey: key))
            }
        }
        return out
    }

    struct Upcoming: Identifiable {
        var id: String
        var date: String
        var title: String
        var amount: Int
        var kind: TxType
        var note: String
    }

    /// 이번 달 남은 예정 (월급, 고정지출, 카드 결제일)
    static func upcoming(_ ledger: Ledger, month: String, today: String) -> [Upcoming] {
        var r: [Upcoming] = []
        let st = ledger.settings
        let existing = Set(ledger.transactions.compactMap { $0.autoKey })
        if st.salary.enabled && st.salary.amount > 0 && DateUtil.monthDiff(st.salary.startMonth, month) >= 0 {
            let d = DateUtil.clampedDay(month, st.salary.day)
            if d > today && !existing.contains(salaryKey(month)) {
                r.append(Upcoming(id: "s" + month, date: d, title: st.salary.title, amount: st.salary.amount, kind: .income, note: "월급 자동 기입 예정"))
            }
        }
        for f in st.fixed where f.active && DateUtil.monthDiff(f.startMonth, month) >= 0 {
            let d = DateUtil.clampedDay(month, f.day)
            if d > today && !existing.contains(fixedKey(f.id, month)) {
                r.append(Upcoming(id: "f" + f.id, date: d, title: f.name, amount: f.amount, kind: .expense, note: "고정지출 예정"))
            }
        }
        for c in st.cards {
            let d = DateUtil.clampedDay(month, c.payDay)
            let bill = cardBill(ledger.transactions, month: DateUtil.addMonths(month, -1), cardId: c.id)
            if d > today && bill > 0 {
                r.append(Upcoming(id: "c" + c.id, date: d, title: "\(c.name) 결제", amount: bill, kind: .cardPayment, note: "지난달 사용분 (합계 제외)"))
            }
        }
        return r.sorted { $0.date < $1.date }
    }

    /// 남은 기간 하루 예산 (오늘 포함). 이번 달이 아니거나 예산이 없으면 nil
    static func dailyBudget(_ ledger: Ledger, month: String, today: String) -> Int? {
        guard ledger.settings.totalBudget > 0, DateUtil.monthKey(today) == month else { return nil }
        let spent = totals(ledger.transactions, month: month).expense
        let fixedLeft = upcoming(ledger, month: month, today: today).filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount }
        let day = Int(today.suffix(2)) ?? 1
        let daysLeft = DateUtil.daysIn(month) - day + 1
        return max(0, (ledger.settings.totalBudget - spent - fixedLeft) / max(1, daysLeft))
    }

    /// 1일부터 날짜별 누적 지출 (환불 차감)
    static func cumulative(_ txs: [Transaction], month: String, upTo lastDay: Int? = nil) -> [Int] {
        let n = lastDay ?? DateUtil.daysIn(month)
        var daily = Array(repeating: 0, count: DateUtil.daysIn(month) + 1)
        for x in txs where x.month == month {
            guard let d = Int(x.date.suffix(2)), d < daily.count else { continue }
            if x.type == .expense { daily[d] += x.amount }
            if x.type == .refund { daily[d] -= x.amount }
        }
        var acc = 0, out: [Int] = []
        for d in 1...max(1, n) { acc += daily[min(d, daily.count - 1)]; out.append(acc) }
        return out
    }

    // MARK: 한줄평 (규칙 기반, 외부 전송 없음)

    static func oneLiner(_ ledger: Ledger, month: String) -> String {
        let txs = ledger.transactions
        let st = ledger.settings
        let cur = byCategory(txs, month: month)
        let total = totals(txs, month: month).expense
        let expenseCount = txs.filter { $0.month == month && $0.type == .expense }.count
        guard expenseCount > 0, total > 0 else {
            return "아직 이번 달 지출 기록이 없어요. 카드 내역을 사진이나 PDF로 올려 기록을 시작해보세요."
        }

        // 1) 예산 초과 카테고리
        let over = Category.allCases.compactMap { c -> (Category, Int)? in
            let b = st.budget(c); let v = cur[c] ?? 0
            return b > 0 && v > b ? (c, v - b) : nil
        }.sorted { $0.1 > $1.1 }
        if let (c, amt) = over.first {
            return "\(c.label) 지출이 예산보다 \(Money.won(amt)) 많아요. 남은 기간 \(c.label)을 줄이면 예산 안으로 돌아올 수 있어요."
        }
        if st.totalBudget > 0 && total > st.totalBudget {
            return "이번 달 지출이 전체 예산보다 \(Money.won(total - st.totalBudget)) 많아요. 큰 항목부터 다시 확인해보세요."
        }

        // 2) 지난달보다 늘어난 카테고리 (기록이 있을 때만)
        let prevMonth = DateUtil.addMonths(month, -1)
        let prevCount = txs.filter { $0.month == prevMonth && $0.type == .expense }.count
        if prevCount >= 3 {
            let prev = byCategory(txs, month: prevMonth)
            let rise = Category.allCases.map { ($0, (cur[$0] ?? 0) - (prev[$0] ?? 0)) }
                .filter { $0.1 >= 30_000 }.sorted { $0.1 > $1.1 }
            if let (c, d) = rise.first {
                return "\(c.label) 지출이 지난달보다 \(Money.won(d)) 늘었어요. 지난달 수준으로 맞추면 그만큼 아낄 수 있어요."
            }
        }

        // 3) 줄이기 쉬운 항목 10% 예시
        let flexible: [Category] = [.food, .shopping, .cafe, .culture]
        if let (c, v) = flexible.map({ ($0, cur[$0] ?? 0) }).max(by: { $0.1 < $1.1 }), v >= 10_000 {
            let save = (v / 10 / 100) * 100
            let pct = Int((Double(v) / Double(total) * 100).rounded())
            return "\(c.label)가 지출의 \(pct)%예요. 10%만 줄여도 이번 달 약 \(Money.won(save))을 아낄 수 있어요."
        }
        if expenseCount < 5 {
            return "기록이 아직 적어서 소비 습관을 판단하기 일러요. 몇 건 더 기록하면 절약 포인트를 알려드릴게요."
        }
        return "고정비 외에 크게 늘어난 항목은 없어요. 지금 흐름을 유지해보세요."
    }

    // MARK: 중복·분류

    static func normalize(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func isDuplicate(_ c: Transaction, in txs: [Transaction]) -> Bool {
        let n = normalize(c.title)
        return txs.contains { x in
            guard x.date == c.date, x.amount == c.amount, x.type == c.type else { return false }
            let m = normalize(x.title)
            return n.isEmpty || m.isEmpty || n == m || n.contains(m) || m.contains(n)
        }
    }

    static let keywordMap: [(Category, [String])] = [
        (.cafe, ["스타벅스", "커피", "카페", "이디야", "투썸", "메가", "빽다방", "컴포즈", "할리스", "폴바셋", "베이커리", "파리바게", "뚜레쥬르", "던킨", "배스킨", "편의점", "gs25", "cu", "세븐일레븐", "이마트24", "cafe", "coffee"]),
        (.food, ["배달의민족", "배민", "요기요", "쿠팡이츠", "식당", "치킨", "피자", "버거", "맥도날드", "롯데리아", "김밥", "국밥", "분식", "고기", "초밥", "마라", "푸드", "레스토랑", "식품", "마트", "이마트", "홈플러스", "롯데마트", "농협", "하나로"]),
        (.transport, ["택시", "카카오t", "카카오모빌리티", "버스", "지하철", "코레일", "ktx", "srt", "티머니", "주유", "주차", "오일", "sk에너지", "gs칼텍스", "s-oil", "에쓰오일", "하이패스", "고속도로", "항공"]),
        (.housing, ["관리비", "월세", "통신", "skt", "kt", "lg유플러스", "u+", "전기", "가스", "수도", "인터넷"]),
        (.health, ["병원", "의원", "약국", "치과", "한의원", "헬스", "필라테스", "요가", "피트니스", "안과", "정형외과", "내과"]),
        (.culture, ["넷플릭스", "netflix", "유튜브", "youtube", "멜론", "스포티파이", "spotify", "왓챠", "티빙", "웨이브", "디즈니", "cgv", "메가박스", "롯데시네마", "교보", "yes24", "알라딘", "애플", "apple", "구글", "google", "chatgpt", "openai", "claude", "anthropic", "게임", "steam", "구독"]),
        (.shopping, ["쿠팡", "coupang", "11번가", "g마켓", "옥션", "무신사", "지그재그", "올리브영", "다이소", "네이버페이", "스마트스토어", "ssg", "29cm", "에이블리", "아마존", "amazon", "알리", "테무", "백화점", "아울렛", "유니클로", "자라"]),
    ]

    static func guessCategory(_ title: String, rules: [String: String]) -> Category {
        let n = normalize(title)
        if let raw = rules[n], let c = Category(rawValue: raw) { return c }
        let low = title.lowercased().replacingOccurrences(of: " ", with: "")
        for (cat, words) in keywordMap where words.contains(where: { low.contains($0) }) { return cat }
        return .etc
    }
}
