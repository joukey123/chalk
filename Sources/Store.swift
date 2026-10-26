import Foundation
import SwiftUI

/// 가계부 파일 하나(가계부.json)를 읽고 쓰는 곳.
/// 기본 위치는 iCloud Drive/차곡. 서버로는 아무것도 보내지 않는다.
@MainActor
final class Store: ObservableObject {
    static let fileName = "가계부.json"
    static let backupDir = "백업"

    @Published private(set) var ledger = Ledger()
    @Published var folder: URL?
    @Published var demo = false
    @Published var lastSaved: Date?
    @Published var lastSyncNote: String?
    @Published var blockedError: String?      // 파일을 읽지 못하면 덮어쓰지 않도록 저장을 멈춤
    @Published var toast: String?

    private var lastDiskDate: Date?
    private var timer: Timer?
    private var realLedger: Ledger?           // 예시 모드에 들어가기 전 기록

    static let deviceName: String = Host.current().localizedName ?? "Mac"

    static var iCloudRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
    }
    static var iCloudAvailable: Bool { FileManager.default.fileExists(atPath: iCloudRoot.path) }
    /// 새 기본 폴더는 iCloud Drive/Chack. 예전 이름(차곡) 폴더에 가계부가 있으면 그대로 사용
    static var defaultFolder: URL {
        let base = iCloudAvailable ? iCloudRoot
            : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let legacy = base.appendingPathComponent("차곡", isDirectory: true)
        let fm = FileManager.default
        if fm.fileExists(atPath: legacy.appendingPathComponent(fileName).path)
            || fm.fileExists(atPath: legacy.appendingPathComponent("." + fileName + ".icloud").path) {
            return legacy
        }
        return base.appendingPathComponent("Chack", isDirectory: true)
    }

    var fileURL: URL? { folder?.appendingPathComponent(Store.fileName) }
    var isICloud: Bool { folder?.path.hasPrefix(Store.iCloudRoot.path) ?? false }

    init() {
        // 예전 앱(차곡, com.joukey123.chagok)에서 고른 저장 위치를 이어받음
        if UserDefaults.standard.string(forKey: "folderPath") == nil,
           let old = UserDefaults(suiteName: "com.joukey123.chagok")?.string(forKey: "folderPath") {
            UserDefaults.standard.set(old, forKey: "folderPath")
        }
        if let p = UserDefaults.standard.string(forKey: "folderPath") {
            folder = URL(fileURLWithPath: p, isDirectory: true)
            load()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkDisk() }
        }
    }

    var needsSetup: Bool { folder == nil && !demo }

    // MARK: 위치

    func useFolder(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        folder = url
        UserDefaults.standard.set(url.path, forKey: "folderPath")
        blockedError = nil
        if let f = fileURL, FileManager.default.fileExists(atPath: f.path) || placeholderExists(f) {
            load()
        } else {
            ledger = Ledger()
            ledger.settingsUpdatedAt = Date().timeIntervalSince1970
            lastDiskDate = nil
            save()
        }
        runAutoRecords()
    }

    // MARK: 읽기

    private func placeholderExists(_ f: URL) -> Bool {
        let ph = f.deletingLastPathComponent().appendingPathComponent("." + f.lastPathComponent + ".icloud")
        return FileManager.default.fileExists(atPath: ph.path)
    }

    private func diskDate() -> Date? {
        guard let f = fileURL else { return nil }
        return (try? FileManager.default.attributesOfItem(atPath: f.path)[.modificationDate]) as? Date
    }

    /// iCloud에서 아직 내려받지 않은 파일이면 내려받기를 요청하고 잠시 기다림
    private func ensureDownloaded(_ f: URL) {
        guard placeholderExists(f) || !FileManager.default.fileExists(atPath: f.path) else { return }
        try? FileManager.default.startDownloadingUbiquitousItem(at: f)
        for _ in 0..<40 {
            if FileManager.default.fileExists(atPath: f.path) && !placeholderExists(f) { return }
            Thread.sleep(forTimeInterval: 0.25)
        }
    }

    private func readDisk() throws -> Ledger? {
        guard let f = fileURL else { return nil }
        ensureDownloaded(f)
        guard FileManager.default.fileExists(atPath: f.path) else { return nil }
        var data: Data?
        var coordErr: NSError?
        var readErr: Error?
        NSFileCoordinator().coordinate(readingItemAt: f, options: [], error: &coordErr) { url in
            do { data = try Data(contentsOf: url) } catch { readErr = error }
        }
        if let e = coordErr ?? readErr as NSError? { throw e }
        guard let d = data else { return nil }
        return try JSONDecoder().decode(Ledger.self, from: d)
    }

    func load() {
        guard !demo else { return }
        do {
            if let disk = try readDisk() {
                ledger = disk
                lastDiskDate = diskDate()
                blockedError = nil
            }
        } catch {
            blockedError = "가계부 파일을 읽지 못했어요. 기존 파일을 지키기 위해 저장을 멈췄어요. (\(error.localizedDescription))"
        }
    }

    /// 다른 기기(아이폰 등)에서 파일이 바뀌었는지 확인하고 합침
    func checkDisk() {
        guard !demo, blockedError == nil, let d = diskDate() else { return }
        if let last = lastDiskDate, abs(d.timeIntervalSince(last)) < 0.5 { return }
        do {
            guard let disk = try readDisk() else { return }
            let before = ledger.transactions.count
            ledger = Sync.merge(ledger, disk)
            lastDiskDate = d
            if !disk.savedBy.isEmpty && disk.savedBy != Store.deviceName {
                let diff = ledger.transactions.count - before
                lastSyncNote = "\(disk.savedBy)에서 바뀐 내용을 불러왔어요" + (diff != 0 ? " (\(diff > 0 ? "+" : "")\(diff)건)" : "")
                toast = lastSyncNote
            }
            runAutoRecords()
        } catch {
            // 다른 기기가 쓰는 도중일 수 있으니 다음 확인 때 다시 시도
        }
    }

    // MARK: 쓰기

    func save() {
        guard !demo, blockedError == nil, let f = fileURL else { return }
        // 저장 직전에 다른 기기의 변경이 있으면 먼저 합침
        if let d = diskDate(), let last = lastDiskDate, abs(d.timeIntervalSince(last)) >= 0.5,
           let disk = try? readDisk() {
            ledger = Sync.merge(ledger, disk)
        }
        ledger.savedAt = Date().timeIntervalSince1970
        ledger.savedBy = Store.deviceName
        ledger.deleted = Sync.pruneTombstones(ledger.deleted)
        do {
            let data = try Ledger.encoder().encode(ledger)
            try FileManager.default.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
            var coordErr: NSError?
            var writeErr: Error?
            NSFileCoordinator().coordinate(writingItemAt: f, options: .forReplacing, error: &coordErr) { url in
                do { try data.write(to: url, options: .atomic) } catch { writeErr = error }
            }
            if let e = coordErr ?? writeErr as NSError? { throw e }
            lastDiskDate = diskDate()
            lastSaved = Date()
            writeAutoBackup(data)
        } catch {
            toast = "저장하지 못했어요: \(error.localizedDescription)"
        }
    }

    /// 백업 폴더에 1시간 단위 스냅샷, 최근 72개 보관
    private func writeAutoBackup(_ data: Data) {
        guard let folder else { return }
        let dir = folder.appendingPathComponent(Store.backupDir, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter(); f.timeZone = DateUtil.tz; f.dateFormat = "yyyyMMdd-HH"
        let url = dir.appendingPathComponent("가계부-\(f.string(from: Date())).json")
        try? data.write(to: url, options: .atomic)
        let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("가계부-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in files.dropFirst(72) { try? FileManager.default.trashItem(at: old, resultingItemURL: nil) }
    }

    var backupFolder: URL? { folder?.appendingPathComponent(Store.backupDir, isDirectory: true) }

    // MARK: 거래 편집

    func upsert(_ tx: Transaction) {
        var t = tx; t.touch()
        if let i = ledger.transactions.firstIndex(where: { $0.id == t.id }) { ledger.transactions[i] = t }
        else { ledger.transactions.append(t) }
        ledger.transactions = Sync.sortTx(ledger.transactions)
        save()
    }

    func add(_ txs: [Transaction]) {
        let now = Date().timeIntervalSince1970
        ledger.transactions += txs.map { var t = $0; t.updatedAt = now; return t }
        ledger.transactions = Sync.sortTx(ledger.transactions)
        save()
    }

    func delete(_ ids: Set<String>) {
        let now = Date().timeIntervalSince1970
        for t in ledger.transactions where ids.contains(t.id) {
            ledger.deleted[t.id] = now
            if let k = t.autoKey, !ledger.skippedAutoKeys.contains(k) { ledger.skippedAutoKeys.append(k) }
        }
        ledger.transactions.removeAll { ids.contains($0.id) }
        save()
    }

    func updateSettings(_ change: (inout Settings) -> Void) {
        change(&ledger.settings)
        ledger.settingsUpdatedAt = Date().timeIntervalSince1970
        save()
        runAutoRecords()
    }

    /// 상호별로 사용자가 고친 분류를 기억
    func learn(_ pairs: [(String, Category)]) {
        guard !pairs.isEmpty else { return }
        for (title, c) in pairs where !Calc.normalize(title).isEmpty {
            ledger.settings.merchantRules[Calc.normalize(title)] = c.rawValue
        }
        ledger.settingsUpdatedAt = Date().timeIntervalSince1970
    }

    func runAutoRecords() {
        guard blockedError == nil, folder != nil || demo else { return }
        let new = Calc.pendingAutoRecords(ledger, today: DateUtil.todayString())
        guard !new.isEmpty else { return }
        ledger.transactions = Sync.sortTx(ledger.transactions + new)
        save()
    }

    // MARK: 백업·복원

    func backupData() throws -> Data { try Ledger.encoder().encode(ledger) }

    /// 백업 파일 또는 웹 가계부 백업을 읽어 확인용 정보를 돌려줌
    static func readBackup(_ url: URL) -> (Ledger, String)? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let l = try? JSONDecoder().decode(Ledger.self, from: data) {
            return (l, "Chack! 백업: 거래 \(l.transactions.count)건, 카드 \(l.settings.cards.count)개")
        }
        if let r = WebImport.parse(data) { return (r.ledger, r.note) }
        return nil
    }

    /// 지금 기록을 백업 폴더에 남긴 뒤, 불러온 기록으로 바꿈 (다른 기기에도 그대로 반영되도록 처리)
    func restore(_ incoming: Ledger) {
        if let dir = backupFolder, let data = try? backupData() {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let f = DateFormatter(); f.timeZone = DateUtil.tz; f.dateFormat = "yyyyMMdd-HHmmss"
            try? data.write(to: dir.appendingPathComponent("복원전-\(f.string(from: Date())).json"))
        }
        let now = Date().timeIntervalSince1970
        var next = incoming
        next.format = "chagok-ledger"
        let keep = Set(next.transactions.map { $0.id })
        for t in ledger.transactions where !keep.contains(t.id) { next.deleted[t.id] = now }
        for (k, v) in ledger.deleted where next.deleted[k] == nil { next.deleted[k] = v }
        next.transactions = Sync.sortTx(next.transactions.map { var t = $0; t.updatedAt = now; return t })
        for id in keep { next.deleted[id] = nil }
        next.settingsUpdatedAt = now
        ledger = next
        save()
        runAutoRecords()
    }

    // MARK: 예시 모드

    func enterDemo() {
        realLedger = folder == nil ? nil : ledger
        ledger = SampleData.make()
        demo = true
    }
    func exitDemo() {
        demo = false
        if let r = realLedger { ledger = r } else { ledger = Ledger() }
        realLedger = nil
        if folder != nil { load(); runAutoRecords() }
    }

    // MARK: CSV

    func csv(month: String) -> Data {
        var rows = ["날짜,유형,상호·내용,금액,카테고리,결제수단,카드,할부,메모"]
        let cardName = Dictionary(uniqueKeysWithValues: ledger.settings.cards.map { ($0.id, $0.name) })
        func esc(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        for t in ledger.transactions.filter({ $0.month == month }).sorted(by: { $0.date < $1.date }) {
            rows.append([t.date, t.type.label, esc(t.title), "\(t.amount)", t.category.label, t.method.label,
                         esc(t.cardId.flatMap { cardName[$0] } ?? ""), t.installments > 1 ? "\(t.installments)개월" : "일시불", esc(t.memo)].joined(separator: ","))
        }
        return Data(("\u{FEFF}" + rows.joined(separator: "\r\n")).utf8)
    }
}
