import Foundation
import AppKit
import Vision
import PDFKit

/// 사진·PDF를 이 맥 안에서만 읽는다 (애플 내장 문자 인식 + PDFKit). 원본은 저장하지 않는다.
enum Recognizer {
    static let maxFiles = 10
    static let maxImageBytes = 15 * 1024 * 1024
    static let maxPDFBytes = 20 * 1024 * 1024
    static let maxPagesPerFile = 30
    static let maxPagesTotal = 60
    static let maxItems = 500

    struct PageResult {
        var file: String
        var page: Int?          // PDF 페이지 번호 (1부터), 사진이면 nil
        var lines: [String]
        var method: String      // "텍스트", "문자 인식"
    }

    struct Outcome {
        var pages: [PageResult] = []
        var warnings: [String] = []
    }

    enum Failure: Error { case message(String) }

    /// PDF 비밀번호 묻기 (메인 스레드에서 호출됨). nil이면 건너뜀
    typealias PasswordAsk = @MainActor (_ fileName: String, _ wrong: Bool) -> String?

    static func run(_ urls: [URL], askPassword: @escaping PasswordAsk, progress: @escaping @MainActor (String) -> Void) async -> Outcome {
        var out = Outcome()
        var pagesUsed = 0
        let files = Array(urls.prefix(maxFiles))
        if urls.count > maxFiles { out.warnings.append("한 번에 \(maxFiles)개까지 읽어요. 나머지 \(urls.count - maxFiles)개는 건너뛰었어요.") }

        for (i, url) in files.enumerated() {
            let name = url.lastPathComponent
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            await progress("파일 \(i + 1)/\(files.count) · \(name)")
            if url.pathExtension.lowercased() == "pdf" {
                if size > maxPDFBytes { out.warnings.append("\(name): PDF는 20MB까지 읽을 수 있어요."); continue }
                guard let doc = PDFDocument(url: url) else { out.warnings.append("\(name): PDF를 열 수 없어요. 파일이 손상되었을 수 있어요."); continue }
                if doc.isLocked {
                    var opened = false
                    var wrong = false
                    for _ in 0..<3 {
                        guard let pw = await askPassword(name, wrong) else { break }
                        if doc.unlock(withPassword: pw) { opened = true; break }
                        wrong = true
                    }
                    if !opened { out.warnings.append("\(name): 비밀번호가 필요한 PDF라 건너뛰었어요."); continue }
                }
                let count = doc.pageCount
                if count > maxPagesPerFile { out.warnings.append("\(name): 파일당 \(maxPagesPerFile)페이지까지만 읽었어요 (전체 \(count)페이지).") }
                for p in 0..<min(count, maxPagesPerFile) {
                    if pagesUsed >= maxPagesTotal {
                        out.warnings.append("한 번에 총 \(maxPagesTotal)페이지까지 읽어요. \(name) \(p + 1)페이지부터는 건너뛰었어요.")
                        break
                    }
                    pagesUsed += 1
                    guard let page = doc.page(at: p) else { continue }
                    await progress("파일 \(i + 1)/\(files.count) · \(name) · \(p + 1)/\(min(count, maxPagesPerFile))페이지")
                    let text = page.string ?? ""
                    let meaningful = text.filter { !$0.isWhitespace }.count
                    if meaningful >= 20 {
                        out.pages.append(PageResult(file: name, page: p + 1, lines: textLines(text), method: "텍스트"))
                    } else if let cg = render(page) {
                        let lines = (try? ocr(cg)) ?? []
                        out.pages.append(PageResult(file: name, page: p + 1, lines: lines, method: "문자 인식"))
                    }
                }
            } else {
                if size > maxImageBytes { out.warnings.append("\(name): 사진은 15MB까지 읽을 수 있어요."); continue }
                guard let img = NSImage(contentsOf: url),
                      let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    out.warnings.append("\(name): 사진을 열 수 없어요. JPG·PNG·WEBP·BMP·HEIC 파일인지 확인해주세요."); continue
                }
                do {
                    out.pages.append(PageResult(file: name, page: nil, lines: try ocr(cg), method: "문자 인식"))
                } catch {
                    out.warnings.append("\(name): 글자를 읽지 못했어요 (\(error.localizedDescription)).")
                }
            }
        }
        return out
    }

    static func textLines(_ s: String) -> [String] {
        s.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func render(_ page: PDFPage) -> CGImage? {
        let box = page.bounds(for: .mediaBox)
        let scale: CGFloat = min(3, max(1.5, 2400 / max(box.width, box.height, 1)))
        let size = NSSize(width: box.width * scale, height: box.height * scale)
        let img = page.thumbnail(of: size, for: .mediaBox)
        return img.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    /// 애플 문자 인식. 같은 높이의 글자 조각을 한 줄로 묶어 표의 한 행이 한 줄이 되게 함
    static func ocr(_ image: CGImage) throws -> [String] {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = false
        req.recognitionLanguages = ["ko-KR", "en-US"]
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([req])
        let obs = (req.results ?? []).compactMap { o -> (CGRect, String)? in
            guard let t = o.topCandidates(1).first?.string, !t.isEmpty else { return nil }
            return (o.boundingBox, t)
        }
        // 위에서 아래로 (Vision 좌표는 아래가 0)
        let sorted = obs.sorted { $0.0.midY > $1.0.midY }
        var rows: [[(CGRect, String)]] = []
        for item in sorted {
            if let last = rows.last, let ref = last.first,
               abs(ref.0.midY - item.0.midY) < max(ref.0.height, item.0.height) * 0.55 {
                rows[rows.count - 1].append(item)
            } else {
                rows.append([item])
            }
        }
        return rows.map { r in r.sorted { $0.0.minX < $1.0.minX }.map { $0.1 }.joined(separator: "  ") }
    }
}
