import Foundation

// 계산 규칙 검사. GitHub(macOS)에서 빌드할 때마다 실행돼요.
// swiftc Sources/Models.swift Sources/Calc.swift Sources/Sync.swift Sources/Parser.swift Sources/SampleData.swift Tests/main.swift

var failures = 0
var passed = 0
func check(_ cond: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
    if cond { passed += 1 } else { failures += 1; print("❌ \(name) \(detail())") }
}

func tx(_ date: String, _ type: TxType = .expense, _ amount: Int, cat: Category = .food, method: PayMethod = .card,
        card: String? = "c1", inst: Int = 1, title: String = "가게") -> Transaction {
    Transaction(date: date, type: type, title: title, amount: amount, category: cat, method: method,
                cardId: method == .card ? card : nil, installments: inst)
}

// 날짜
check(DateUtil.daysIn("2024-02") == 29, "윤년 2월")
check(DateUtil.daysIn("2026-02") == 28, "평년 2월")
check(DateUtil.daysIn("2100-02") == 28, "2100년은 평년")
check(DateUtil.clampedDay("2026-02", 31) == "2026-02-28", "말일 보정")
check(DateUtil.clampedDay("2024-02", 30) == "2024-02-29", "윤년 말일 보정")
check(DateUtil.addMonths("2026-11", 3) == "2027-02", "월 더하기")
check(DateUtil.addMonths("2026-01", -1) == "2025-12", "월 빼기")
check(DateUtil.monthDiff("2026-10", "2027-01") == 3, "월 차이")
check(!DateUtil.isValid("2026-02-30"), "없는 날짜 거부")
check(DateUtil.isValid("2024-02-29"), "윤일 허용")

// 합계
let txs = [
    tx("2026-10-01", .income, 3_000_000, method: .account),
    tx("2026-10-02", .expense, 10_000),
    tx("2026-10-03", .expense, 20_000, cat: .shopping),
    tx("2026-10-04", .refund, 5_000, cat: .shopping),
    tx("2026-10-14", .cardPayment, 400_000, method: .account),
    tx("2026-10-20", .transfer, 500_000, method: .account),
    tx("2026-09-30", .expense, 99_999),
    tx("2026-11-01", .expense, 77_777),
]
let t = Calc.totals(txs, month: "2026-10")
check(t.income == 3_000_000, "총 입금", "\(t.income)")
check(t.expense == 25_000, "총 지출 = 지출 − 환불, 카드대금·이체 제외", "\(t.expense)")
check(t.excluded == 900_000, "합계 제외 금액", "\(t.excluded)")
check(Calc.byCategory(txs, month: "2026-10")[.shopping] == 15_000, "카테고리 환불 차감")

// 할부
check(Calc.installmentPortion(amount: 100_000, count: 3, index: 0) == 33_333, "할부 1회차")
check(Calc.installmentPortion(amount: 100_000, count: 3, index: 2) == 33_334, "원 단위 차이는 마지막 회차")
check((0..<3).reduce(0) { $0 + Calc.installmentPortion(amount: 100_000, count: 3, index: $1) } == 100_000, "할부 합계 일치")
let inst = [tx("2026-10-07", .expense, 900_000, inst: 6), tx("2026-10-08", .expense, 50_000), tx("2026-10-09", .refund, 10_000)]
check(Calc.totals(inst, month: "2026-10").expense == 940_000, "할부 총액은 구매한 달 지출")
check(Calc.cardBill(inst, month: "2026-10") == 150_000 + 50_000 - 10_000, "청구 예상 = 일시불 + 할부 회차 − 환불", "\(Calc.cardBill(inst, month: "2026-10"))")
check(Calc.cardBill(inst, month: "2026-11") == 150_000, "다음 달 청구는 할부 회차만")
check(Calc.cardBill(inst, month: "2027-04") == 0, "할부 끝난 뒤 0")
check(Calc.remainingInstallments(inst, after: "2026-10") == 750_000, "남은 할부금", "\(Calc.remainingInstallments(inst, after: "2026-10"))")
check(Calc.remainingInstallments(inst, after: "2027-03") == 0, "마지막 회차 뒤 남은 할부 0")
check(Calc.cardBill(inst, month: "2026-10", cardId: "other") == 0, "다른 카드 제외")
check(Calc.paymentDate(card: Card(name: "A", payDay: 31), usageMonth: "2026-01") == "2026-02-28", "결제일 말일 보정")

