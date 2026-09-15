# 指间 · FingerChord

仅供本机 macOS 27 使用的触摸板手势工具，原生 Swift / AppKit / SwiftUI，无第三方运行时依赖。

## 手势

- 食指、无名指保持在触摸板上，在两者之间轻点中指：在当前光标处发送 ⌘ + 左键点击。
- 三指接触时实际压下触摸板：发送 ⌘W。
- 四指接触时实际压下触摸板：发送 ⌘Q。

系统提供的是触点位置，无法识别手指名称；第一个手势按“两侧触点保持稳定，中间新增触点轻触后抬起”识别。

## App 行为

首次运行打开设置并引导系统授权。关闭设置后继续后台运行，没有 Dock 图标或菜单栏图标。再次打开 App 显示设置。各手势开关即时生效并保存在本地。登录时启动使用系统 ServiceManagement 接口，默认关闭。

## 使用

1. 打开 `/Applications/FingerChord.app`（显示名称“指间”）。
2. 在设置中分别点“去授权”，前往 **系统设置 → 隐私与安全性 → 辅助功能 / 输入监控**，允许“指间”。系统列表有时显示为 `FingerChord`。
3. 如 macOS 提示退出并重新打开，请允许；再次打开 App 即可。状态变成“正在后台运行”后可使用手势。
4. 勾选“测试模式”可以观察手势结果，此时不会发送点击、关闭窗口或退出应用。实时触摸板会显示手指位置和实际压下状态。
5. 点击“隐藏并运行”或直接关窗口。再次双击 App 打开设置；“退出指间”完全停止程序。

第一种手势需要两侧手指先稳定约 80 ms，中指在两者之间轻触 25–260 ms 后抬起。移动或添加第四个触点会取消这次轻点。抬起所有手指后可以重新尝试；成功后两侧手指可以继续保持接触，重复轻点中指。

三指和四指手势只响应物理按下；系统的“轻点来点按”不会触发 ⌘W / ⌘Q。按住不重复触发。快捷键发给当前应用，⌘ 点击发生在当前光标位置。三指／四指开关开启时，普通鼠标按下会最多延后 25 ms，以对齐系统点击和触摸板原始帧；原有点击随后原样转发。系统的三指拖移、四指滑动等设置不会被修改。

## 开机自启动

在 App 设置中开启“开机自启动”，通过 `SMAppService.mainApp` 注册登录启动。如果显示需要系统批准，点“打开登录项”。关闭该开关即可取消。登录启动时已授权的 App 会隐藏运行；“暂停”状态也会保留。

## 开发

要求本机 Xcode（含 Swift 6.2+）及代码签名证书，无网络依赖：

```sh
./scripts/test.sh       # 33 项手势状态机及点击配对测试
./scripts/build.sh      # 构建、签名 dist/FingerChord.app
./scripts/install.sh    # 构建、安装 /Applications/FingerChord.app 并打开设置
```

安装新构建前先退出旧 App。构建脚本自动选择本机 Developer ID / Apple Development 证书，也可以设置 `FINGERCHORD_SIGN_IDENTITY`。持续使用相同的 bundle ID、安装路径和签名身份，使系统授权在重新构建后保持稳定。产物只供本机运行，未进行公证和 App Store 分发。

项目使用 Swift Package Manager，Xcode 可直接打开 `Package.swift`。

## 诊断

```sh
/Applications/FingerChord.app/Contents/MacOS/FingerChord --probe
/Applications/FingerChord.app/Contents/MacOS/FingerChord --probe --observe
/Applications/FingerChord.app/Contents/MacOS/FingerChord --self-test-events
/Applications/FingerChord.app/Contents/MacOS/FingerChord --self-test-login
```

- `--probe`：检查系统、权限、设备连接；`--observe` 延长到 15 秒，输出接收到的触点帧数和物理按键变化次数。
- `--self-test-events`：在已解锁并授权的环境中验证 ⌘ 点击、⌘W、⌘Q 的六个合成事件。测试 event tap 会吸收测试事件，避免送到其他 App。
- `--self-test-login`：在当前未开启登录启动时，实际注册再注销系统登录项，最后恢复关闭状态；已有登录启动设置时跳过。
- 离屏界面检查：`FingerChord --render-settings /absolute/path/settings.png`。
- 设置保存在 `local.heruoxin.FingerChord` 的 UserDefaults 域；单实例锁在 `~/Library/Application Support/FingerChord/instance.lock`。不记录键盘内容，不进行网络请求。

重连设备、睡眠唤醒和用户会话恢复会重新建立监听。授权刚开启但未收到触点时，可点“重新连接”，或退出重开。

## 实现依据

- 系统 MultitouchSupport 私有框架提供触点帧，运行时加载并检查接口；仅面向当前系统，不承诺后续版本兼容。
- 触点 ABI 参考 [OpenMultitouchSupport](https://github.com/Kyome22/OpenMultitouchSupport/blob/main/Framework/OpenMultitouchSupportXCF/OpenMTInternal.h) 和 [Hammerspoon touchdevice](https://github.com/asmagill/hs._asm.undocumented.touchdevice/blob/master/MultitouchSupport.h) 的接口声明；手势识别与 App 实现独立编写。
- CoreGraphics event tap 拦截点击、发送合成事件；ServiceManagement 管理登录启动。

## 开发记录

- 2026-09-15：确认 macOS 27.0 (26A428)、Swift 6.4、内置 Apple Force Touch 触摸板和所需 MultitouchSupport 符号可用；初始化 Git。
- 已通过 33 项自动化状态机测试、Release 构建、签名校验、内置触摸板启动及连接检查、设置页面离屏渲染检查；后台进程激活策略为 accessory（无 Dock）。系统登录项实际注册／注销测试通过（enabled → notRegistered），测试后保持关闭。
- 当前实机验收限制：Mac 锁定且输入监控未授权，无法获取用户真实手指帧或完成快捷键的全流程验证。解锁并授权后，使用设置中的测试模式逐个验收三个手势。设置窗口的真实交互及重新登录启动行为尚需实机验证。
