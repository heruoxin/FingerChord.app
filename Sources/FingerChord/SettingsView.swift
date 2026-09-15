import GestureCore
// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

private let accent = Color(
    nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.42, green: 0.79, blue: 0.71, alpha: 1)
            : NSColor(srgbRed: 0.12, green: 0.43, blue: 0.40, alpha: 1)
    })

struct SettingsView: View {
    private static let appIcon: NSImage = {
        if let url = Bundle.main.url(forResource: "FingerChord", withExtension: "icns"),
            let image = NSImage(contentsOf: url)
        {
            return image
        }
        return NSImage(named: NSImage.applicationIconName) ?? NSImage()
    }()

    @ObservedObject var model: AppModel
    var hide: () -> Void
    var quit: () -> Void

    var body: some View {
        ScrollView {
            content.id(model.language)
        }
        .frame(width: 680, height: Self.windowHeight(model))
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(accent)
    }

    static func windowHeight(_ model: AppModel) -> CGFloat {
        let permissionHeight: CGFloat = model.accessibility && model.inputMonitoring ? 0 : 120
        let loginHeight: CGFloat = model.loginNeedsApproval || model.loginError != nil ? 44 : 0
        return min(
            720 + permissionHeight + loginHeight, (NSScreen.main?.visibleFrame.height ?? 900) - 60)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                Image(nsImage: Self.appIcon)
                    .resizable().interpolation(.high).frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("app.name")).font(.system(size: 27, weight: .semibold))
                    Text(L10n.text("app.tagline"))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(model.running ? accent : Color.orange).frame(width: 7, height: 7)
                    Text(model.statusText).font(.system(size: 11, weight: .medium)).lineLimit(2)
                }.frame(maxWidth: 205, alignment: .trailing)
            }

            if !model.accessibility || !model.inputMonitoring {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.text("permissions.intro"))
                        .font(.system(size: 12, weight: .medium))
                    HStack(spacing: 12) {
                        permission(
                            L10n.text("permissions.accessibility"), granted: model.accessibility,
                            action: model.requestAccessibility)
                        permission(
                            L10n.text("permissions.input"), granted: model.inputMonitoring,
                            action: model.requestInputMonitoring)
                    }
                    Text(L10n.text("permissions.detail"))
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(
                            horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            }

            VStack(alignment: .leading, spacing: 9) {
                sectionTitle(L10n.text("gestures.title"))
                VStack(spacing: 0) {
                    gestureRow(
                        symbol: "hand.point.up.left", title: L10n.text("gesture.middle"),
                        detail: L10n.text("gesture.middle.detail"), shortcut: L10n.text("shortcut.click"),
                        enabled: $model.middleTap)
                    Divider().padding(.leading, 50)
                    gestureRow(
                        symbol: "hand.tap", title: L10n.text("gesture.three"),
                        detail: L10n.text("gesture.three.detail"), shortcut: "⌘ W", enabled: $model.threePress)
                    Divider().padding(.leading, 50)
                    gestureRow(
                        symbol: "hand.raised", title: L10n.text("gesture.four"),
                        detail: L10n.text("gesture.four.detail"), shortcut: "⌘ Q", enabled: $model.fourPress)
                }.background(
                    Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            }

            HStack(alignment: .top, spacing: 16) {
                TouchPreview(contacts: model.snapshot.contacts, pressed: model.snapshot.buttonDown)
                    .id(model.language)
                    .frame(width: 192, height: 119)
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text(L10n.text("preview.title")).font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Text(L10n.text("preview.contacts", model.snapshot.contacts.count))
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    Toggle(L10n.text("preview.test"), isOn: $model.testMode)
                        .font(.system(size: 11)).toggleStyle(.checkbox)
                    Text(
                        model.actionCount > 0
                            ? L10n.text("preview.count", model.lastAction, model.actionCount) : model.lastAction
                    )
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(accent)
                    .lineLimit(2).frame(height: 30, alignment: .topLeading)
                    .accessibilityIdentifier("lastAction")
                    Text(L10n.text("preview.hint"))
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }.padding(.vertical, 4)
            }

            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text("login.title")).font(.system(size: 12, weight: .medium))
                        Text(L10n.text("login.detail"))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle(
                        L10n.text("login.title"),
                        isOn: Binding(get: { model.loginEnabled }, set: { model.setLoginEnabled($0) })
                    )
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .accessibilityLabel(L10n.text("login.title"))
                }
                if model.loginNeedsApproval {
                    HStack {
                        Text(L10n.text("login.approval")).font(.system(size: 11))
                        Spacer()
                        Button(L10n.text("login.open"), action: model.openLoginSettings)
                    }
                }
                if let error = model.loginError {
                    Text(error).font(.system(size: 11)).foregroundStyle(.red)
                }
            }.padding(14).background(
                Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))

            HStack {
                Text(L10n.text("language.title")).font(.system(size: 12, weight: .medium))
                Spacer()
                Picker(L10n.text("language.title"), selection: $model.language) {
                    ForEach(AppLanguage.allCases) { language in Text(language.title).tag(language) }
                }.labelsHidden().frame(width: 190)
            }

            Divider()
            HStack {
                Button(L10n.text("action.quit"), action: quit).buttonStyle(.plain).foregroundStyle(
                    .secondary)
                Button(L10n.text("action.reconnect"), action: model.reconnect).buttonStyle(.plain)
                    .foregroundStyle(.secondary).padding(.leading, 8)
                Spacer()
                Button(model.enabled ? L10n.text("action.pause") : L10n.text("action.start")) {
                    model.enabled.toggle()
                }
                .buttonStyle(.bordered)
                Button(L10n.text("action.hide")) {
                    model.enabled = true
                    hide()
                }
                .buttonStyle(.borderedProminent).tint(accent)
                .disabled(!model.running)
            }.font(.system(size: 12))
            Text(
                L10n.text(
                    "about.version",
                    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                        ?? "1.1.0")
            )
            .font(.system(size: 10)).foregroundStyle(.tertiary).frame(maxWidth: .infinity)
            Text(L10n.text("footer"))
                .font(.system(size: 10)).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(26)
        .frame(width: 680)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(accent)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
    }

    private func permission(_ name: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? accent : .secondary)
            Text(name).font(.system(size: 12))
            Spacer()
            if !granted {
                Button(L10n.text("permissions.allow"), action: action).controlSize(.small)
                    .accessibilityLabel(L10n.text("permissions.allowNamed", name))
            }
        }.frame(maxWidth: .infinity)
    }

    private func gestureRow(
        symbol: String, title: String, detail: String, shortcut: String, enabled: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 21)).foregroundStyle(accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Text(shortcut).font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary).frame(width: 59)
                .padding(.vertical, 5).background(
                    .primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 5))
            Toggle(title, isOn: enabled).labelsHidden().toggleStyle(.switch).controlSize(.small)
                .accessibilityLabel(title)
        }.padding(.horizontal, 14).padding(.vertical, 16)
    }
}

private struct TouchPreview: View {
    let contacts: [Contact]
    let pressed: Bool
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(accent.opacity(pressed ? 0.14 : 0.045))
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(accent.opacity(pressed ? 0.6 : 0.19), lineWidth: pressed ? 2 : 1)
                if contacts.isEmpty {
                    VStack(spacing: 5) {
                        Image(systemName: "rectangle.and.hand.point.up.left").font(.system(size: 21))
                        Text(L10n.text("preview.live")).font(.system(size: 10))
                    }.foregroundStyle(accent.opacity(0.55))
                }
                // Enumerated ids avoid collisions between two connected trackpads.
                ForEach(Array(contacts.enumerated()), id: \.offset) { _, contact in
                    Circle().fill(accent.opacity(0.85)).frame(width: 13, height: 13)
                        .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 2))
                        .position(
                            x: 10 + contact.x * (geometry.size.width - 20),
                            y: 10 + (1 - contact.y) * (geometry.size.height - 20))
                }
            }
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel(
                L10n.text("preview.ax", contacts.count) + (pressed ? L10n.text("preview.pressed") : ""))
    }
}
