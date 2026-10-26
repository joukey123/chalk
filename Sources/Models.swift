import Foundation

// MARK: - 기본 분류

enum TxType: String, Codable, CaseIterable, Identifiable {
    case expense, income, refund, transfer, cardPayment
    var id: String { rawValue }
    var label: String {
        switch self {
        case .expense: return "지출"
        case .income: return "입금"
        case .refund: return "환불"
        case .transfer: return "내 계좌 이체"
        case .cardPayment: return "카드대금 납부"
        }
    }
    /// 배지에 쓰는 짧은 이름
    var badge: String {
        switch self {
        case .expense: return "지출"
        case .income: return "입금"
        case .refund: return "환불"
        case .transfer: return "이체"
        case .cardPayment: return "카드납부"
        }
    }
    init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        self = TxType(rawValue: s) ?? .expense
    }
}

enum PayMethod: String, Codable, CaseIterable, Identifiable {
    case card, account, cash
    var id: String { rawValue }
    var label: String {
        switch self {
        case .card: return "카드"
        case .account: return "계좌"
        case .cash: return "현금"
        }
    }
    init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        self = PayMethod(rawValue: s) ?? .card
    }
}

enum Category: String, Codable, CaseIterable, Identifiable {
    case food, shopping, cafe, transport, housing, health, culture, etc
    var id: String { rawValue }
    var label: String {
        switch self {
        case .food: return "음식·배달"
        case .shopping: return "쇼핑"
        case .cafe: return "카페·간식"
        case .transport: return "교통"
        case .housing: return "주거·통신"
        case .health: return "건강"
        case .culture: return "문화·구독"
        case .etc: return "기타"
        }
    }
    init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        self = Category(rawValue: s) ?? Category.fromLabel(s) ?? .etc
    }
    static func fromLabel(_ s: String) -> Category? {
        let t = s.replacingOccurrences(of: " ", with: "")
        return Category.allCases.first { $0.label == t || $0.label.replacingOccurrences(of: "·", with: "/") == t }
    }
}

// MARK: - 거래

struct Transaction: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var date: String              // yyyy-MM-dd (사용일)
    var type: TxType = .expense
    var title: String = ""
    var amount: Int = 0           // 원, 항상 양수
    var category: Category = .etc
    var method: PayMethod = .card
    var cardId: String? = nil
    var installments: Int = 1     // 1 = 일시불
    var memo: String = ""
    var autoKey: String? = nil    // 자동 기록 회차 (salary:2026-10, fixed:<id>:2026-10)
    var updatedAt: Double = Date().timeIntervalSince1970

    init(id: String = UUID().uuidString, date: String, type: TxType = .expense, title: String = "",
         amount: Int = 0, category: Category = .etc, method: PayMethod = .card, cardId: String? = nil,
         installments: Int = 1, memo: String = "", autoKey: String? = nil) {
        self.id = id; self.date = date; self.type = type; self.title = title; self.amount = amount
        self.category = category; self.method = method; self.cardId = cardId
        self.installments = installments; self.memo = memo; self.autoKey = autoKey
        self.updatedAt = Date().timeIntervalSince1970
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        date = try c.decode(String.self, forKey: .date)
        type = (try? c.decode(TxType.self, forKey: .type)) ?? .expense
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        amount = (try? c.decode(Int.self, forKey: .amount)) ?? 0
        category = (try? c.decode(Category.self, forKey: .category)) ?? .etc
        method = (try? c.decode(PayMethod.self, forKey: .method)) ?? .card
        cardId = try? c.decodeIfPresent(String.self, forKey: .cardId)
        installments = max(1, (try? c.decode(Int.self, forKey: .installments)) ?? 1)
        memo = (try? c.decode(String.self, forKey: .memo)) ?? ""
        autoKey = try? c.decodeIfPresent(String.self, forKey: .autoKey)
        updatedAt = (try? c.decode(Double.self, forKey: .updatedAt)) ?? 0
    }

    mutating func touch() { updatedAt = Date().timeIntervalSince1970 }
    var month: String { String(date.prefix(7)) }
}

// MARK: - 설정

struct Card: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var payDay: Int  // 다음 달 결제일
}

struct FixedExpense: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var amount: Int
    var day: Int
    var category: Category = .housing
    var method: PayMethod = .account
    var cardId: String? = nil
    var startMonth: String   // yyyy-MM
    var active: Bool = true
}

struct SalarySetting: Codable, Hashable {
    var enabled: Bool = false
    var title: String = "월급"
    var amount: Int = 0
    var day: Int = 25
    var startMonth: String = DateUtil.monthKey(DateUtil.todayString())
}

struct Settings: Codable, Hashable {
    var salary = SalarySetting()
    var cards: [Card] = []
    var fixed: [FixedExpense] = []
    var totalBudget: Int = 0
    var categoryBudgets: [String: Int] = [:]   // Category.rawValue -> 원
    var merchantRules: [String: String] = [:]  // 정규화한 상호명 -> Category.rawValue

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        salary = (try? c.decode(SalarySetting.self, forKey: .salary)) ?? SalarySetting()
        cards = (try? c.decode([Card].self, forKey: .cards)) ?? []
        fixed = (try? c.decode([FixedExpense].self, forKey: .fixed)) ?? []
        totalBudget = (try? c.decode(Int.self, forKey: .totalBudget)) ?? 0
        categoryBudgets = (try? c.decode([String: Int].self, forKey: .categoryBudgets)) ?? [:]
        merchantRules = (try? c.decode([String: String].self, forKey: .merchantRules)) ?? [:]
    }
    func budget(_ cat: Category) -> Int { categoryBudgets[cat.rawValue] ?? 0 }
}

