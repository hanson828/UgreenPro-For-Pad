# UgreenPro-For-Pad · 绿联云平板端

把一个安卓平板变成绿联云（UGOS Pro）的「原生」客户端：里面是绿联云自己的网页端，
外面补上平板浏览器做不到的登录记忆、应用锁、指纹解锁、上传和下载。

不是官方客户端，也不含绿联的任何代码或资源 —— 它只是用一个 WebView 打开**你自己的** NAS。

---

## 这个项目解决什么问题

绿联云网页端本身是完整的，但在平板上直接开浏览器有这么几个坑：

| 问题 | 这里的做法 |
| --- | --- |
| 网页按手机版布局排，桌面工作台挤成一团 | 伪装 Windows 桌面 Chrome UA + 虚拟视口（0.8 缩放后等比放大），让 UGOS 走桌面布局 |
| 每次都要输一长串 `ip:端口` 或 UGREENlink ID | 重设计的登录页，自动补 `http://…:9999` / `https://…:9443`，最多记住 8 个账号并自动登录 |
| 浏览器不保存 NAS 密码，也不该存明文 | 账号密码走 Android Keystore 加密存储（`flutter_secure_storage`），明文不落盘、不出设备 |
| 平板借人用，怕被翻照片 | 应用锁：4-6 位数字密码或九点图形密码，可选指纹；后台超过 1 分钟回来重新上锁 |
| 文件管理只在右键菜单里给「上传」，触屏没有右键 | 注入脚本合成 contextmenu，走网页自己的上传流程，再交给系统文件选择器 |
| 网页下载点了没反应 / 文件找不到 | 接管 WebView 下载，落盘到「下载/Ugreen_Pro_For_Pad」，带进度、打开、删除 |

## 功能一览

- **登录页**：局域网（IP / 域名 / 自定义端口）与 UGREENlink（`https://ug.link/<ID>`）两种连接方式；地址会做校验和规范化；账号列表可切换、删除。
- **自动登录**：记住密码后下次进 App 自动填表并提交；网页端会话失效时可从菜单里「清除会话并自动登录」。
- **桌面布局**：固定桌面 UA；启动即注入脚本覆盖 `screen`/视口尺寸，避免网页按真实分辨率重排导致的闪屏。
- **横屏 + 沉浸式**：锁定横屏，状态栏/导航栏可隐藏（下滑临时唤出），适合当平板上的「NAS 桌面」。
- **应用锁**：数字密码（4-6 位）或图形密码（3x3 九点，至少 4 个点），二选一；随机盐 + HMAC-SHA256 8000 轮迭代后存 Keystore，定时安全比较。
- **指纹**：走原生 `FingerprintManager`，弹窗由 Flutter 自绘（系统 BiometricPrompt 的弹窗改不了样式）；指纹只做本地解锁，不参与 NAS 认证。
- **上传**：`UGShellBridge` 通道让网页上报结果；文件选择器优先 MIUI 文件管理器，失败回退 `ACTION_OPEN_DOCUMENT`，`content://` 取持久授权。
- **下载**：替换 `webview_flutter_android` 默认 DownloadListener（默认行为是对下载地址重新导航），自建下载队列，写入 MediaStore 的 Downloads。

## 构建

环境：Flutter 3.47.x stable（Dart `^3.13.2`）+ Android SDK，JDK 17。已在 Windows + Flutter 3.47.2 上验证。

```bash
flutter pub get
flutter test          # 26 个测试：地址解析、PIN 哈希、下载落盘、上传脚本
flutter analyze       # 目前零告警
flutter build apk --release
# 产物：build/app/outputs/flutter-apk/app-release.apk
```

说明几点：

- `pubspec.yaml` 里用 `dependency_overrides` 把 `path_provider_android` 钉在纯 Java 实现的 `2.2.23`：2.3.x 改用 JNI/CMake，需要完整 NDK 才能构建，而本项目在 Android 上并不使用 `path_provider` 的数据目录。
- release 构建目前**用 debug keystore 签名**（Flutter 模板默认行为）。要正式分发请自建 keystore 并配 `android/key.properties`，否则换签名后无法覆盖安装。
- 仓库里带了 Gradle wrapper，克隆后不需要 `flutter create` 重新生成。
- 项目名是 **UgreenPro-For-Pad**，但 Dart 包名（`ugreen_cloud_shell`）和 Android
  `applicationId`（`com.ugreencloud.ugreen_cloud_shell`）保持原样：Dart 包名不允许大写，
  改 `applicationId` 会变成另一个 App、和已发布 APK 的安装标识不再匹配。改名只影响仓库名与文档。

## 上手

