# 桥接协议与关键取舍

这份文档说明外层壳是怎么和绿联网页打交道的，方便改 UA、改注入脚本或换网页版本时定位。

## 层次

```
Flutter (lib/)
 ├─ LoginScreen        地址解析 + Keystore 取凭据
 ├─ BrowserScreen      WebViewController：UA、视口、JS 桥、下载拦截、菜单
 └─ AppLockGate        包在 MaterialApp.builder 外面，盖住整个导航栈
        │  MethodChannel / EventChannel / JavaScriptChannel
Android (MainActivity.kt)
 └─ 文件选择器、MediaStore 落盘、打开/删除文件、FingerprintManager、沉浸式全屏
```

## 通道一览

| 通道 | 类型 | 方向 | 用途 |
| --- | --- | --- | --- |
| `ugreen_shell/file_picker` | Method | Dart → 原生 | `pickFiles`：网页 `<input type="file">` 触发时打开系统选择器 |
| `ugreen_shell/immersive` | Method | Dart → 原生 | `setImmersive`：隐藏/显示状态栏与导航栏 |
| `ugreen_shell/fingerprint` | Method | Dart → 原生 | `status` / `start` / `cancel` / `openEnroll` |
| `ugreen_shell/fingerprint_events` | Event | 原生 → Dart | 指纹结果：`success` / `failed` / `help` / `error` |
| `ugreen_shell/files` | Method | Dart → 原生 | `saveToDownloads` / `openFile` / `deleteFile` |
| `UGShellBridge` | JavaScriptChannel | 网页 → Dart | 注入脚本回传 JSON |

`UGShellBridge` 的消息都是 `{"type": ..., ...}`：

- `{"type":"autofill","status":"filled"|"failed"|...,"reason":...}` —— 自动填充结果；`filled` 之后停止重试。
- `{"type":"upload","status":"ok"|...,"reason":"no_list"|"no_menu"|"no_submenu"}` —— 上传入口脚本的进度；Dart 侧翻成中文提示。
- `{"type":"header","height":N}` —— 网页上报顶部区域高度，用来对齐原生悬浮按钮的位置。

## 桌面布局：UA + 虚拟视口

绿联云网页按 UA 和视口宽度决定给桌面版还是平板版。做法是两层配合：

1. `setUserAgent()` 固定 Windows 桌面 Chrome UA —— 网页据此返回桌面工作台。
2. 在 `onPageStarted` 之前注入 `_buildEarlyScreenScript()`：用 `0.8` 的比例伪造更宽的
   `screen.width/height`、`devicePixelRatio` 与视口尺寸，再由 WebView 把结果等比放大。
   脚本只在 `window.__ugShellScreen` 未设置时执行，避免重复覆盖。

必须**尽早**注入：如果等网页先按真实分辨率排好版再改，图标会先大后小地闪一下。

同时关掉了 `enableZoom`、滚动条与过滚动（`setOverScrollMode(never)`），减少长列表里的重绘。

## 下载：替换默认 DownloadListener

`webview_flutter_android` 的默认实现对下载地址是「重新导航」，在壳里会变成空白页。这里用
pigeon 覆盖接口把 `downloadListener_new` 换成自己的回调，拿到
`url / userAgent / contentDisposition / mimetype / contentLength` 后交给
`DownloadManager.start()`：

- Dart 侧 `HttpClient` 拉流，边写临时文件边通过 `ChangeNotifier` 推进度；
- 下载完成调用原生 `saveToDownloads`，API 29+ 走 MediaStore 写
  `Download/Ugreen_Pro_For_Pad`，低版本直接写外部存储目录并自动改名去重；
- 记录（最多 60 条）存在 `flutter_secure_storage` 里，重开 App 还能看到历史和已下载文件。

## 上传：合成右键菜单

UGOS 的文件管理只在**列表空白处右键**菜单里给「上传到 / 上传文件」，触屏够不着。注入脚本
（`upload_script.dart`）的做法是复刻这条链路，而不是自己造上传请求：

1. 在顶层页面和所有同源 iframe 里找到文件列表容器；
2. 派发合成的 `contextmenu` 事件打开菜单 → `mouseover` 展开子菜单 → 点「上传文件」；
3. 网页自己创建 `<input type="file">` 并弹对话框，此时 `setOnShowFileSelector` 接管，
   打开系统选择器（MIUI 上优先系统文件管理器，回退 `ACTION_OPEN_DOCUMENT`）；
4. 选完文件后由网页走它原来的上传逻辑，服务端行为与浏览器完全一致。

脚本有防重入标记 `window.__ugUploading`，并在每个失败点回传错误码（`no_list` / `no_menu` /
`no_submenu`）。

## 自动填充

`autofill_script.dart` 在页面里找可见的账号框与密码框，用 **原生 setter**
（`HTMLInputElement.prototype.value` 的 descriptor）赋值再派发 `input`/`change`，这样 React /
Vue / Angular 的受控输入也会接收到值；随后按需点击登录按钮。只在收到 `filled` 之前重试，
避免和用户手动输入打架。

密码从 Dart 侧拼进脚本字符串执行 —— 只存在内存里，落盘的一直是 Keystore 加密的密文。

## 安全模型

- **账号密码**：`flutter_secure_storage`（`encryptedSharedPreferences: true`，Android Keystore
  派生密钥），最多 8 条，明文不落盘、不出设备。
- **应用锁**：数字密码（4-6 位）或图形密码（九点、至少 4 点）二选一，`随机 16 字节盐 +
  HMAC-SHA256 迭代 8000 次`，只存盐和摘要；比较用定时安全写法（`constantTimeEquals`）。
- **指纹**：只作为本地解锁的一种方式，验证通过即放行应用锁，不参与 NAS 认证。
- **TLS**：局域网 NAS 常是自签证书。`onSslAuthError` 弹原生对话框让用户**确认**后再
  `proceed()`，不会静默接受；`usesCleartextTraffic` 打开是为了 `http://ip:9999`。
- **应用锁是外层闸门**，不是系统级加密：拿到设备并解开系统锁的人仍可能访问 App 数据目录。

## 测试

`test/` 下覆盖可以脱离设备跑的部分：

- `address_resolver_test.dart`：局域网/UGREENlink 的补全、规范化与拒绝规则；
- `pin_hash_test.dart`：PIN/图形密码规则、哈希稳定性、盐随机性、安全比较；
- `download_manager_test.dart`：本地 HTTP 服务真实下载落盘（注入落盘实现，不碰平台通道）；
- `upload_flow_test.dart`：MIME 归一化与注入脚本的文案/错误码契约；
- `widget_test.dart`：登录页首屏。

涉及 WebView、指纹、MediaStore 的部分只能真机验证。
