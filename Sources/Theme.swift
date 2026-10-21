import SwiftUI
import AppKit
import CoreText

// MARK: - 색 (DocuForge)

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
}

enum DF {
    static let primary = Color(hex: 0x2563EB)
    static let primaryHover = Color(hex: 0x1D4ED8)
    static let primarySoft = Color(hex: 0xEFF6FF)
    static let secondary = Color(hex: 0x7C3AED)
    static let secondarySoft = Color(hex: 0xF5F3FF)
    static let tertiary = Color(hex: 0x6B7280)
    static let background = Color(hex: 0xFAFAFA)
    static let surface = Color.white
    static let success = Color(hex: 0x16A34A)
    static let successSoft = Color(hex: 0xF0FDF4)
    static let warning = Color(hex: 0xCA8A04)
    static let warningSoft = Color(hex: 0xFFF7ED)
    static let error = Color(hex: 0xDC2626)
    static let errorHover = Color(hex: 0xB91C1C)
    static let errorSoft = Color(hex: 0xFEF2F2)
    static let ink = Color(hex: 0x18181B)
    static let text = Color(hex: 0x3F3F46)
    static let label = Color(hex: 0x52525B)
    static let helper = Color(hex: 0x71717A)
    static let disabled = Color(hex: 0xA1A1AA)
    static let line = Color(hex: 0xF4F4F5)
    static let border = Color(hex: 0xE4E4E7)
    static let borderHover = Color(hex: 0xD4D4D8)
    static let fill = Color(hex: 0xF4F4F5)

    static func category(_ c: Category) -> Color {
        switch c {
        case .food: return Color(hex: 0x2563EB)
        case .shopping: return Color(hex: 0x7C3AED)
        case .cafe: return Color(hex: 0xCA8A04)
        case .transport: return Color(hex: 0x16A34A)
        case .housing: return Color(hex: 0x0891B2)
        case .health: return Color(hex: 0xDC2626)
        case .culture: return Color(hex: 0xDB2777)
        case .etc: return Color(hex: 0x6B7280)
        }
    }

    static func badgeColors(_ t: TxType) -> (Color, Color) {
        switch t {
        case .income: return (successSoft, success)
        case .expense: return (errorSoft, error)
        case .refund: return (warningSoft, warning)
        case .cardPayment: return (primarySoft, primary)
        case .transfer: return (fill, label)
        }
    }

    static func amountColor(_ t: TxType) -> Color {
        switch t {
        case .income: return success
        case .refund: return warning
        case .expense: return ink
        case .transfer, .cardPayment: return helper
        }
    }
}

// MARK: - 글꼴
// 한글: Pretendard (라틴 글자는 Inter 기반) · 숫자 강조: Plus Jakarta Sans · 날짜·배지: Fira Code

enum FontKit {
    private static var cache: [String: NSFont] = [:]
    private static let wght = 0x77676874 // 'wght'

    static func registerBundled() {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for f in files where ["ttf", "otf"].contains(f.pathExtension.lowercased()) {
            CTFontManagerRegisterFontsForURL(f as CFURL, .process, nil)
        }
    }

    static func ns(_ postscript: String, _ size: CGFloat, _ weight: CGFloat, fallback: NSFont.Weight = .regular) -> NSFont {
        let key = "\(postscript)|\(size)|\(weight)"
        if let f = cache[key] { return f }
        var font: NSFont
        if NSFont(name: postscript, size: size) != nil {
            let attr = NSFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)
            let attrs: [NSFontDescriptor.AttributeName: Any] = [.name: postscript, attr: [NSNumber(value: wght): NSNumber(value: Double(weight))]]
            let desc = NSFontDescriptor(fontAttributes: attrs)
            font = NSFont(descriptor: desc, size: size) ?? NSFont.systemFont(ofSize: size, weight: fallback)
        } else {
            font = NSFont.systemFont(ofSize: size, weight: fallback)
        }
        cache[key] = font
        return font
    }
}

