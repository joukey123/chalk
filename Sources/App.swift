import SwiftUI
import AppKit

enum AppInfo {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev" }
    static let releaseRepo = "joukey123/chack-release"
}

enum Page: String, CaseIterable, Identifiable {
    case summary, transactions, cards, budget, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .summary: return "월간 요약"
        case .transactions: return "입금·지출"
        case .cards: return "카드 관리"
        case .budget: return "예산 관리"
        case .settings: return "설정"
        }
    }
    var icon: String {
        switch self {
        case .summary: return "square.grid.2x2"
        case .transactions: return "list.bullet.rectangle"
        case .cards: return "creditcard"
        case .budget: return "chart.pie"
        case .settings: return "gearshape"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var page: Page = .summary
    @Published var month: String = DateUtil.monthKey(DateUtil.todayString())
    @Published var search = ""
    @Published var editing: Transaction?
    @Published var importing = false

    func shiftMonth(_ n: Int) { month = DateUtil.addMonths(month, n) }
    func newTransaction(_ store: Store) {
        let today = DateUtil.todayString()
        let date = DateUtil.monthKey(today) == month ? today : month + "-01"
        editing = Transaction(date: date, cardId: store.ledger.settings.cards.first?.id)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
@MainActor
struct ChackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject var store: Store
    @StateObject var state = AppState()
    @StateObject var updater = Updater()

    init() {
        FontKit.registerBundled()
        _store = StateObject(wrappedValue: Store())
    }

    var body: some Scene {
        WindowGroup("Chack!") {
            RootView()
                .environmentObject(store)
                .environmentObject(state)
                .environmentObject(updater)
                .preferredColorScheme(.light)
                .frame(minWidth: 1080, minHeight: 720)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    store.checkDisk()
                    store.runAutoRecords()
                }
                .task { await updater.check(silent: true) }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("새 기록") { state.newTransaction(store) }.keyboardShortcut("n")
                Button("사진·PDF로 기록…") { state.importing = true }.keyboardShortcut("o")
            }
            CommandMenu("이동") {
                ForEach(Array(Page.allCases.enumerated()), id: \.element) { item in
                    Button(item.element.title) { state.page = item.element }
                        .keyboardShortcut(KeyEquivalent(Character("\(item.offset + 1)")))
                }
                Divider()
                Button("이전 달") { state.shiftMonth(-1) }.keyboardShortcut("[")
                Button("다음 달") { state.shiftMonth(1) }.keyboardShortcut("]")
            }
        }
    }
}

// MARK: - 전체 화면

struct RootView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var state: AppState

    var body: some View {
        Group {
            if store.needsSetup {
                SetupView()
            } else {
                HStack(spacing: 0) {
                    Sidebar().frame(width: 280)
                    Rectangle().fill(DF.border).frame(width: 1)
                    content.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(DF.background)
        .ignoresSafeArea()
        .sheet(item: $state.editing) { tx in
            TransactionEditor(original: tx).environmentObject(store)
        }
        .sheet(isPresented: $state.importing) {
            ImportSheet().environmentObject(store).environmentObject(state)
        }
        .overlay(alignment: .bottom) { ToastView() }
        .onAppear { store.runAutoRecords() }
    }

    @ViewBuilder var content: some View {
        switch state.page {
        case .summary: SummaryView()
        case .transactions: TransactionsView()
        case .cards: CardsView()
        case .budget: BudgetView()
        case .settings: SettingsView()
        }
    }
}

struct ToastView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        if let t = store.toast {
            Text(t)
                .font(T.sans(13))
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 8).fill(DF.ink))
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: t) {
                    try? await Task.sleep(nanoseconds: 3_500_000_000)
                    withAnimation { store.toast = nil }
                }
        }
    }
}

// MARK: - 사이드바