1. 从 [Releases](../../releases) 下载最新 APK，装到平板上（首次安装需允许「安装未知来源应用」）。
2. 打开 App，选「局域网」填 NAS 的 IP（如 `192.168.31.70`，端口默认 9999；开了 HTTPS 用 9443）或选「UGREENlink」填 ID。
3. 输入绿联云账号密码登录；勾选「记住密码」/「自动登录」后，下次直接进桌面。
4. 右上角菜单里可以：复制当前地址、上传文件到当前文件夹、下载管理、重新加载、清除会话并自动登录、返回登录页。
5. 设置 → 安全 里可开启应用锁（数字/图形/指纹）。

## 目录结构

```
lib/
  main.dart                    入口：锁横屏、预加载应用锁状态、注入 AppLockGate
  models/saved_account.dart    已保存账号 / 上次会话的数据模型
  screens/
    login_screen.dart          重设计的登录页（局域网 / UGREENlink、账号记忆）
    browser_screen.dart        WebView 主界面：UA、虚拟视口、桥接、菜单、下载拦截
    downloads_screen.dart      下载进度 / 打开 / 删除
    lock_screen.dart           解锁页（数字、图形、指纹）
    security_settings_screen.dart  安全设置
    unlock_method_screen.dart  选择/修改解锁方式
    pattern_setup_screen.dart  图形密码录入
    secret_verify_screen.dart  修改密码前的旧密码校验
  services/
    address_resolver.dart      地址 → 可加载 URL 的解析与校验
    credential_store.dart      Keystore 加密的账号 / 会话存储
    app_lock_service.dart      应用锁状态机
    pin_hash.dart              盐 + HMAC-SHA256 迭代哈希、定时安全比较
    fingerprint_auth.dart      指纹通道封装
    download_manager.dart      下载队列、落盘、记录持久化
    file_picker_bridge.dart    网页 <input type="file"> → 原生选择器
    autofill_script.dart       登录页自动填充注入脚本
    upload_script.dart         合成右键菜单触发上传的注入脚本
  theme/, widgets/             主题、图标、密码盘、图形盘、指纹弹窗、锁屏闸门
android/app/src/main/kotlin/.../MainActivity.kt
                               原生侧：文件选择器、MediaStore 落盘、打开/删除文件、
                               指纹（EventChannel 推送）、沉浸式全屏
docs/ARCHITECTURE.md           桥接协议与几个关键取舍的说明
```

## 已知限制

- **只做安卓平板横屏**，手机竖屏、iPad、桌面端都没适配（`main.dart` 直接锁横屏）。
- **和绿联网页的 DOM 耦合**：上传靠合成右键菜单找「上传文件」项，自动填充靠找可见的账号/密码框。UGOS 改版可能让这两处失效，那时需要更新 `upload_script.dart` / `autofill_script.dart`。
- **允许明文 http**（`usesCleartextTraffic=true`），因为局域网 UGOS 默认就是 `http://ip:9999`。只在可信网络里用；外网走 UGREENlink（https）。
- 应用锁是**外层闸门**，不是系统级加密：能解锁设备并拿到 App 数据目录的人，仍可能读到 Keystore 保护的内容。
- 下载走 Dart 侧 HTTP 拉取，超大文件（数十 GB）没有断点续传。

## 免责声明

- 本项目**非官方**，与绿联科技（UGREEN）无任何关联，未获其授权或背书。
- 仓库不含、不分发绿联的代码、固件、图标或其它资源。「绿联」「UGREEN」「UGOS」等名称与商标归其权利人所有，此处仅用于说明用途。`assets/brand/ugreen_cloud_browser.png` 是本项目自绘的 NAS + 地球图标，不是厂商 logo。
- 本项目的部分功能（伪装 UA、覆盖视口尺寸、合成右键菜单、脚本注入）会改变绿联网页端的默认行为。**请只对你拥有或已获授权使用的 NAS 与账号这样做**，并自行确认是否符合绿联的服务条款与当地法律法规。
- 凭据只保存在本机 Keystore，不会上传到任何第三方服务器；但请自行评估在你的设备上保存 NAS 密码的风险。
- 软件按「现状」提供，不附带任何担保，使用风险自负。

## English

UgreenPro-For-Pad is a small Android tablet shell for the UGREEN NAS (UGOS Pro) web UI. It
wraps the vendor's own web app in a WebView and adds what a tablet browser can't do well: a
screen with per-NAS account memory (Android Keystore encrypted), a desktop-Chrome UA plus a
virtual viewport so UGOS renders its desktop layout, an app lock (PIN / pattern / fingerprint),
a synthesized context-menu bridge so uploading works without a right click, and a download
manager that saves into `Download/Ugreen_Pro_For_Pad`. Landscape-only, Android only. Not
affiliated with UGREEN; no vendor code or assets are included. Build with
`flutter pub get && flutter build apk --release`.

## License

MIT，见 [LICENSE](LICENSE)。