enum T {
    static func sans(_ size: CGFloat, _ w: CGFloat = 400) -> Font {
        Font(FontKit.ns("PretendardVariable-Regular", size, w, fallback: w >= 700 ? .bold : w >= 600 ? .semibold : w >= 500 ? .medium : .regular) as CTFont)
    }
    static func number(_ size: CGFloat, _ w: CGFloat = 800) -> Font {
        Font(FontKit.ns("PlusJakartaSans-Regular", size, w, fallback: .heavy) as CTFont)
    }
    static func mono(_ size: CGFloat = 13, _ w: CGFloat = 400) -> Font {
        let f = FontKit.ns("FiraCode-Light", size, w)
        if f.fontName.lowercased().contains("fira") { return Font(f as CTFont) }
        return .system(size: size, weight: w >= 500 ? .medium : .regular, design: .monospaced)
    }

    static let display = sans(34, 800)
    static let headline = sans(26, 700)
    static let subhead = sans(19, 600)
    static let bodyLarge = sans(16)
    static let body = sans(15)
    static let bodySmall = sans(14)
    static let caption = sans(12, 500)
    static let overline = sans(11, 600)
}

// MARK: - 공통 부품

struct CardBox<Content: View>: View {
    var padding: CGFloat = 24
    var elevated = false
    @ViewBuilder var content: Content
    @State var hover = false

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(DF.surface))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(elevated ? Color.clear : DF.line, lineWidth: 1))
            .shadow(color: .black.opacity(elevated ? (hover ? 0.10 : 0.06) : (hover ? 0.06 : 0.04)),
                    radius: elevated ? (hover ? 16 : 6) : (hover ? 6 : 1), x: 0, y: elevated ? (hover ? 12 : 4) : (hover ? 4 : 1))
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.15), value: hover)
    }
}

struct Overline: View {
    var text: String
    init(_ t: String) { text = t }
    var body: some View {
        Text(text.uppercased()).font(T.overline).tracking(0.9).foregroundStyle(DF.helper)
    }
}

struct SectionTitle: View {
    var title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(T.subhead).foregroundStyle(DF.ink)
            if let s = subtitle { Text(s).font(T.bodySmall).foregroundStyle(DF.tertiary) }
        }
    }
}

/// API 메서드 배지처럼 쓰는 거래 유형 배지
struct TypeBadge: View {
    var type: TxType
    var body: some View {
        let (bg, fg) = DF.badgeColors(type)
        Text(type.badge)
            .font(T.sans(12, 600))
            .foregroundStyle(fg)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .frame(minWidth: 52)
            .background(RoundedRectangle(cornerRadius: 4).fill(bg))
    }
}

struct Chip: View {
    var text: String
    var color: Color? = nil
    var body: some View {
        HStack(spacing: 5) {
            if let c = color { Circle().fill(c).frame(width: 6, height: 6) }
            Text(text).font(T.caption).foregroundStyle(DF.label)
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 4).fill(DF.fill))
    }
}

/// 할부·버전 등 보라색 알약 배지
struct Pill: View {
    var text: String
    var body: some View {
        Text(text).font(T.mono(11, 500)).foregroundStyle(DF.secondary)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(Capsule().fill(DF.secondarySoft))
    }
}

enum DFButtonKind { case primary, secondary, ghost, destructive }

struct DFButtonStyle: ButtonStyle {
    var kind: DFButtonKind = .primary
    var small = false
    @Environment(\.isEnabled) var enabled

    func makeBody(configuration: Configuration) -> some View {
        Body(kind: kind, small: small, enabled: enabled, configuration: configuration)
    }

    private struct Body: View {
        var kind: DFButtonKind
        var small: Bool
        var enabled: Bool
        var configuration: ButtonStyleConfiguration
        @State var hover = false

        var body: some View {
            let pressed = configuration.isPressed
            let (bg, fg, border): (Color, Color, Color) = {
                switch kind {
                case .primary: return (hover || pressed ? DF.primaryHover : DF.primary, .white, .clear)
                case .secondary: return (hover || pressed ? DF.primarySoft : DF.surface, DF.primary, DF.primary)
                case .ghost: return (hover || pressed ? DF.fill : .clear, DF.label, .clear)
                case .destructive: return (hover || pressed ? DF.errorHover : DF.error, .white, .clear)
                }
            }()
            configuration.label
                .font(T.sans(small ? 13 : 14, 600))
                .foregroundStyle(fg)
                .padding(.horizontal, small ? 12 : 18)
                .frame(height: small ? 30 : 36)
                .background(RoundedRectangle(cornerRadius: 8).fill(bg))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(border, lineWidth: 1))
                .opacity(enabled ? 1 : 0.4)
                .contentShape(Rectangle())
                .onHover { hover = enabled && $0 }
        }
    }
}