struct Sidebar: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var state: AppState
    @EnvironmentObject var updater: Updater
    @FocusState var searchFocused: Bool
    @State var hovered: Page?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                AppMark().frame(width: 28, height: 28)
                Text("Chack!").font(T.number(19, 800)).foregroundStyle(DF.ink)
                Pill(text: "v\(AppInfo.version)")
                Spacer()
            }
            .padding(.top, 36).padding(.bottom, 18)

            // 검색
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(DF.helper)
                TextField("기록 검색", text: $state.search)
                    .textFieldStyle(.plain).font(T.sans(14)).focused($searchFocused)
                    .onSubmit { state.page = .transactions }
                    .onChange(of: state.search) { q in if !q.isEmpty { state.page = .transactions } }
                if state.search.isEmpty {
                    Text("⌘F").font(T.mono(11)).foregroundStyle(DF.helper)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 4).stroke(DF.border))
                } else {
                    Button { state.search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(DF.disabled) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10).frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 8).fill(DF.fill))
            .background(Button("") { searchFocused = true }.keyboardShortcut("f").opacity(0))
            .padding(.bottom, 20)

            Overline("가계부").padding(.leading, 12).padding(.bottom, 6)
            ForEach(Page.allCases) { p in navRow(p) }

            Spacer()
            storageBox
            if updater.available != nil {
                Button { state.page = .settings } label: {
                    Label("새 버전 \(updater.available ?? "")", systemImage: "arrow.down.circle.fill")
                        .font(T.sans(13, 600)).foregroundStyle(DF.secondary)
                }
                .buttonStyle(.plain).padding(.top, 10)
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 16)
        .frame(maxHeight: .infinity)
        .background(DF.surface)
    }

    func navRow(_ p: Page) -> some View {
        let active = state.page == p
        return Button { state.page = p } label: {
            HStack(spacing: 10) {
                Image(systemName: p.icon).font(.system(size: 14)).frame(width: 18)
                Text(p.title).font(T.sans(14, active ? 600 : 400))
                Spacer()
                if p == .transactions, !state.search.isEmpty {
                    Text("검색 중").font(T.caption).foregroundStyle(DF.primary)
                }
            }
            .foregroundStyle(active ? DF.primary : DF.label)
            .padding(.horizontal, 12).frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 6).fill(active ? DF.primarySoft : hovered == p ? DF.fill : .clear))
            .overlay(alignment: .leading) {
                if active { Rectangle().fill(DF.primary).frame(width: 2).padding(.vertical, 8) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? p : (hovered == p ? nil : hovered) }
    }

    @ViewBuilder var storageBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            if store.demo {
                HStack(spacing: 6) {
                    Image(systemName: "eye").foregroundStyle(DF.warning)
                    Text("예시 가계부").font(T.sans(13, 600)).foregroundStyle(DF.ink)
                }
                Text("둘러보기용이라 저장되지 않아요.").font(T.sans(12)).foregroundStyle(DF.helper)
                Button(store.folder == nil ? "내 가계부 시작하기" : "내 가계부로 돌아가기") { store.exitDemo() }
                    .dfButton(.secondary, small: true).padding(.top, 4)
            } else if let err = store.blockedError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(DF.error)
                    Text("저장 멈춤").font(T.sans(13, 600)).foregroundStyle(DF.error)
                }
                Text(err).font(T.sans(12)).foregroundStyle(DF.helper).lineLimit(3)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: store.isICloud ? "icloud" : "internaldrive").foregroundStyle(DF.primary)
                    Text(store.isICloud ? "iCloud Drive · \(store.folder?.lastPathComponent ?? "")" : (store.folder?.lastPathComponent ?? "")).font(T.sans(13, 600)).foregroundStyle(DF.ink)
                }
                Text(savedText).font(T.sans(12)).foregroundStyle(DF.helper)
                if let n = store.lastSyncNote { Text(n).font(T.sans(12)).foregroundStyle(DF.success).lineLimit(2) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(DF.background))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(DF.line))
    }

    var savedText: String {
        guard let d = store.lastSaved else { return "내 기기와 내 iCloud에만 저장돼요" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"; f.timeZone = DateUtil.tz
        return "\(f.string(from: d))에 저장됨"
    }
}

/// 앱 표시 (앱 아이콘 그림을 둥근 사각형으로)
struct AppMark: View {
    static let image: NSImage? = Bundle.main.url(forResource: "Mark", withExtension: "png").flatMap { NSImage(contentsOf: $0) }
    var body: some View {
        GeometryReader { g in
            Group {
                if let img = AppMark.image {
                    Image(nsImage: img).resizable().interpolation(.high)
                } else {
                    Color(hex: 0xFC4B0B)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: g.size.width * 0.225, style: .continuous))
        }
    }
}

