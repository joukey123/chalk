import Foundation
import AppKit

/// GitHub에서 새 버전을 확인하고, 받은 소스를 이 맥에서 다시 빌드해 설치한다 (MacClean과 같은 방식).
/// 가계부 기록은 업데이트와 상관없이 그대로 남는다.
@MainActor
final class Updater: ObservableObject {
    @Published var available: String?
    @Published var notes = ""
    @Published var status = "업데이트를 아직 확인하지 않았어요."
    @Published var busy = false

    struct Info: Decodable { var version: String; var notes: String? }

    static func newer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    func check(silent: Bool) async {
        busy = true
        defer { busy = false }
        let url = URL(string: "https://raw.githubusercontent.com/\(AppInfo.repo)/main/version.json")!
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let info = try JSONDecoder().decode(Info.self, from: data)
            if Updater.newer(info.version, than: AppInfo.version) {
                available = info.version
                notes = info.notes ?? ""
                status = "새 버전 \(info.version)이 있어요." + (notes.isEmpty ? "" : " \(notes)")
            } else {
                available = nil
                status = "최신 버전을 쓰고 있어요."
            }
        } catch {
            if !silent { status = "업데이트를 확인하지 못했어요. 인터넷 연결을 확인해주세요." }
        }
    }

    func install() {
        guard let v = available else { return }
        busy = true
        status = "새 버전을 내려받는 중…"
        Task {
            do {
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("chagok-update-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
                let zip = tmp.appendingPathComponent("Chagok.zip")
                let sources = [
                    "https://github.com/\(AppInfo.repo)/releases/download/v\(v)/Chagok.zip",
                    "https://github.com/\(AppInfo.repo)/archive/refs/heads/main.zip",
                ]
                var ok = false
                for s in sources {
                    if let r = try? await URLSession.shared.download(from: URL(string: s)!),
                       (r.1 as? HTTPURLResponse)?.statusCode == 200 {
                        try? FileManager.default.removeItem(at: zip)
                        try FileManager.default.moveItem(at: r.0, to: zip)
                        ok = true; break
                    }
                }
                guard ok else { throw URLError(.cannotFindHost) }
                try Updater.run("/usr/bin/ditto", ["-x", "-k", zip.path, tmp.path])
                guard let script = FileManager.default.enumerator(at: tmp, includingPropertiesForKeys: nil)?
                        .compactMap({ $0 as? URL }).first(where: { $0.lastPathComponent == "build.sh" }) else {
                    throw URLError(.cannotParseResponse)
                }
                let logDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs")
                try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
                let log = logDir.appendingPathComponent("Chagok-update.log")
                FileManager.default.createFile(atPath: log.path, contents: nil)
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/bash")
                p.arguments = [script.path]
                p.currentDirectoryURL = script.deletingLastPathComponent()
                var env = ProcessInfo.processInfo.environment
                env["CHAGOK_UPDATE"] = "1"
                p.environment = env
                let h = try FileHandle(forWritingTo: log)
                p.standardOutput = h; p.standardError = h
                try p.run()
                status = "설치 중이에요 (1~2분). 끝나면 앱이 자동으로 다시 열려요."
            } catch {
                busy = false
                status = "업데이트하지 못했어요 (\(error.localizedDescription)). GitHub 저장소에서 직접 받아 설치할 수 있어요."
            }
        }
    }

    static func run(_ exe: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 { throw NSError(domain: "Chagok", code: Int(p.terminationStatus)) }
    }
}
