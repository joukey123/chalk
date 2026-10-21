import Foundation

/// 카드 이용내역·영수증에서 읽은 글자 줄들을 거래 후보로 바꾼다.
/// 읽지 못한 날짜·금액은 임의로 채우지 않는다.
enum Parser {
    struct Candidate: Equatable {
        var date: String?
        var title: String
        var amount: Int?
        var type: TxType = .expense
        var installments: Int = 1
        var raw: String
    }

    private static func re(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p, options: [.caseInsensitive]) }

    static let fullDate = re(#"(?<!\d)(20\d{2}|\d{2})\s*[.\-/년]\s*(\d{1,2})\s*[.\-/월]\s*(\d{1,2})(?:\s*일)?(?!\d)"#)
    static let shortDate = re(#"(?<![\d,.])(\d{1,2})\s*[.\-/월]\s*(\d{1,2})(?:\s*일)?(?![\d,])"#)
    static let amountWon = re(#"(-|−|\()?\s*(\d{1,3}(?:,\d{3})+|\d{3,9})\s*원"#)
    static let amountComma = re(#"(-|−|\()?\s*(?<![\d.])(\d{1,3}(?:,\d{3})+)(?![\d,])"#)
    static let time = re(#"\d{1,2}:\d{2}(?::\d{2})?"#)
    static let cardNo = re(#"[\d*]{4}[\-\s][\d*]{2,4}[\-\s][\d*]{2,4}(?:[\-\s][\d*]{2,4})?"#)
    static let inst = re(#"(?:할부\s*(\d{1,2})|(\d{1,2})\s*개월)"#)
    static let summaryWords = re(#"합\s*계|총\s*(?:액|합|사용|청구|결제|금액|이용)|청구\s*(?:금액|예정)|결제\s*(?:예정|금액\s*합)|이용\s*한도|한도|포인트|잔액|소\s*계|누적|납부\s*금액|이용\s*금액\s*합|할인\s*금액|적립"#)
    static let receiptTotal = re(#"합\s*계|총\s*액|결\s*제\s*금\s*액|받을\s*금액|승인\s*금액|총\s*결제|판매\s*금액|청구\s*금액"#)
    static let noise = re(#"일시불|승인|국내|해외|체크|신용|정상|매입|확정|이용|가맹점|카드|원\b|[|│¦]"#)

    static func ns(_ s: String) -> NSRange { NSRange(s.startIndex..., in: s) }
    static func sub(_ s: String, _ r: NSRange) -> String { Range(r, in: s).map { String(s[$0]) } ?? "" }

    /// 날짜 찾기. 연도가 없으면 오늘 기준으로 가장 가까운 과거로 추정
    static func findDate(_ line: String, today: String) -> (String, NSRange)? {
        let (ty, _) = DateUtil.parts(DateUtil.monthKey(today))
        if let m = fullDate.firstMatch(in: line, range: ns(line)) {
            var y = Int(sub(line, m.range(at: 1))) ?? 0
            if y < 100 { y += 2000 }
            let mo = Int(sub(line, m.range(at: 2))) ?? 0, d = Int(sub(line, m.range(at: 3))) ?? 0
            let s = String(format: "%04d-%02d-%02d", y, mo, d)
            if DateUtil.isValid(s) { return (s, m.range) }
        }
        for m in shortDate.matches(in: line, range: ns(line)) {
            let mo = Int(sub(line, m.range(at: 1))) ?? 0, d = Int(sub(line, m.range(at: 2))) ?? 0
            var s = String(format: "%04d-%02d-%02d", ty, mo, d)
            guard DateUtil.isValid(s) else { continue }
            if s > today { s = String(format: "%04d-%02d-%02d", ty - 1, mo, d) }
            if DateUtil.isValid(s) { return (s, m.range) }
        }
        return nil
    }

    /// 금액 찾기 (줄의 마지막 금액). 음수·괄호·취소는 환불로
    static func findAmount(_ line: String) -> (Int, Bool, NSRange)? {
        var matches = amountWon.matches(in: line, range: ns(line))
        if matches.isEmpty { matches = amountComma.matches(in: line, range: ns(line)) }
        guard let m = matches.last, let v = Money.parse(sub(line, m.range(at: 2))), v > 0, v < 100_000_000 else { return nil }
        let negative = m.range(at: 1).location != NSNotFound
        return (v, negative, m.range)
    }

    static func cleanTitle(_ line: String, removing ranges: [NSRange]) -> String {
        var s = line
        for r in ranges.sorted(by: { $0.location > $1.location }) {
            if let rr = Range(r, in: s) { s.replaceSubrange(rr, with: " ") }
        }
        for rx in [time, cardNo, inst, noise] { s = rx.stringByReplacingMatches(in: s, range: ns(s), withTemplate: " ") }
        s = s.replacingOccurrences(of: #"(?<![가-힣A-Za-z])\d[\d,.\-]*(?![가-힣A-Za-z])"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: CharacterSet(charactersIn: " -·:;,.()[]/*|"))
    }

    static func installments(_ line: String) -> Int {
        guard let m = inst.firstMatch(in: line, range: ns(line)) else { return 1 }
        let a = sub(line, m.range(at: 1)), b = sub(line, m.range(at: 2))
        let n = Int(a.isEmpty ? b : a) ?? 1
        return (2...36).contains(n) ? n : 1
    }

    static func parse(lines rawLines: [String], today: String) -> [Candidate] {
        let lines = rawLines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var out: [Candidate] = []
        var pending: (date: String, title: String)?

        for line in lines {
            let isSummary = summaryWords.firstMatch(in: line, range: ns(line)) != nil
            let date = findDate(line, today: today)
            let amt = findAmount(line)
            if isSummary && date == nil { pending = nil; continue }
            if isSummary && amt != nil && cleanTitle(line, removing: [date!.1, amt!.2]).count < 2 { continue }

            switch (date, amt) {
            case let (d?, a?):
                let title = cleanTitle(line, removing: [d.1, a.2])
                let refund = a.1 || line.contains("취소") || line.contains("환불")
                out.append(Candidate(date: d.0, title: title.isEmpty ? (pending?.title ?? "") : title, amount: a.0,
                                     type: refund ? .refund : .expense, installments: refund ? 1 : installments(line), raw: line))
                pending = nil
            case let (d?, nil):
                pending = (d.0, cleanTitle(line, removing: [d.1]))
            case let (nil, a?):
                guard let p = pending else { continue }
                let t = cleanTitle(line, removing: [a.2])
                let refund = a.1 || line.contains("취소") || line.contains("환불")
                out.append(Candidate(date: p.date, title: t.count >= 2 ? t : p.title, amount: a.0,
                                     type: refund ? .refund : .expense, installments: refund ? 1 : installments(line),
                                     raw: "\(p.title) / \(line)"))
                pending = nil
            default:
                if let p = pending, p.title.count < 2 {
                    let t = cleanTitle(line, removing: [])
                    if t.count >= 2 { pending = (p.date, t) }
                }
            }
        }
        // 영수증 한 장(날짜 줄이 하나뿐이고 합계 줄이 있음)이면 품목 대신 합계 한 건으로
        let datedLines = lines.filter { findDate($0, today: today) != nil }.count
        let hasTotal = lines.contains { receiptTotal.firstMatch(in: $0, range: ns($0)) != nil }
        if (out.isEmpty || (datedLines <= 1 && hasTotal)), let r = receipt(lines, today: today) { return [r] }
        return out
    }

    /// 거래 줄이 없을 때: 영수증 한 장으로 보고 날짜 + 합계 금액 + 첫 줄 상호명으로 한 건
    static func receipt(_ lines: [String], today: String) -> Candidate? {
        guard let date = lines.lazy.compactMap({ findDate($0, today: today)?.0 }).first else { return nil }
        let totals = lines.filter { receiptTotal.firstMatch(in: $0, range: ns($0)) != nil }.compactMap { findAmount($0)?.0 }
        guard let amount = totals.max() else { return nil }
        let title = lines.first { l in
            let t = cleanTitle(l, removing: [])
            return t.count >= 2 && t.rangeOfCharacter(from: .letters) != nil && !l.contains("영수증")
        }.map { cleanTitle($0, removing: []) } ?? ""
        return Candidate(date: date, title: title, amount: amount, raw: "영수증 합계로 추정")
    }
}
