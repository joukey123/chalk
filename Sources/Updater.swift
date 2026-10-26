import Foundation
import AppKit

/// 공개 배포 저장소(chack-release)의 최신 Release를 확인하고,
/// 이 맥에 맞는 DMG(애플 실리콘 / 인텔)를 받아 앱을 바꿔 끼운 뒤 다시 연다.
/// 가계부 기록(iCloud Drive)은 업데이트와 상관없이 그대로 남는다.
@MainActor
final class Updater: ObservableObject {
    @Published var available: String?
    @Published var notes = ""
    @Published var status = "업데이트를 아직 확인하지 않았어요."
    @Published var busy = false
    private var assetURL: URL?

    struct Release: Decodable {
        struct Asset: Decodable { var name: String; var browser_download_url: String }
        var tag_name: String
        var body: String?
        var assets: [Asset]
    }

    // MARK: 칩 종류

    /// 이 앱이 빌드된 칩 (Info.plist)
    static var builtArch: String { Bundle.main.object(forInfoDictionaryKey: "ChackArch") as? String ?? "" }

    /// 실제 맥이 애플 실리콘인지 (인텔용 앱을 Rosetta로 돌리는 경우도 포함)
    static var isAppleSiliconMac: Bool {
        var v: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &v, &size, nil, 0) == 0 && v == 1
    }

    static var assetName: String { isAppleSiliconMac ? "Chack-AppleSilicon.dmg" : "Chack-Intel.dmg" }
    static var chipLabel: String { isAppleSiliconMac ? "애플 실리콘" : "인텔" }

    /// 인텔용 앱을 애플 실리콘 맥에서 쓰는 중이면 같은 버전이어도 바꿔주기
    static var wrongArch: Bool { builtArch == "x86_64" && isAppleSiliconMac }

    static func newer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    // MARK: 확인

    func check(silent: Bool) async {
        busy = true
        defer { busy = false }
        let url = URL(string: "https://api.github.com/repos/\(AppInfo.releaseRepo)/releases/latest")!
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let rel = try JSONDecoder().decode(Release.self, from: data)
            let version = rel.tag_name.hasPrefix("v") ? String(rel.tag_name.dropFirst()) : rel.tag_name
            assetURL = rel.assets.first { $0.name == Updater.assetName }.flatMap { URL(string: $0.browser_download_url) }
            if (Updater.newer(version, than: AppInfo.version) || Updater.wrongArch) && assetURL != nil {
                available = version
                notes = (rel.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                status = Updater.wrongArch && !Updater.newer(version, than: AppInfo.version)
                    ? "이 맥은 애플 실리콘이에요. 더 빠른 애플 실리콘용으로 바꿀 수 있어요."
                    : "새 버전 \(version)이 있어요." + (notes.isEmpty ? "" : " " + (notes.components(separatedBy: .newlines).first ?? ""))
            } else {
                available = nil
                status = "최신 버전을 쓰고 있어요 (\(Updater.chipLabel)용)."
            }
        } catch {
            if !silent { status = "업데이트를 확인하지 못했어요. 인터넷 연결을 확인해주세요." }
        }
    }

    // MARK: 설치

    func install() {
        guard let v = available, let asset = assetURL else { return }
        let current = Bundle.main.bundleURL
        let parent = current.deletingLastPathComponent()

        if current.path.contains("/AppTranslocation/") || current.path.hasPrefix("/Volumes/") {
            alert("응용 프로그램 폴더로 옮긴 뒤 업데이트해주세요",
                  "지금은 DMG나 다운로드 폴더에서 바로 실행 중이에요. Chack!을 응용 프로그램(Applications) 폴더로 옮겨서 다시 연 뒤 업데이트를 눌러주세요.")
            return
        }

        busy = true
        status = "v\(v) (\(Updater.chipLabel)용)을 내려받는 중…"
        Task {
            do {
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("chack-update-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
                let dmg = tmp.appendingPathComponent(Updater.assetName)
                let (file, resp) = try await URLSession.shared.download(from: asset)
                guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError("파일을 받지 못했어요") }
                try FileManager.default.moveItem(at: file, to: dmg)

                status = "설치 파일을 여는 중…"
                let staged = try await Task.detached { try Updater.extractApp(dmg: dmg, into: tmp) }.value

                // 응용 프로그램 폴더에 쓸 수 없으면 DMG를 열어 직접 옮기도록 안내
                guard FileManager.default.isWritableFile(atPath: parent.path) else {
                    NSWorkspace.shared.open(dmg)
                    busy = false
                    status = "설치 파일을 열었어요. Chack!을 응용 프로그램 폴더로 끌어다 놓아 바꿔주세요."
                    return
                }

                let script = tmp.appendingPathComponent("swap.sh")
                try Updater.swapScript.write(to: script, atomically: true, encoding: .utf8)
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/bash")
                p.arguments = [script.path, "\(ProcessInfo.processInfo.processIdentifier)", staged.path, current.path, tmp.path]
                try p.run()
                status = "설치 중이에요. 잠시 뒤 새 버전으로 다시 열려요."
                try? await Task.sleep(nanoseconds: 400_000_000)
                NSApp.terminate(nil)
            } catch {
                busy = false
                status = "업데이트하지 못했어요 (\(error.localizedDescription)). 배포 페이지에서 DMG를 직접 받아 설치할 수 있어요."
            }
        }
    }

    struct UpdateError: LocalizedError {
        var message: String
        init(_ m: String) { message = m }
        var errorDescription: String? { message }
    }

    /// DMG를 열어 안의 앱을 임시 폴더로 복사하고 DMG는 닫는다
    nonisolated static func extractApp(dmg: URL, into dir: URL) throws -> URL {
        let mount = dir.appendingPathComponent("mnt", isDirectory: true)
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        try run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path, dmg.path])
        defer { _ = try? run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }
        guard let app = try FileManager.default.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" }) else { throw UpdateError("설치 파일 안에 앱이 없어요") }
        let staged = dir.appendingPathComponent("new", isDirectory: true).appendingPathComponent(app.lastPathComponent)
        try FileManager.default.createDirectory(at: staged.deletingLastPathComponent(), withIntermediateDirectories: true)
        try run("/usr/bin/ditto", [app.path, staged.path])
        guard let info = NSDictionary(contentsOf: staged.appendingPathComponent("Contents/Info.plist")),
              (info["CFBundleIdentifier"] as? String) == Bundle.main.bundleIdentifier else {
            throw UpdateError("받은 앱을 확인하지 못했어요")
        }
        return staged
    }

    /// 앱이 완전히 끝나길 기다렸다가 바꿔 끼우고 다시 연다. 실패하면 원래 앱을 되돌린다.
    static let swapScript = """
    #!/bin/bash
    PID="$1"; SRC="$2"; DST="$3"; TMP="$4"
    for i in $(seq 1 100); do kill -0 "$PID" 2>/dev/null || break; sleep 0.2; done
    BAK="${DST%.app}.old.app"
    rm -rf "$BAK"
    if mv "$DST" "$BAK" && /usr/bin/ditto "$SRC" "$DST"; then
      rm -rf "$BAK"
    else
      rm -rf "$DST"; mv "$BAK" "$DST"
    fi
    /usr/bin/xattr -dr com.apple.quarantine "$DST" 2>/dev/null
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DST" >/dev/null 2>&1
    /usr/bin/open "$DST"
    rm -rf "$TMP"
    """

    @discardableResult
    nonisolated static func run(_ exe: String, _ args: [String]) throws -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 { throw UpdateError("\((exe as NSString).lastPathComponent) 실패 (\(p.terminationStatus))") }
        return p.terminationStatus
    }

    func alert(_ title: String, _ text: String) {
        let a = NSAlert(); a.messageText = title; a.informativeText = text; a.runModal()
    }
}
