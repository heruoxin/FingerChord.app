# 指间 · FingerChord

仅供本机 macOS 27 使用的触摸板手势工具，原生 Swift / AppKit / SwiftUI，无第三方运行时依赖。

## 手势

- 食指、无名指保持在触摸板上，在两者之间轻点中指：在当前光标处发送 ⌘ + 左键点击。
- 三指接触时实际压下触摸板：发送 ⌘W。
- 四指接触时实际压下触摸板：发送 ⌘Q。

系统提供的是触点位置，无法识别手指名称；第一个手势按“两侧触点保持稳定，中间新增触点轻触后抬起”识别。

## App 行为

首次运行打开设置并引导系统授权。关闭设置后继续后台运行，没有 Dock 图标或菜单栏图标。再次打开 App 显示设置。各手势开关即时生效并保存在本地。登录时启动使用系统 ServiceManagement 接口。

## 开发

构建、安装、验证说明随实现补充。项目不修改系统触摸板偏好设置。

## 实现依据

- 系统 MultitouchSupport 私有框架提供触点帧，运行时加载并检查接口；仅面向当前系统，不承诺后续版本兼容。
- 触点 ABI 参考 [OpenMultitouchSupport](https://github.com/Kyome22/OpenMultitouchSupport/blob/main/Framework/OpenMultitouchSupportXCF/OpenMTInternal.h) 和 [Hammerspoon touchdevice](https://github.com/asmagill/hs._asm.undocumented.touchdevice/blob/master/MultitouchSupport.h) 的接口声明；手势识别与 App 实现独立编写。
- CoreGraphics event tap 拦截点击、发送合成事件；ServiceManagement 管理登录启动。

## 开发记录

- 2026-09-15：确认 macOS 27.0 (26A428)、Swift 6.4、内置 Apple Force Touch 触摸板和所需 MultitouchSupport 符号可用；初始化 Git。
