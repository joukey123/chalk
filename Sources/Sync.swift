import Foundation

/// 맥과 아이폰이 같은 파일을 쓸 때, 서로의 변경을 잃지 않도록 합치는 규칙
/// - 거래: id별로 더 나중에 수정한 쪽을 남김
/// - 삭제: 삭제 시각이 거래 수정 시각보다 나중이면 지움
/// - 같은 자동 기록 회차가 두 기기에서 따로 생기면 하나만 남김
/// - 설정: 더 나중에 바꾼 쪽
enum Sync {
    static func merge(_ a: Ledger, _ b: Ledger) -> Ledger {
        var out = a
        var deleted = a.deleted
        for (k, v) in b.deleted { deleted[k] = max(deleted[k] ?? 0, v) }

        var byId: [String: Transaction] = [:]
        for x in a.transactions + b.transactions {
            if let old = byId[x.id], old.updatedAt >= x.updatedAt { continue }
            byId[x.id] = x
        }
        var txs = byId.values.filter { x in
            if let d = deleted[x.id], d >= x.updatedAt { return false }
            return true
        }

        // 자동 기록 중복 정리
        var seen: [String: Transaction] = [:]
        var drop = Set<String>()
        for x in txs.sorted(by: { $0.id < $1.id }) {
            guard let k = x.autoKey else { continue }
            if seen[k] != nil { drop.insert(x.id); deleted[x.id] = max(deleted[x.id] ?? 0, x.updatedAt) }
            else { seen[k] = x }
        }
        txs.removeAll { drop.contains($0.id) }

        out.transactions = sortTx(txs)
        out.deleted = pruneTombstones(deleted)
        out.skippedAutoKeys = Array(Set(a.skippedAutoKeys).union(b.skippedAutoKeys)).sorted()
        if b.settingsUpdatedAt > a.settingsUpdatedAt {
            out.settings = b.settings
            out.settingsUpdatedAt = b.settingsUpdatedAt
        }
        return out
    }

    static func sortTx(_ txs: [Transaction]) -> [Transaction] {
        txs.sorted { $0.date != $1.date ? $0.date > $1.date : $0.updatedAt > $1.updatedAt }
    }

    /// 1년 넘은 삭제 기록은 정리
    static func pruneTombstones(_ d: [String: Double]) -> [String: Double] {
        let cutoff = Date().timeIntervalSince1970 - 366 * 86_400
        return d.filter { $0.value >= cutoff }
    }
}

// MARK: - 웹 버전 백업 불러오기 (형식을 추정해서 읽음)

enum WebImport {
    struct Result { var ledger: Ledger; var note: String }

    static func parse(_ data: Data) -> Result? {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
        guard let rows = findRows(root), !rows.isEmpty else { return nil }
        var ledger = Ledger()
        var skipped = 0
        for r in rows {
            guard let tx = tx(from: r) else { skipped += 1; continue }
            ledger.transactions.append(tx)
        }
        guard !ledger.transactions.isEmpty else { return nil }
        if let dict = root as? [String: Any] { applySettings(dict, to: &ledger) }
        ledger.transactions = Sync.sortTx(ledger.transactions)
        ledger.settingsUpdatedAt = Date().timeIntervalSince1970
        let note = "웹 가계부 백업에서 \(ledger.transactions.count)건을 읽었어요" + (skipped > 0 ? " (날짜·금액을 읽지 못한 \(skipped)건 제외)" : "") + "."
        return Result(ledger: ledger, note: note)
    }

    static func findRows(_ v: Any, depth: Int = 0) -> [[String: Any]]? {
        if depth > 5 { return nil }
        if let arr = v as? [[String: Any]], arr.contains(where: { looksLikeTx($0) }) { return arr }
        if let dict = v as? [String: Any] {
            for key in ["transactions", "records", "entries", "items", "ledger", "data", "personal"] {
                if let sub = dict[key], let r = findRows(sub, depth: depth + 1) { return r }
            }
            for (_, sub) in dict { if let r = findRows(sub, depth: depth + 1) { return r } }
        }
        return nil
    }

    static func looksLikeTx(_ d: [String: Any]) -> Bool {
        d.keys.contains(where: { ["date", "usedAt", "day"].contains($0) }) && d.keys.contains(where: { ["amount", "price", "value"].contains($0) })
    }

    static func str(_ d: [String: Any], _ keys: [String]) -> String? {
        for k in keys { if let s = d[k] as? String, !s.isEmpty { return s } }
        return nil
    }
    static func num(_ d: [String: Any], _ keys: [String]) -> Int? {
        for k in keys {
            if let n = d[k] as? NSNumber { return n.intValue }
            if let s = d[k] as? String, let n = Money.parse(s) { return n }
        }
        return nil
    }