// 자동 기록
var l = Ledger()
l.settings.salary = SalarySetting(enabled: true, title: "월급", amount: 3_000_000, day: 31, startMonth: "2024-01")
l.settings.fixed = [FixedExpense(id: "f1", name: "월세", amount: 500_000, day: 5, category: .housing, method: .account, startMonth: "2024-02")]
let auto1 = Calc.pendingAutoRecords(l, today: "2024-03-15")
check(auto1.filter { $0.type == .income }.map(\.date) == ["2024-01-31", "2024-02-29"], "월급: 지난 회차만, 윤년 말일", "\(auto1.map(\.date))")
check(auto1.filter { $0.type == .expense }.map(\.date) == ["2024-02-05", "2024-03-05"], "고정지출 회차", "\(auto1.map(\.date))")
l.transactions = auto1
check(Calc.pendingAutoRecords(l, today: "2024-03-15").isEmpty, "같은 회차 중복 생성 안 함")
l.transactions.removeAll { $0.autoKey == "salary:2024-02" }
l.skippedAutoKeys = ["salary:2024-02"]
check(Calc.pendingAutoRecords(l, today: "2024-03-15").isEmpty, "삭제한 자동 기록은 다시 만들지 않음")
check(Calc.pendingAutoRecords(l, today: "2024-03-31").map(\.autoKey) == ["salary:2024-03"], "월급날 당일 기록")

// 합치기 (맥과 아이폰이 같은 파일을 쓸 때)
var a = Ledger(), b = Ledger()
var x1 = tx("2026-10-01", .expense, 1000, title: "A"); x1.id = "x1"; x1.updatedAt = 100
var x1b = x1; x1b.amount = 2000; x1b.updatedAt = 200
var x2 = tx("2026-10-02", .expense, 3000, title: "B"); x2.id = "x2"; x2.updatedAt = 100
var x3 = tx("2026-10-03", .expense, 4000, title: "C"); x3.id = "x3"; x3.updatedAt = 100
a.transactions = [x1, x2]
b.transactions = [x1b, x3]
b.deleted = ["x2": 150]
let now = Date().timeIntervalSince1970
a.deleted = [:]
let merged = Sync.merge(a, b)
check(merged.transactions.first { $0.id == "x1" }?.amount == 2000, "나중에 고친 쪽이 남음")
check(!merged.transactions.contains { $0.id == "x2" }, "다른 기기에서 지운 기록 반영")
check(merged.transactions.contains { $0.id == "x3" }, "다른 기기에서 추가한 기록 반영")
var s1 = tx("2026-10-25", .income, 10, method: .account); s1.autoKey = "salary:2026-10"; s1.id = "aaa"; s1.updatedAt = now
var s2 = s1; s2.id = "bbb"
a.transactions = [s1]; b.transactions = [s2]; b.deleted = [:]
check(Sync.merge(a, b).transactions.filter { $0.autoKey == "salary:2026-10" }.count == 1, "두 기기의 같은 자동 기록은 하나로")
a.settings.totalBudget = 1; a.settingsUpdatedAt = 10
b.settings.totalBudget = 2; b.settingsUpdatedAt = 20
check(Sync.merge(a, b).settings.totalBudget == 2, "설정은 나중에 바꾼 쪽")