// MARK: - 페이지 공통 머리

struct PageScaffold<Header: View, Content: View>: View {
    var title: String
    var subtitle: String? = nil
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(T.headline).foregroundStyle(DF.ink)
                        if let s = subtitle { Text(s).font(T.body).foregroundStyle(DF.tertiary) }
                    }
                    Spacer()
                    header
                }
                content
            }
            .padding(.horizontal, 40).padding(.top, 40).padding(.bottom, 64)
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(DF.background)
    }
}

struct MonthSwitcher: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        HStack(spacing: 4) {
            Button { state.shiftMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 14) }
                .dfButton(.ghost, small: true).help("이전 달 (⌘[)")
            Menu {
                let cur = DateUtil.monthKey(DateUtil.todayString())
                ForEach(0..<24, id: \.self) { i in
                    let m = DateUtil.addMonths(cur, -i)
                    Button(DateUtil.monthTitle(m)) { state.month = m }
                }
            } label: {
                Text(DateUtil.monthTitle(state.month)).font(T.sans(15, 600)).foregroundStyle(DF.ink)
            }
            .menuStyle(.borderlessButton).fixedSize()
            .padding(.horizontal, 8)
            Button { state.shiftMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 14) }
                .dfButton(.ghost, small: true).help("다음 달 (⌘])")
            if state.month != DateUtil.monthKey(DateUtil.todayString()) {
                Button("이번 달") { state.month = DateUtil.monthKey(DateUtil.todayString()) }
                    .dfButton(.secondary, small: true).padding(.leading, 4)
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 8).fill(DF.surface))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(DF.border))
    }
}

// MARK: - 첫 실행

struct SetupView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: 24) {
                AppMark().frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Chack! · 월간 가계부").font(T.display).foregroundStyle(DF.ink)
                    Text("기록은 서버가 아니라 내 기기와 내 iCloud Drive에만 저장돼요.\n맥과 아이폰이 같은 가계부 파일 하나를 함께 사용해요.")
                        .font(T.bodyLarge).foregroundStyle(DF.tertiary).lineSpacing(6)
                }
                VStack(spacing: 12) {
                    option(icon: "icloud", title: "iCloud Drive에 저장 (추천)",
                           text: Store.iCloudAvailable ? "iCloud Drive › \(Store.defaultFolder.lastPathComponent) › 가계부.json — 아이폰 앱과 함께 쓸 수 있어요."
                                                       : "이 맥에서 iCloud Drive가 켜져 있지 않아요. 시스템 설정 › Apple 계정 › iCloud에서 켜주세요.",
                           primary: true, enabled: Store.iCloudAvailable) {
                        store.useFolder(Store.defaultFolder)
                    }
                    option(icon: "folder", title: "다른 폴더 선택", text: "원하는 폴더에 가계부 파일을 만들거나, 이미 있는 가계부 폴더를 열어요.", primary: false, enabled: true) {
                        let p = NSOpenPanel()
                        p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
                        p.prompt = "이 폴더 사용"
                        if p.runModal() == .OK, let u = p.url { store.useFolder(u) }
                    }
                    option(icon: "eye", title: "예시로 둘러보기", text: "가상의 기록으로 화면을 먼저 살펴봐요. 저장되지 않아요.", primary: false, enabled: true) {
                        store.enterDemo()
                    }
                }
            }
            .frame(maxWidth: 620)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .background(DF.background)
    }

    func option(icon: String, title: String, text: String, primary: Bool, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon).font(.system(size: 20)).foregroundStyle(primary ? .white : DF.primary)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 8).fill(primary ? DF.primary : DF.primarySoft))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(T.sans(16, 600)).foregroundStyle(DF.ink)
                    Text(text).font(T.sans(13)).foregroundStyle(DF.tertiary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(DF.disabled)
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 12).fill(DF.surface))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(primary ? DF.primary.opacity(0.4) : DF.line))
            .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }
}
