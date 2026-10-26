import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var updater: Updater
    @State var salary = SalarySetting()
    @State var cards: [Card] = []
    @State var fixed: [FixedExpense] = []
    @State var loaded = false

    var dirty: Bool {
        salary != store.ledger.settings.salary || cards != store.ledger.settings.cards || fixed != store.ledger.settings.fixed
    }

    var monthOptions: [String] {
        let cur = DateUtil.monthKey(DateUtil.todayString())
        var ms = (-24...2).map { DateUtil.addMonths(cur, $0) }
        for extra in [salary.startMonth] + fixed.map(\.startMonth) where !ms.contains(extra) && DateUtil.isValidMonth(extra) { ms.append(extra) }
        return ms.sorted()
    }

    var body: some View {
        PageScaffold(title: "설정", subtitle: "월급·카드·고정지출, 저장 위치와 백업") {
            EmptyView()
        } content: {
            storageSection
            salarySection
            cardsSection
            fixedSection
            if dirty { saveBar }
            backupSection
            aboutSection
        }
        .onAppear { if !loaded { reset(); loaded = true } }
        .onChange(of: store.ledger.settingsUpdatedAt) { _ in if !dirty { reset() } }
    }

    func reset() {
        salary = store.ledger.settings.salary
        cards = store.ledger.settings.cards
        fixed = store.ledger.settings.fixed
    }

    var saveBar: some View {
        HStack {
            Image(systemName: "pencil.circle.fill").foregroundStyle(DF.warning)
            Text("저장하지 않은 변경이 있어요").font(T.sans(14, 500)).foregroundStyle(DF.ink)
            Spacer()
            Button("되돌리기") { reset() }.dfButton(.ghost)
            Button("설정 저장") { saveSettings() }.dfButton(.primary).keyboardShortcut("s")
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(DF.warningSoft))
    }

    func saveSettings() {
        let cleanedCards = cards.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        let cleanedFixed = fixed.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && $0.amount > 0 }
        store.updateSettings { s in
            s.salary = salary
            s.cards = cleanedCards
            s.fixed = cleanedFixed
        }
        reset()
        store.toast = "설정을 저장했어요. 지난 예정일의 월급·고정지출은 바로 기록돼요."
    }

    // MARK: 저장 위치

    var storageSection: some View {
        CardBox {
            VStack(alignment: .leading, spacing: 16) {
                SectionTitle(title: "저장 위치", subtitle: "서버 없이 이 파일 하나에 모든 기록을 저장해요")
                HStack(spacing: 12) {
                    Image(systemName: store.isICloud ? "icloud.fill" : "folder.fill").font(.system(size: 20)).foregroundStyle(DF.primary)
                        .frame(width: 40, height: 40).background(RoundedRectangle(cornerRadius: 8).fill(DF.primarySoft))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.isICloud ? "iCloud Drive › \(store.folder?.lastPathComponent ?? "") › \(Store.fileName)" : (store.fileURL?.path ?? "예시 모드"))
                            .font(T.sans(14, 600)).foregroundStyle(DF.ink).textSelection(.enabled)
                        Text(store.isICloud ? "아이폰의 파일 앱 › iCloud Drive › \(store.folder?.lastPathComponent ?? "") 에서도 같은 파일이 보여요." : "iCloud Drive 밖이라 아이폰과는 공유되지 않아요.")
                            .font(T.sans(12)).foregroundStyle(DF.helper)
                    }
                    Spacer()
                }
                HStack(spacing: 8) {
                    Button { if let f = store.fileURL { NSWorkspace.shared.activateFileViewerSelecting([f]) } } label: { Label("Finder에서 보기", systemImage: "magnifyingglass") }
                        .dfButton(.secondary, small: true).disabled(store.folder == nil)
                    Button { if let b = store.backupFolder { try? FileManager.default.createDirectory(at: b, withIntermediateDirectories: true); NSWorkspace.shared.open(b) } } label: { Label("자동 백업 폴더", systemImage: "clock.arrow.circlepath") }
                        .dfButton(.ghost, small: true).disabled(store.folder == nil)
                    Button { changeFolder() } label: { Label("위치 바꾸기", systemImage: "arrow.left.arrow.right") }
                        .dfButton(.ghost, small: true)
                    Spacer()
                }
                Text("저장할 때마다 ‘백업’ 폴더에 1시간 단위로 사본이 남아요 (최근 72개). 맥과 아이폰에서 동시에 고치면 기록을 합쳐서 저장하고, 같은 기록은 더 나중에 고친 쪽이 남아요.")
                    .font(T.sans(12)).foregroundStyle(DF.helper).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    func changeFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        p.directoryURL = Store.iCloudAvailable ? Store.iCloudRoot : nil
        p.prompt = "이 폴더 사용"
        p.message = "가계부.json이 있는 폴더를 고르면 그 기록을 열고, 없으면 새로 만들어요. 지금 기록은 원래 위치에 그대로 남아요."
        if p.runModal() == .OK, let u = p.url {
            if store.demo { store.exitDemo() }
            store.useFolder(u)
            reset()
        }
    }

    // MARK: 월급

    var salarySection: some View {
        CardBox {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    SectionTitle(title: "월급 자동 기입", subtitle: "정한 날이 지나면 앱을 열 때 입금으로 기록해요. 미리 기록하지 않아요.")
                    Spacer()
                    Toggle("", isOn: $salary.enabled).toggleStyle(.switch).labelsHidden().tint(DF.primary)
                }
                if salary.enabled {
                    HStack(alignment: .top, spacing: 16) {
                        Field(label: "이름") { DFTextField(placeholder: "월급", text: $salary.title) }.frame(width: 160)
                        Field(label: "금액") { MoneyField(value: $salary.amount) }.frame(width: 200)
                        Field(label: "매월", helper: "말일보다 크면 말일에 기록") { dayPicker($salary.day) }.frame(width: 120)
                        Field(label: "시작 월") { monthPicker($salary.startMonth) }.frame(width: 150)
                        Spacer()
                    }
                }
            }
        }
    }

    func dayPicker(_ b: Binding<Int>) -> some View {
        DFPickerBox {
            Picker("", selection: b) { ForEach(1...31, id: \.self) { d in Text(d == 31 ? "말일(31일)" : "\(d)일").tag(d) } }
        }
    }

    func monthPicker(_ b: Binding<String>) -> some View {
        DFPickerBox {
            Picker("", selection: b) { ForEach(monthOptions, id: \.self) { m in Text(DateUtil.monthTitle(m)).tag(m) } }
        }
    }

    // MARK: 카드

    var cardsSection: some View {
        CardBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionTitle(title: "카드", subtitle: "이번 달에 쓴 금액이 다음 달 결제일에 빠져나가요")
                    Spacer()
                    Button { cards.append(Card(name: "", payDay: 14)) } label: { Label("카드 추가", systemImage: "plus") }.dfButton(.secondary, small: true)
                }
                if cards.isEmpty {
                    Text("카드를 추가하면 카드별 청구 예상과 결제일을 볼 수 있어요.").font(T.sans(13)).foregroundStyle(DF.helper)
                }
                ForEach($cards) { $c in
                    HStack(spacing: 12) {
                        Image(systemName: "creditcard").foregroundStyle(DF.primary)
                        DFTextField(placeholder: "카드 이름 (예: 신한 Deep Dream)", text: $c.name).frame(maxWidth: 320)
                        Text("다음 달").font(T.sans(13)).foregroundStyle(DF.helper)
                        dayPicker($c.payDay).frame(width: 120)
                        Text("결제").font(T.sans(13)).foregroundStyle(DF.helper)
                        Spacer()
                        Button { cards.removeAll { $0.id == c.id } } label: { Image(systemName: "trash") }
                            .dfButton(.ghost, small: true).help("카드 삭제 (기록은 ‘카드 미지정’으로 남아요)")
                    }
                }
            }
        }
    }

    // MARK: 고정지출

    var fixedSection: some View {
        CardBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionTitle(title: "고정지출", subtitle: "월세·통신비·구독료처럼 매달 나가는 돈을 정한 날 자동으로 기록해요")
                    Spacer()
                    Button {
                        fixed.append(FixedExpense(name: "", amount: 0, day: 1, startMonth: DateUtil.monthKey(DateUtil.todayString())))
                    } label: { Label("고정지출 추가", systemImage: "plus") }.dfButton(.secondary, small: true)
                }
                if fixed.isEmpty {
                    Text("등록된 고정지출이 없어요.").font(T.sans(13)).foregroundStyle(DF.helper)
                }
                ForEach($fixed) { $f in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Toggle("", isOn: $f.active).toggleStyle(.switch).labelsHidden().controlSize(.small).help("자동 기록 켜기/끄기")
                            DFTextField(placeholder: "이름 (예: 월세)", text: $f.name).frame(width: 180)
                            MoneyField(value: $f.amount).frame(width: 160)
                            Text("매월").font(T.sans(13)).foregroundStyle(DF.helper)
                            dayPicker($f.day).frame(width: 120)
                            Spacer()
                            Button { fixed.removeAll { $0.id == f.id } } label: { Image(systemName: "trash") }.dfButton(.ghost, small: true)
                        }
                        HStack(spacing: 10) {
                            Spacer().frame(width: 40)
                            DFPickerBox { Picker("", selection: $f.category) { ForEach(Category.allCases) { c in Text(c.label).tag(c) } } }.frame(width: 130)
                            DFPickerBox { Picker("", selection: $f.method) { ForEach(PayMethod.allCases) { m in Text(m.label).tag(m) } } }.frame(width: 90)
                            if f.method == .card {
                                DFPickerBox {
                                    Picker("", selection: $f.cardId) {
                                        Text("카드 미지정").tag(String?.none)
                                        ForEach(cards) { c in Text(c.name.isEmpty ? "(이름 없음)" : c.name).tag(Optional(c.id)) }
                                    }
                                }
                                .frame(width: 170)
                            }
                            Text("시작").font(T.sans(13)).foregroundStyle(DF.helper)
                            monthPicker($f.startMonth).frame(width: 140)
                            Spacer()
                        }
                    }
                    .padding(.vertical, 6)
                    .opacity(f.active ? 1 : 0.55)
                    Divider1()
                }
            }
        }
    }

    // MARK: 백업

    var backupSection: some View {
        CardBox {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(title: "백업·복원", subtitle: "전체 기록과 설정을 JSON 파일 하나로 저장하고 불러와요")
                HStack(spacing: 8) {
                    Button { makeBackup() } label: { Label("백업 파일 만들기", systemImage: "square.and.arrow.down") }
                        .dfButton(.primary, small: true).disabled(store.demo)
                    Button { loadBackup() } label: { Label("백업 불러오기", systemImage: "square.and.arrow.up") }
                        .dfButton(.secondary, small: true).disabled(store.demo || store.folder == nil)
                    Spacer()
                }
                Text("백업 불러오기는 지금 기록을 바꿔치기해요. 불러오기 전에 지금 기록을 ‘백업’ 폴더에 자동으로 남겨둬요. 웹 버전 차곡 가계부에서 만든 백업 파일도 불러올 수 있어요.")
                    .font(T.sans(12)).foregroundStyle(DF.helper).fixedSize(horizontal: false, vertical: true)
                Divider1()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("예시 가계부").font(T.sans(14, 600)).foregroundStyle(DF.ink)
                        Text("가상의 기록으로 기능을 둘러봐요. 내 기록에는 영향이 없어요.").font(T.sans(12)).foregroundStyle(DF.helper)
                    }
                    Spacer()
                    Button(store.demo ? "내 가계부로 돌아가기" : "예시 둘러보기") { store.demo ? store.exitDemo() : store.enterDemo() }
                        .dfButton(.ghost, small: true)
                }
            }
        }
    }

    func makeBackup() {
        let p = NSSavePanel()
        p.allowedContentTypes = [.json]
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd"; f.timeZone = DateUtil.tz
        p.nameFieldStringValue = "Chack-백업-\(f.string(from: Date())).json"
        if p.runModal() == .OK, let u = p.url {
            do { try store.backupData().write(to: u, options: .atomic); store.toast = "백업 파일을 만들었어요." }
            catch { store.toast = "백업하지 못했어요: \(error.localizedDescription)" }
        }
    }

    func loadBackup() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.json]
        p.allowsMultipleSelection = false
        guard p.runModal() == .OK, let u = p.url else { return }
        guard let read = Store.readBackup(u) else {
            let a = NSAlert(); a.messageText = "읽을 수 없는 파일이에요"
            a.informativeText = "Chack! 백업 파일이나 웹 버전 백업 파일인지 확인해주세요. 지금 기록은 바뀌지 않았어요."
            a.runModal(); return
        }
        let (incoming, note) = read
        let a = NSAlert()
        a.messageText = "이 백업으로 바꿀까요?"
        a.informativeText = "\(note)\n\n지금 기록(거래 \(store.ledger.transactions.count)건)은 ‘백업’ 폴더에 ‘복원전-…’ 파일로 남겨둔 뒤 바꿔요. 아이폰에도 같은 기록이 반영돼요."
        a.addButton(withTitle: "바꾸기")
        a.addButton(withTitle: "취소")
        if a.runModal() == .alertFirstButtonReturn {
            store.restore(incoming)
            reset()
            store.toast = "백업을 불러왔어요."
        }
    }

    // MARK: 정보·업데이트

    var aboutSection: some View {
        CardBox {
            HStack(alignment: .center, spacing: 14) {
                AppMark().frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Chack! · 월간 가계부").font(T.sans(15, 700)).foregroundStyle(DF.ink)
                        Pill(text: "v\(AppInfo.version)")
                        Pill(text: Updater.builtArch == "x86_64" ? "Intel" : "Apple Silicon")
                    }
                    Text(updater.status).font(T.sans(12)).foregroundStyle(updater.available != nil ? DF.secondary : DF.helper)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if updater.available != nil {
                    Button("업데이트 설치") { updater.install() }.dfButton(.primary, small: true).disabled(updater.busy)
                } else {
                    Button("업데이트 확인") { Task { await updater.check(silent: false) } }.dfButton(.ghost, small: true).disabled(updater.busy)
                }
                Button { NSWorkspace.shared.open(URL(string: "https://github.com/\(AppInfo.releaseRepo)/releases")!) } label: { Image(systemName: "arrow.up.right.square") }
                    .dfButton(.ghost, small: true).help("배포 페이지 열기")
            }
        }
    }
}