// 파일 형식
let enc = try! Ledger.encoder().encode(SampleData.make(today: "2026-10-21"))
let dec = try! JSONDecoder().decode(Ledger.self, from: enc)
check(dec.transactions.count == SampleData.make(today: "2026-10-21").transactions.count, "저장 후 다시 읽기")
check((try? JSONDecoder().decode(Ledger.self, from: Data("{\"a\":1}".utf8))) == nil, "다른 형식 파일 거부")
let web = """
{"version":1,"transactions":[{"id":"w1","date":"2026-10-03","type":"expense","merchant":"스타벅스","amount":5600,"category":"cafe","method":"card","installments":1},
{"id":"w2","date":"2026-10-25","type":"income","merchant":"월급","amount":3000000,"category":"etc","method":"account"},
{"id":"w3","date":"bad","type":"expense","merchant":"x","amount":1}]}
"""
let wi = WebImport.parse(Data(web.utf8))
check(wi?.ledger.transactions.count == 2, "웹 백업 읽기 (잘못된 날짜 제외)", "\(String(describing: wi?.ledger.transactions.count))")
check(wi?.ledger.transactions.first { $0.id == "w1" }?.category == .cafe, "웹 백업 카테고리")

// 글자 인식 결과 해석
let today = "2026-10-21"
let p1 = Parser.parse(lines: [
    "이용일자  가맹점명  이용금액",
    "2026.10.03  스타벅스 역삼점  6,300",
    "10/05 쿠팡 (3개월) 129,000원",
    "10.06 배달의민족 승인취소 -23,500",
    "합계 158,800",
    "10.09",
    "카카오T 택시",
    "12,800",
], today: today)
check(p1.count == 4, "카드 내역 4건", "\(p1.map { "\($0.date ?? "-") \($0.title) \($0.amount ?? 0)" })")
if p1.count == 4 {
    check(p1[0].date == "2026-10-03" && p1[0].amount == 6_300 && p1[0].title.contains("스타벅스"), "1행", "\(p1[0])")
    check(p1[1].installments == 3 && p1[1].amount == 129_000 && p1[1].title.contains("쿠팡"), "할부 인식", "\(p1[1])")
    check(p1[2].type == .refund && p1[2].amount == 23_500, "취소는 환불", "\(p1[2])")
    check(p1[3].date == "2026-10-09" && p1[3].amount == 12_800 && p1[3].title.contains("택시"), "여러 줄로 나뉜 거래", "\(p1[3])")
}
let p2 = Parser.parse(lines: ["12.28 연말 쇼핑 50,000"], today: "2026-01-05")
check(p2.first?.date == "2025-12-28", "연도 없는 날짜는 가까운 과거로", "\(p2)")
let rc = Parser.parse(lines: ["김밥천국 강남점", "2026-10-10 12:31", "참치김밥 1 4,500", "라면 1 5,000", "합계 9,500"], today: today)
check(rc.count == 1 && rc.first?.amount == 9_500 && rc.first?.title == "김밥천국 강남점", "영수증 합계", "\(rc)")
check(Parser.parse(lines: ["카드번호 1234-****-****-5678", "결제예정금액 1,234,000"], today: today).isEmpty, "안내 문구·합계는 거래로 넣지 않음")

// 분류·중복
check(Calc.guessCategory("스타벅스 역삼", rules: [:]) == .cafe, "카테고리 추천")
check(Calc.guessCategory("우리동네가게", rules: [Calc.normalize("우리동네가게"): "health"]) == .health, "배운 분류 적용")
check(Calc.isDuplicate(tx("2026-10-03", .expense, 6300, title: "스타벅스"), in: [tx("2026-10-03", .expense, 6300, title: "스타벅스 역삼점")]), "중복 찾기")
check(!Calc.isDuplicate(tx("2026-10-03", .expense, 6300, title: "스타벅스"), in: [tx("2026-10-04", .expense, 6300, title: "스타벅스")]), "날짜 다르면 중복 아님")

// 한줄평
var ol = Ledger()
check(Calc.oneLiner(ol, month: "2026-10").contains("기록이 없어요"), "기록 없을 때 단정하지 않음")
ol.transactions = [tx("2026-10-02", .expense, 300_000, cat: .food)]
ol.settings.categoryBudgets = ["food": 200_000]
check(Calc.oneLiner(ol, month: "2026-10").contains("100,000원"), "예산 초과 안내", Calc.oneLiner(ol, month: "2026-10"))

print("✅ 통과 \(passed)개" + (failures > 0 ? ", ❌ 실패 \(failures)개" : ""))
exit(failures > 0 ? 1 : 0)