// MARK: - 가계부 파일 전체

struct Ledger: Codable {
    var format: String = "chagok-ledger"
    var version: Int = 1
    var transactions: [Transaction] = []
    var deleted: [String: Double] = [:]      // 삭제한 거래 id -> 삭제 시각 (다른 기기와 합칠 때 사용)
    var skippedAutoKeys: [String] = []       // 삭제한 자동 기록 회차는 다시 만들지 않음
    var settings = Settings()
    var settingsUpdatedAt: Double = 0
    var savedAt: Double = 0
    var savedBy: String = ""

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = (try? c.decode(String.self, forKey: .format)) ?? ""
        guard format == "chagok-ledger" else {
            throw NSError(domain: "Chagok", code: 1, userInfo: [NSLocalizedDescriptionKey: "Chack! 가계부 파일이 아니에요."])
        }
        version = (try? c.decode(Int.self, forKey: .version)) ?? 1
        transactions = try c.decode([Transaction].self, forKey: .transactions)
        deleted = (try? c.decode([String: Double].self, forKey: .deleted)) ?? [:]
        skippedAutoKeys = (try? c.decode([String].self, forKey: .skippedAutoKeys)) ?? []
        settings = (try? c.decode(Settings.self, forKey: .settings)) ?? Settings()
        settingsUpdatedAt = (try? c.decode(Double.self, forKey: .settingsUpdatedAt)) ?? 0
        savedAt = (try? c.decode(Double.self, forKey: .savedAt)) ?? 0
        savedBy = (try? c.decode(String.self, forKey: .savedBy)) ?? ""
    }

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }
}

// MARK: - 날짜 도구 (한국 시간 기준, 문자열 yyyy-MM-dd)

enum DateUtil {
    static let tz = TimeZone(identifier: "Asia/Seoul")!
    static var cal: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = tz; return c
    }()
    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = cal; f.timeZone = tz; f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"; return f
    }()

    static func todayString(_ now: Date = Date()) -> String { dayFormatter.string(from: now) }
    static func date(_ s: String) -> Date? { isValid(s) ? dayFormatter.date(from: s) : nil }
    static func string(_ d: Date) -> String { dayFormatter.string(from: d) }
    static func monthKey(_ day: String) -> String { String(day.prefix(7)) }

    static func parts(_ month: String) -> (Int, Int) {
        let p = month.split(separator: "-").compactMap { Int($0) }
        return (p.count > 0 ? p[0] : 2000, p.count > 1 ? p[1] : 1)
    }
    static func monthString(_ y: Int, _ m: Int) -> String { String(format: "%04d-%02d", y, m) }

    static func addMonths(_ month: String, _ n: Int) -> String {
        let (y, m) = parts(month)
        let total = y * 12 + (m - 1) + n
        return monthString(total / 12, total % 12 + 1)
    }
    /// a에서 b까지 몇 개월 차이인지 (b - a)
    static func monthDiff(_ a: String, _ b: String) -> Int {
        let (y1, m1) = parts(a), (y2, m2) = parts(b)
        return (y2 * 12 + m2) - (y1 * 12 + m1)
    }
    static func isLeap(_ y: Int) -> Bool { (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 }
    static func daysIn(_ month: String) -> Int {
        let (y, m) = parts(month)
        switch m {
        case 2: return isLeap(y) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }
    /// 말일보다 큰 날짜는 말일로 맞춤
    static func clampedDay(_ month: String, _ day: Int) -> String {
        let d = min(max(day, 1), daysIn(month))
        return month + String(format: "-%02d", d)
    }
    static func isValid(_ s: String) -> Bool {
        let p = s.split(separator: "-")
        guard s.count == 10, p.count == 3, let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]),
              (1900...2100).contains(y), (1...12).contains(m) else { return false }
        return d >= 1 && d <= daysIn(monthString(y, m))
    }
    static func isValidMonth(_ s: String) -> Bool { isValid(s + "-01") }

    static func monthTitle(_ month: String) -> String {
        let (y, m) = parts(month); return "\(y)년 \(m)월"
    }
    static func shortDay(_ day: String) -> String {
        let p = day.split(separator: "-")
        guard p.count == 3 else { return day }
        return "\(p[1]).\(p[2])"
    }
    static func weekday(_ day: String) -> String {
        guard let d = date(day) else { return "" }
        return ["일", "월", "화", "수", "목", "금", "토"][cal.component(.weekday, from: d) - 1]
    }
}

enum Money {
    static let f: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.locale = Locale(identifier: "ko_KR"); return f
    }()
    static func won(_ v: Int) -> String { (f.string(from: NSNumber(value: v)) ?? "\(v)") + "원" }
    static func plain(_ v: Int) -> String { f.string(from: NSNumber(value: v)) ?? "\(v)" }
    static func signed(_ v: Int) -> String { (v > 0 ? "+" : v < 0 ? "−" : "") + won(abs(v)) }
    /// "12,300원", "12300" 같은 입력을 정수로
    static func parse(_ s: String) -> Int? {
        let digits = s.filter { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 12 else { return nil }
        return Int(digits)
    }
}