    static func tx(from d: [String: Any]) -> Transaction? {
        guard let rawDate = str(d, ["date", "usedAt", "day"]) else { return nil }
        let date = String(rawDate.prefix(10)).replacingOccurrences(of: ".", with: "-").replacingOccurrences(of: "/", with: "-")
        guard DateUtil.isValid(date), let amt0 = num(d, ["amount", "price", "value"]), amt0 != 0 else { return nil }
        let typeRaw = (str(d, ["type", "kind", "flow"]) ?? "").lowercased()
        var type: TxType = .expense
        if typeRaw.contains("income") || typeRaw.contains("입금") || typeRaw == "in" { type = .income }
        else if typeRaw.contains("refund") || typeRaw.contains("환불") { type = .refund }
        else if typeRaw.contains("transfer") || typeRaw.contains("이체") { type = .transfer }
        else if typeRaw.contains("card") && (typeRaw.contains("pay") || typeRaw.contains("bill")) || typeRaw.contains("카드대금") { type = .cardPayment }
        let catRaw = str(d, ["category", "tag", "categoryId"]) ?? ""
        let category = Category(rawValue: catRaw) ?? Category.fromLabel(catRaw) ?? webCategory(catRaw)
        let methodRaw = (str(d, ["method", "payment", "paymentMethod"]) ?? "").lowercased()
        let method: PayMethod = methodRaw.contains("cash") || methodRaw.contains("현금") ? .cash
            : (methodRaw.contains("account") || methodRaw.contains("bank") || methodRaw.contains("계좌")) ? .account
            : (type == .income || type == .transfer ? .account : .card)
        var t = Transaction(date: date, type: type,
                            title: str(d, ["merchant", "title", "name", "description", "store"]) ?? "",
                            amount: abs(amt0), category: category, method: method,
                            installments: max(1, num(d, ["installments", "installmentMonths", "months"]) ?? 1),
                            memo: str(d, ["memo", "note"]) ?? "")
        if let id = str(d, ["id"]) { t.id = id }
        if let card = str(d, ["cardId", "card"]) { t.cardId = card }
        return t
    }

    static func webCategory(_ s: String) -> Category {
        let l = s.lowercased()
        if l.contains("food") || l.contains("음식") || l.contains("배달") { return .food }
        if l.contains("shop") || l.contains("쇼핑") { return .shopping }
        if l.contains("cafe") || l.contains("카페") || l.contains("간식") { return .cafe }
        if l.contains("trans") || l.contains("교통") { return .transport }
        if l.contains("hous") || l.contains("주거") || l.contains("통신") { return .housing }
        if l.contains("health") || l.contains("건강") { return .health }
        if l.contains("cult") || l.contains("문화") || l.contains("구독") || l.contains("sub") { return .culture }
        return .etc
    }

    static func applySettings(_ root: [String: Any], to ledger: inout Ledger) {
        let s = (root["settings"] as? [String: Any]) ?? root
        if let cards = s["cards"] as? [[String: Any]] {
            ledger.settings.cards = cards.compactMap { c in
                guard let name = str(c, ["name", "title"]) else { return nil }
                var card = Card(name: name, payDay: num(c, ["payDay", "paymentDay", "billingDay", "day"]) ?? 14)
                if let id = str(c, ["id"]) { card.id = id }
                return card
            }
        }
        if let b = s["budget"] as? [String: Any] ?? s["budgets"] as? [String: Any] {
            if let total = num(b, ["total", "monthly", "all"]) { ledger.settings.totalBudget = total }
            for (k, v) in b {
                let cat = Category(rawValue: k) ?? Category.fromLabel(k) ?? webCategory(k)
                if let n = (v as? NSNumber)?.intValue, cat != .etc || k.lowercased().contains("etc") || k.contains("기타") {
                    ledger.settings.categoryBudgets[cat.rawValue] = n
                }
            }
        }
        if let sal = s["salary"] as? [String: Any] {
            ledger.settings.salary.amount = num(sal, ["amount"]) ?? 0
            ledger.settings.salary.day = num(sal, ["day", "payDay"]) ?? 25
            if let m = str(sal, ["startMonth", "start"]), DateUtil.isValidMonth(String(m.prefix(7))) { ledger.settings.salary.startMonth = String(m.prefix(7)) }
            ledger.settings.salary.enabled = ledger.settings.salary.amount > 0
        }
    }
}
