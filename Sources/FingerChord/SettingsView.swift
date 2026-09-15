import SwiftUI
import GestureCore

private let accent = Color(red: 0.12, green: 0.43, blue: 0.40)

struct SettingsView: View {
    @ObservedObject var model: AppModel
    var hide: () -> Void
    var quit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "hand.draw.fill")
                    .font(.system(size: 29, weight: .medium))
                    .foregroundStyle(accent)
                    .frame(width: 58, height: 58)
                    .background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 4) {
                    Text("指间").font(.system(size: 27, weight: .semibold))
                    Text("三个手势，留在指尖。")
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
                    Text("允许以下权限后，手势会自动开始工作。")
                        .font(.system(size: 12, weight: .medium))
                    HStack(spacing: 12) {
                        permission("辅助功能", granted: model.accessibility, action: model.requestAccessibility)
                        permission("输入监控", granted: model.inputMonitoring, action: model.requestInputMonitoring)
                    }
                    Text("在系统设置里打开“指间”的开关。如系统要求退出并重新打开，请照常操作。")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            }

            VStack(alignment: .leading, spacing: 9) {
                sectionTitle("手势")
                VStack(spacing: 0) {
                    gestureRow(symbol: "hand.point.up.left", title: "轻点中指", detail: "食指、无名指保持接触，轻点两指之间的中指", shortcut: "⌘ 点击", enabled: $model.middleTap)
                    Divider().padding(.leading, 50)
                    gestureRow(symbol: "hand.tap", title: "三指按下", detail: "三指接触时，实际压下触摸板", shortcut: "⌘ W", enabled: $model.threePress)
                    Divider().padding(.leading, 50)
                    gestureRow(symbol: "hand.raised", title: "四指按下", detail: "四指接触时，实际压下触摸板", shortcut: "⌘ Q", enabled: $model.fourPress)
                }.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            }

            HStack(alignment: .top, spacing: 16) {
                TouchPreview(contacts: model.snapshot.contacts, pressed: model.snapshot.buttonDown)
                    .frame(width: 192, height: 119)
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("试试手势").font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Text("\(model.snapshot.contacts.count) 个触点")
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    Toggle("测试模式：只显示识别结果", isOn: $model.testMode)
                        .font(.system(size: 11)).toggleStyle(.checkbox)
                    Text(model.lastAction)
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(accent)
                        .lineLimit(2).frame(height: 30, alignment: .topLeading)
                        .accessibilityIdentifier("lastAction")
                    Text("隐藏设置后自动结束测试模式。")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }.padding(.vertical, 4)
            }

            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("开机自启动").font(.system(size: 12, weight: .medium))
                        Text("登录 Mac 后自动在后台运行")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("开机自启动", isOn: Binding(get: { model.loginEnabled }, set: { model.setLoginEnabled($0) }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                        .accessibilityLabel("开机自启动")
                }
                if model.loginNeedsApproval {
                    HStack { Text("请在系统登录项中允许指间运行。").font(.system(size: 11)); Spacer(); Button("打开登录项", action: model.openLoginSettings) }
                }
                if let error = model.loginError { Text(error).font(.system(size: 11)).foregroundStyle(.red) }
            }.padding(14).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))

            Divider()
            HStack {
                Button("退出指间", action: quit).buttonStyle(.plain).foregroundStyle(.secondary)
                Button("重新连接", action: model.reconnect).buttonStyle(.plain).foregroundStyle(.secondary).padding(.leading, 8)
                Spacer()
                Button(model.enabled ? "暂停" : "开始运行") { model.enabled.toggle() }
                    .buttonStyle(.bordered)
                Button("隐藏并运行") { model.enabled = true; hide() }
                    .buttonStyle(.borderedProminent).tint(accent)
                    .disabled(!model.running)
            }.font(.system(size: 12))
            Text("关闭窗口后继续运行 · 再次打开 App 返回设置 · 无 Dock 或菜单栏图标")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(26)
        .frame(width: 620)
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
            if !granted { Button("去授权", action: action).controlSize(.small).accessibilityLabel("授权\(name)") }
        }.frame(maxWidth: .infinity)
    }

    private func gestureRow(symbol: String, title: String, detail: String, shortcut: String, enabled: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 21)).foregroundStyle(accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            Text(shortcut).font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary).frame(width: 59)
                .padding(.vertical, 5).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 5))
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
                        Text("实时触摸板").font(.system(size: 10))
                    }.foregroundStyle(accent.opacity(0.55))
                }
                // Enumerated ids avoid collisions between two connected trackpads.
                ForEach(Array(contacts.enumerated()), id: \.offset) { _, contact in
                    Circle().fill(accent.opacity(0.85)).frame(width: 13, height: 13)
                        .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 2))
                        .position(x: 10 + contact.x * (geometry.size.width - 20),
                                  y: 10 + (1 - contact.y) * (geometry.size.height - 20))
                }
            }
        }.accessibilityLabel("触摸板，\(contacts.count) 个触点\(pressed ? "，已按下" : "")")
    }
}