extension View {
    func dfButton(_ kind: DFButtonKind = .primary, small: Bool = false) -> some View {
        buttonStyle(DFButtonStyle(kind: kind, small: small))
    }
}

/// 라벨이 위에 있는 입력칸
struct Field<Content: View>: View {
    var label: String
    var helper: String? = nil
    var error: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(T.sans(14, 500)).foregroundStyle(error == nil ? DF.label : DF.error)
            content
            if let e = error { Text(e).font(T.sans(12)).foregroundStyle(DF.error) }
            else if let h = helper { Text(h).font(T.sans(12)).foregroundStyle(DF.helper) }
        }
    }
}

struct DFTextField: View {
    var placeholder: String
    @Binding var text: String
    var mono = false
    var invalid = false
    var onSubmit: () -> Void = {}
    @FocusState var focused: Bool
    @State var hover = false

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(mono ? T.mono(14) : T.sans(14))
            .foregroundStyle(DF.ink)
            .padding(.horizontal, 12).frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 8).fill(DF.surface))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(invalid ? DF.error : focused ? DF.primary : hover ? DF.borderHover : DF.border,
                        lineWidth: invalid || focused ? 2 : 1))
            .focused($focused)
            .onHover { hover = $0 }
            .onSubmit(onSubmit)
    }
}

/// 금액 입력: 숫자만 받아 천 단위 쉼표를 보여줌
struct MoneyField: View {
    var placeholder = "0"
    @Binding var value: Int
    var invalid = false
    @State var text = ""
    var body: some View {
        HStack(spacing: 0) {
            DFTextField(placeholder: placeholder, text: $text, mono: true, invalid: invalid)
                .onChange(of: text) { new in
                    let v = Money.parse(new) ?? 0
                    if v != value { value = v }
                    let formatted = v == 0 && new.filter(\.isNumber).isEmpty ? "" : Money.plain(v)
                    if formatted != new { text = formatted }
                }
                .onAppear { text = value == 0 ? "" : Money.plain(value) }
                .onChange(of: value) { v in
                    let formatted = v == 0 && text.isEmpty ? "" : Money.plain(v)
                    if formatted != text { text = formatted }
                }
            Text("원").font(T.sans(14)).foregroundStyle(DF.helper).padding(.leading, 8)
        }
    }
}

struct DFPickerBox<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .labelsHidden()
            .pickerStyle(.menu)
            .font(T.sans(14))
            .padding(.horizontal, 6).frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 8).fill(DF.surface))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(DF.border, lineWidth: 1))
    }
}

/// 안내 상자 (12px 모서리)
struct Callout: View {
    enum Kind { case info, warning, error, success }
    var kind: Kind = .info
    var title: String? = nil
    var text: String
    var icon: String? = nil
    var body: some View {
        let (bg, fg, sym): (Color, Color, String) = {
            switch kind {
            case .info: return (DF.primarySoft, DF.primary, "info.circle.fill")
            case .warning: return (DF.warningSoft, DF.warning, "exclamationmark.triangle.fill")
            case .error: return (DF.errorSoft, DF.error, "xmark.octagon.fill")
            case .success: return (DF.successSoft, DF.success, "checkmark.circle.fill")
            }
        }()
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon ?? sym).font(.system(size: 15)).foregroundStyle(fg).padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                if let t = title { Text(t).font(T.sans(14, 600)).foregroundStyle(DF.ink) }
                Text(text).font(T.sans(14)).foregroundStyle(DF.text).lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(bg))
        .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(fg).frame(width: 3).padding(.vertical, 12) }
    }
}

struct Bar: View {
    var ratio: Double
    var color: Color = DF.primary
    var height: CGFloat = 8
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(DF.fill)
                Capsule().fill(color).frame(width: max(0, min(1, ratio)) * g.size.width)
            }
        }
        .frame(height: height)
    }
}

struct EmptyState: View {
    var icon: String
    var title: String
    var text: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 28)).foregroundStyle(DF.disabled)
            Text(title).font(T.sans(15, 600)).foregroundStyle(DF.label)
            Text(text).font(T.sans(13)).foregroundStyle(DF.helper).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 32)
    }
}

struct Divider1: View {
    var body: some View { Rectangle().fill(DF.line).frame(height: 1) }
}
