// SPDX-License-Identifier: GPL-3.0-only
import GestureCore
import SwiftUI

private typealias Gesture = GestureCore.Gesture

private let accent = Color.indigo

struct SettingsView: View {
    @ObservedObject var model: AppModel
    var hide: () -> Void
    var quit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 40, height: 40)
                Text(L10n.text("app.name")).font(.title2.weight(.semibold))
                Spacer()
                if let problem = model.problem {
                    Text(problem).foregroundStyle(.orange).multilineTextAlignment(.trailing)
                }
                switchFor(L10n.text("enabled"), isOn: $model.enabled)
            }
            if !model.accessibility || !model.inputMonitoring {
                VStack(spacing: 0) {
                    permission("permission.accessibility", model.accessibility, model.requestAccessibility)
                    Divider()
                    permission("permission.input", model.inputMonitoring, model.requestInputMonitoring)
                }
                .padding(.vertical, 16)
            } else {
                TouchPreview(feed: model.touches, placeholder: L10n.text("preview.placeholder"))
                    .frame(height: 156)
                    .padding(.vertical, 20)
            }
            ForEach(Gesture.allCases, id: \.self) { gesture in
                if gesture != Gesture.allCases.first { Divider() }
                row {
                    GestureGlyph(gesture: gesture)
                    Text(L10n.text("gesture." + gesture.rawValue))
                    Spacer()
                    Text(L10n.text("action." + gesture.rawValue)).foregroundStyle(.secondary)
                    switchFor(
                        L10n.text("gesture." + gesture.rawValue),
                        isOn: Binding(
                            get: { model.gestures.contains(gesture) },
                            set: { on in
                                if on { model.gestures.insert(gesture) } else { model.gestures.remove(gesture) }
                            }))
                }
            }
            Spacer().frame(height: 22)
            row {
                Text(L10n.text("login"))
                Spacer()
                if model.loginNeedsApproval { Button(L10n.text("allow"), action: model.openLoginSettings) }
                switchFor(
                    L10n.text("login"), isOn: Binding(get: { model.loginEnabled }, set: model.setLoginEnabled))
            }
            if let error = model.loginError {
                Text(error).font(.caption).foregroundStyle(.red).padding(.bottom, 8)
            }
            Divider()
            row {
                Text(L10n.text("language"))
                Spacer()
                Picker(L10n.text("language"), selection: $model.language) {
                    ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden().fixedSize()
            }
            HStack {
                Button(L10n.text("quit"), action: quit)
                Spacer()
                Button(L10n.text("hide"), action: hide).keyboardShortcut(.defaultAction).tint(accent)
            }
            .padding(.top, 22)
        }
        .padding(EdgeInsets(top: 8, leading: 28, bottom: 24, trailing: 28))
        .frame(width: 460)
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 12, content: content).frame(height: 38)
    }

    private func switchFor(_ label: String, isOn: Binding<Bool>) -> some View {
        Toggle(label, isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.small).tint(accent)
    }

    private func permission(_ key: String, _ granted: Bool, _ request: @escaping () -> Void) -> some View {
        row {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(granted ? accent : .secondary)
            Text(L10n.text(key))
            Spacer()
            if !granted { Button(L10n.text("allow"), action: request) }
        }
    }
}

/// Resting fingers are grey, a tapping finger is a ring, a pressing finger is solid.
private struct GestureGlyph: View {
    let gesture: Gesture

    private enum Finger { case rest, tap, press }

    private var fingers: [Finger] {
        switch gesture {
        case .middleTap: [.rest, .tap, .rest]
        case .threePress: [.press, .press, .press]
        case .fourPress: [.press, .press, .press, .press]
        }
    }

    var body: some View {
        let fingers = fingers
        HStack(spacing: 3) {
            ForEach(fingers.indices, id: \.self) { index in
                dot(fingers[index])
                    .frame(width: 9, height: 9)
                    .offset(y: index == 0 || index == fingers.count - 1 ? 2 : -2)
            }
        }
        .frame(width: 46, alignment: .leading)
        .accessibilityHidden(true)
    }

    @ViewBuilder private func dot(_ finger: Finger) -> some View {
        switch finger {
        case .rest: Circle().fill(.secondary.opacity(0.4))
        case .tap: Circle().strokeBorder(accent, lineWidth: 1.6)
        case .press: Circle().fill(accent)
        }
    }
}

private struct TouchPreview: View {
    @ObservedObject var feed: TouchFeed
    let placeholder: String

    var body: some View {
        let contacts = feed.snapshot.contacts
        GeometryReader { geometry in
            // Contacts keep the trackpad's own proportions inside the wider panel.
            let height = geometry.size.height - 20
            let width = min(geometry.size.width - 20, height * 1.6)
            let left = (geometry.size.width - width) / 2
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.primary.opacity(feed.snapshot.buttonDown ? 0.1 : 0.045))
                ForEach(contacts.indices, id: \.self) { index in
                    Circle().fill(accent).frame(width: 18, height: 18)
                        .position(x: left + contacts[index].x * width, y: 10 + (1 - contacts[index].y) * height)
                }
                if let gesture = feed.recognized {
                    Text(L10n.text("action." + gesture.rawValue))
                        .font(.system(size: 26, weight: .semibold)).foregroundStyle(accent)
                        .transition(.opacity)
                } else if contacts.isEmpty {
                    Text(placeholder).foregroundStyle(.tertiary)
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: feed.recognized)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.text("preview.ax", contacts.count))
    }
}
