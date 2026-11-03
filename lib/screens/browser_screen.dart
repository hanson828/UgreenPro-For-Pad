import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
// ignore: implementation_imports
import 'package:webview_flutter_android/src/android_webkit.g.dart' as aw;
import '../services/autofill_script.dart';
import '../services/download_manager.dart';
import '../services/file_picker_bridge.dart';
import '../services/upload_script.dart';
import '../theme/app_theme.dart';
import 'downloads_screen.dart';

/// 固定使用 Windows 桌面 Chrome 的 UA，让绿联云网页端返回 PC 布局。
const _desktopUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36';

/// 虚拟屏幕分辨率相对物理屏幕的比例：网页按更高分辨率布局，再由 WebView 等比缩放到屏幕。
const double _virtualScale = 0.8;

/// 页面一开始就屏蔽真实屏幕分辨率，改用虚拟尺寸，避免网页按真实分辨率重新适配造成闪屏。
/// 虚拟尺寸（更宽的 CSS 视口 + 0.8 缩放）是 UGOS 桌面按桌面布局排布图标/窗口的前提，
/// 一旦丢失，图标会按平板宽度重排、变得又大又稀。
String _buildEarlyScreenScript(double screenWidth, double screenHeight) {
  final width = (screenWidth / _virtualScale).round();
  final height = (screenHeight / _virtualScale).round();
  return '''
(function () {
  if (window.__ugShellScreen) { return; }
  window.__ugShellScreen = true;
  var vw = $width;
  var vh = $height;
  var scale = $_virtualScale;
  function override(target, name, value) {
    try {
      Object.defineProperty(target, name, {
        get: function () { return value; },
        configurable: true
      });
    } catch (e) {}
  }
  try {
    override(window.screen, 'width', vw);
    override(window.screen, 'height', vh);
    override(window.screen, 'availWidth', vw);
    override(window.screen, 'availHeight', vh);
    override(window, 'outerWidth', vw);
    override(window, 'outerHeight', vh);
  } catch (e) {}
  var content = 'width=' + vw + ', initial-scale=' + scale +
    ', minimum-scale=' + scale + ', maximum-scale=' + scale +
    ', user-scalable=no';
  // 强制锁定所有 viewport meta：网页自带的 meta 稍后解析出来时会覆盖我们注入的，
  // 这里把全部 meta 统一改写，防止页面加载完成后弹回原始比例。
  function enforceMeta() {
    try {
      if (!document.documentElement) { return false; }
      var metas = document.querySelectorAll('meta[name="viewport"]');
      if (metas.length === 0) {
        if (!document.head) { return false; }
        var created = document.createElement('meta');
        created.setAttribute('name', 'viewport');
        created.setAttribute('content', content);
        document.head.appendChild(created);
        return true;
      }
      for (var i = 0; i < metas.length; i++) {
        if (metas[i].getAttribute('content') !== content) {
          metas[i].setAttribute('content', content);
        }
      }
      return true;
    } catch (e) {
      return false;
    }
  }
  var watcher = null;
  function startWatcher() {
    if (watcher || !document.documentElement) { return; }
    try {
      watcher = new MutationObserver(function () { enforceMeta(); });
      watcher.observe(document.documentElement, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ['content']
      });
    } catch (e) {}
  }
  var tries = 0;
  var timer = setInterval(function () {
    tries++;
    enforceMeta();
    startWatcher();
    if (tries > 100) { clearInterval(timer); }
  }, 30);
})();
''';
}

/// 探测网页顶部状态栏的实际高度（CSS 像素），供悬浮条自适应等高。
String _buildHeaderProbeScript() => '''
(function () {
  try {
    var root = document.documentElement;
    if (!root) { return; }
    var width = root.clientWidth || window.innerWidth || 0;
    var probeX = Math.round((window.innerWidth || width) / 2);
    var el = document.elementFromPoint(probeX, 6);
    var height = 0;
    while (el && el !== document.body && el !== root) {
      var w = el.offsetWidth;
      var h = el.offsetHeight;
      if (w >= width * 0.55 && h >= 26 && h <= 140 && h > height) {
        height = h;
      }
      el = el.parentElement;
    }
    if (height > 0 && typeof UGHShellBridge !== 'undefined') {
      UGHShellBridge.postMessage(
        JSON.stringify({ type: 'header', height: height })
      );
    }
  } catch (e) {}
})();
''';

/// 原生沉浸模式通道，用于连同底部手势小白条一起隐藏。
const _immersiveChannel = MethodChannel('ugreen_shell/immersive');

/// UGOS 网页端的窗口拖动依赖它自己的「触摸→鼠标事件」模拟：前端在 touchstart /
/// touchmove / touchend 里用 Event 造出 mousedown / mousemove / mouseup 再派发，
/// 但只复制了坐标（clientX/clientY/pageX/screenX 等），没有 buttons；而窗口拖动
/// 逻辑第一句就是「buttons 不等于 1 就结束拖动」。结果手指一动拖动就被自己结束，
/// 表现为「拖一小段就拖不动」。
///
/// 这里只补这个缺口：在每个同源 frame 的捕获阶段给这类合成事件补上 buttons /
/// button，让绿联云自带的触摸拖动恢复正常。不要再另外合成一套拖拽——两套同时跑
/// 会互相打断，反而更糟（已实测）。
String _buildTouchShimScript() => r'''
(function () {
  if (window.__ugMouseFix) { return; }
  window.__ugMouseFix = true;

  // 只处理没有 buttons 的事件（绿联云合成的）；真实鼠标事件一定带 buttons。
  function patch(target, type, buttons) {
    try {
      target.addEventListener(type, function (e) {
        if (e.buttons === undefined) {
          try {
            e.buttons = buttons;
          } catch (err) {
            try { Object.defineProperty(e, 'buttons', { value: buttons }); } catch (e2) {}
          }
        }
        if (e.button === undefined) {
          try {
            e.button = 0;
          } catch (err) {
            try { Object.defineProperty(e, 'button', { value: 0 }); } catch (e2) {}
          }
        }
      }, true);
    } catch (e) {}
  }

  function install(doc) {
    if (!doc || doc.__ugMouseFix || !doc.addEventListener) { return; }
    doc.__ugMouseFix = true;
    patch(doc, 'mousedown', 1);
    patch(doc, 'mousemove', 1);
    patch(doc, 'mouseup', 0);
  }

  function installAll(root) {
    install(root);
    var frames = root.querySelectorAll('iframe');
    for (var i = 0; i < frames.length; i++) {
      try {
        var d = frames[i].contentDocument;
        if (d) { installAll(d); }
      } catch (e) {}
    }
  }

  installAll(document);
  // UGOS 的窗口（iframe）是动态创建的，定时补装进新 frame。
  setInterval(function () {
    try { installAll(document); } catch (e) {}
  }, 1500);
})();
''';

/// 绿联云平板网页端。负责加载 UGOS Pro 页面、自动登录与基础浏览控制。
class BrowserScreen extends StatefulWidget {
  const BrowserScreen({
    super.key,
    required this.url,
    required this.addressLabel,
    required this.account,
    required this.password,
    required this.autoLogin,
  });

  final String url;
  final String addressLabel;
  final String account;
  final String? password;
  final bool autoLogin;

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

enum _MenuAction { copyUrl, upload, downloads, reload, relogin, exit }

class _BrowserScreenState extends State<BrowserScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final WebViewController _controller;
  late final AnimationController _islandCtrl;

  int _progress = 0;
  bool _loading = true;
  String? _error;
  String _pageTitle = '';
  String? _currentUrl;
  bool _canGoBack = false;

  Timer? _fillTimer;
  bool _fillRunning = false;
  bool _autoFillLocked = false;
  int _noFormCount = 0;
  bool _tipShown = false;

  bool _sslTrusted = false;
  bool _sslDialogOpen = false;
  bool _closing = false;

  double _headerBarHeight = 44;
  bool _pageRevealed = false;
  final Map<String, DownloadStatus> _lastDownloadStatus =
      <String, DownloadStatus>{};


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 必须在创建导航代理之前接管 DownloadListener，把网页下载转交下载管理器。
    _installDownloadInterceptor();
    DownloadManager.instance.addListener(_onDownloadsChanged);
    _enterImmersive();
    _islandCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      value: 0,
    );
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.canvasTop)
      ..setUserAgent(_desktopUserAgent)
      ..addJavaScriptChannel(
        'UGShellBridge',
        onMessageReceived: _onJsMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: _onProgress,
          onPageStarted: _onPageStarted,
          onPageFinished: _onPageFinished,
          onWebResourceError: _onResourceError,
          onUrlChange: _onUrlChange,
          onSslAuthError: _onSslAuthError,
        ),
      );

    // 允许网页应用 viewport，并关闭网页自身的缩放能力。
    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      // 临时调试开关：仅 --dart-define=DEV_WEBVIEW_DEBUG=true 时打开远程调试。
      if (const bool.fromEnvironment('DEV_WEBVIEW_DEBUG')) {
        unawaited(AndroidWebViewController.enableDebugging(true));
      }
      unawaited(platform.setUseWideViewPort(true));
      unawaited(platform.enableZoom(false));
      // 关掉边缘回弹与滚动条：这两样在长列表/大窗口里每帧都要额外绘制与合成，
      // 关掉后滚动更稳，也不会再出现拉到边缘的橡皮筋效果。
      unawaited(platform.setOverScrollMode(WebViewOverScrollMode.never));
      unawaited(platform.setVerticalScrollBarEnabled(false));
      unawaited(platform.setHorizontalScrollBarEnabled(false));
      // 接管网页的 <input type="file">：绿联云「上传」最终就是靠它选文件，
      // 不接管的话点下去没有任何反应（默认不弹选择器）。
      unawaited(platform.setOnShowFileSelector(_onShowFileSelector));
    }
    unawaited(_controller.loadRequest(Uri.parse(widget.url)));
  }

  @override
  void dispose() {
    _fillTimer?.cancel();
    _islandCtrl.dispose();
    WidgetsBinding.instance.removeObserver(this);
    DownloadManager.instance.removeListener(_onDownloadsChanged);
    _exitImmersive();
    super.dispose();
  }

  /// 网页请求选择文件时回调（绿联云「上传文件」的最后一步就是它）。
  /// 不实现这个回调，网页点「确定」之后什么都不会发生。
  Future<List<String>> _onShowFileSelector(FileSelectorParams params) async {
    if (params.mode == FileSelectorMode.save) {
      // 「另存为」分支绿联云用不到，直接当作取消。
      return const <String>[];
    }
    final uris = await FilePickerBridge.pickFiles(
      multiple: params.mode == FileSelectorMode.openMultiple,
      mimeTypes: FilePickerBridge.normalizeMimeTypes(params.acceptTypes),
    );
    if (uris.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已选择 ${uris.length} 个文件，开始上传…'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
    return uris;
  }

  /// 平板没有右键，网页的上传菜单调不出来：注入脚本走同一条右键路径。
  Future<void> _startUpload() async {
    _collapseIsland();
    try {
      await _controller.runJavaScript(buildUploadScript());
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前页面还没加载完成，稍后再试')),
      );
    }
  }

  void _onUploadReported(Object? status, Object? reason) {
    if (!mounted || status == 'ok') {
      return;
    }
    final text = switch ('$reason') {
      'no_list' => '请先打开「文件管理」窗口，再点上传',
      'no_menu' => '没能调出网页的上传菜单，请重试',
      'no_submenu' => '没找到「上传文件」这一项，请重试',
      _ => '上传入口没打开，请重试',
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 3)),
    );
  }

  /// 用 pigeon 覆盖接口替换默认 DownloadListener（默认行为是对下载地址重新导航）。
  void _installDownloadInterceptor() {
    // ignore: invalid_use_of_visible_for_testing_member
    aw.PigeonOverrides.downloadListener_new = ({
      required void Function(
        aw.DownloadListener,
        String url,
        String userAgent,
        String contentDisposition,
        String mimetype,
        int contentLength,
      ) onDownloadStart,
    }) {
      return aw.DownloadListener.pigeon_new(
        // ignore: invalid_use_of_protected_member
        onDownloadStart: (
          _,
          String url,
          String userAgent,
          String contentDisposition,
          String mimetype,
          int contentLength,
        ) {
          _onNativeDownload(url, contentDisposition, mimetype, contentLength);
        },
      );
    };
  }

  void _onNativeDownload(
    String url,
    String contentDisposition,
    String mimeType,
    int contentLength,
  ) {
    unawaited(
      DownloadManager.instance.start(
        url: url,
        contentDisposition: contentDisposition,
        mimeType: mimeType,
        contentLength: contentLength,
      ),
    );
    if (!mounted) {
      return;
    }
    final name = DownloadManager.resolveFileName(url, contentDisposition);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('开始下载：$name'),
        action: SnackBarAction(
          label: '查看',
          onPressed: _openDownloads,
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _onDownloadsChanged() {
    if (!mounted) {
      return;
    }
    final manager = DownloadManager.instance;
    if (!manager.isLoaded) {
      return;
    }
    if (_lastDownloadStatus.isEmpty) {
      // 首次回调只记录基线，不为历史记录弹提示。
      for (final task in manager.tasks) {
        _lastDownloadStatus[task.id] = task.status;
      }
      return;
    }
    for (final task in manager.tasks) {
      final previous = _lastDownloadStatus[task.id];
      if (previous == task.status) {
        continue;
      }
      _lastDownloadStatus[task.id] = task.status;
      if (previous == null) {
        continue;
      }
      if (task.status == DownloadStatus.done &&
          previous == DownloadStatus.running) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('下载完成：${task.fileName}'),
            action: SnackBarAction(label: '查看', onPressed: _openDownloads),
            duration: const Duration(seconds: 3),
          ),
        );
      } else if (task.status == DownloadStatus.failed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('下载失败：${task.fileName}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
    _lastDownloadStatus.removeWhere(
      (id, _) => !manager.tasks.any((task) => task.id == id),
    );
  }

  void _openDownloads() {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const DownloadsScreen()),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _enterImmersive();
    }
  }

  void _enterImmersive() {
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
    unawaited(_invokeNativeImmersive(true));
  }

  void _exitImmersive() {
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      ),
    );
    unawaited(_invokeNativeImmersive(false));
  }

  Future<void> _invokeNativeImmersive(bool enabled) async {
    try {
      await _immersiveChannel.invokeMethod<void>('setImmersive', enabled);
    } catch (_) {
      // 非 Android 平台或通道不可用时忽略。
    }
  }

  void _onProgress(int value) {
    if (!mounted) {
      return;
    }
    // 进度回调可能十几次连续触发，每次都 setState 会连 WebView 平台视图一起重建。
    // 只在进度跨过 4%（或加载状态变化）时重建，视觉上无差别，重建次数少一个量级。
    final loadingNow = value < 100;
    if (loadingNow == _loading && value < 100 && (value - _progress).abs() < 4) {
      return;
    }
    setState(() {
      _progress = value;
      if (loadingNow) {
        _loading = true;
      }
    });
  }

  void _onPageStarted(String url) {
    _fillTimer?.cancel();
    _fillTimer = null;
    _fillRunning = false;
    _noFormCount = 0;
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = true;
      _progress = 0;
      _error = null;
      _currentUrl = url;
      _pageRevealed = false;
    });
    unawaited(_injectEarlyScreen());
  }

  /// 在页面开始加载时就写入虚拟分辨率与 viewport，避免首帧按真实分辨率渲染后再跳变。
  Future<void> _injectEarlyScreen() async {
    if (!mounted) {
      return;
    }
    final size = MediaQuery.sizeOf(context);
    try {
      await _controller.runJavaScript(
        _buildEarlyScreenScript(size.width, size.height),
      );
    } catch (_) {
      // 文档尚未创建时忽略，页面加载完成后还会再应用一次。
    }
  }

  void _onPageFinished(String url) {
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = false;
      _progress = 100;
      _currentUrl = url;
    });
    unawaited(_refreshNavigationState());
    unawaited(_injectTouchShim());
    unawaited(_revealPageWhenReady());
    _scheduleHeaderProbe();
    unawaited(_invokeNativeImmersive(true));
    if (widget.autoLogin && !_autoFillLocked) {
      _startAutoFill();
    }
  }

  /// 等虚拟分辨率应用完再显示网页，避免首帧按真实比例渲染后再跳变闪屏。
  Future<void> _revealPageWhenReady() async {
    await _applyVirtualScreen();
    await Future<void>.delayed(const Duration(milliseconds: 160));
    if (!mounted || _pageRevealed) {
      return;
    }
    setState(() => _pageRevealed = true);
  }

  /// 把屏幕虚拟成更高分辨率告知网页，网页按该尺寸布局后再缩放到物理屏幕。
  Future<void> _applyVirtualScreen() async {
    final size = MediaQuery.sizeOf(context);
    try {
      await _controller.runJavaScript(
        _buildEarlyScreenScript(size.width, size.height),
      );
    } catch (_) {
      // 页面跳转过程中注入失败时忽略，下次加载会重新应用。
    }
  }

  /// 读取网页顶部状态栏的高度，让悬浮条与之等高。
  Future<void> _probeHeaderBar() async {
    try {
      await _controller.runJavaScript(_buildHeaderProbeScript());
    } catch (_) {
      // 页面结构尚未就绪时忽略。
    }
  }

  void _scheduleHeaderProbe([int delayMs = 2500]) {
    unawaited(
      Future<void>.delayed(Duration(milliseconds: delayMs)).then((_) {
        if (mounted) {
          unawaited(_probeHeaderBar());
        }
      }),
    );
  }

  void _onHeaderMeasured(Object? rawHeight) {
    final cssHeight = rawHeight is num
        ? rawHeight.toDouble()
        : double.tryParse('${rawHeight ?? ''}');
    if (cssHeight == null || cssHeight <= 0) {
      return;
    }
    final height = (cssHeight * _virtualScale)
        .clamp(30.0, 64.0)
        .toDouble();
    if (!mounted || (height - _headerBarHeight).abs() < 1) {
      return;
    }
    setState(() => _headerBarHeight = height);
  }

  Future<void> _injectTouchShim() async {
    try {
      await _controller.runJavaScript(_buildTouchShimScript());
    } catch (_) {
      // 页面跳转过程中注入失败时忽略，下次加载会重新注入。
    }
  }

  void _expandIsland() {
    unawaited(
      _islandCtrl.animateTo(
        1,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _collapseIsland() {
    unawaited(
      _islandCtrl.animateTo(
        0,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  /// 动画进行中点击可反向打断：展开时立即缩回，收起时立即重新展开。
  /// 已展开时点击灵动岛空白处也会缩回，按钮仍保持各自功能。
  void _handleIslandTap() {
    if (_islandCtrl.isAnimating) {
      if (_islandCtrl.status == AnimationStatus.forward) {
        _collapseIsland();
      } else {
        _expandIsland();
      }
      return;
    }
    if (_islandCtrl.value >= 0.5) {
      _collapseIsland();
    } else {
      _expandIsland();
    }
  }

  /// 点击空白区域：展开中或已展开时收起，正在收起时改为展开。
  void _handleScrimTap() {
    if (_islandCtrl.status == AnimationStatus.reverse) {
      _expandIsland();
    } else {
      _collapseIsland();
    }
  }

  void _onIslandDragUpdate(DragUpdateDetails details) {
    _islandCtrl.value = (_islandCtrl.value + details.delta.dy / 96)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  void _onIslandDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity > 180) {
      _expandIsland();
    } else if (velocity < -180) {
      _collapseIsland();
    } else if (_islandCtrl.value > 0.35) {
      _expandIsland();
    } else {
      _collapseIsland();
    }
  }

  Future<void> _refreshNavigationState() async {
    try {
      final canGoBack = await _controller.canGoBack();
      final title = await _controller.getTitle();
      if (!mounted) {
        return;
      }
      setState(() {
        _canGoBack = canGoBack;
        final trimmed = title?.trim() ?? '';
        if (trimmed.isNotEmpty && trimmed != _pageTitle) {
          _pageTitle = trimmed;
        }
      });
    } catch (_) {
      // 页面尚未就绪时忽略。
    }
  }

  void _startAutoFill() {
    final password = widget.password;
    if (password == null || password.isEmpty || _autoFillLocked) {
      return;
    }
    _fillTimer?.cancel();
    _noFormCount = 0;
    _fillTimer = Timer.periodic(const Duration(milliseconds: 900), (timer) async {
      if (!mounted || _autoFillLocked) {
        timer.cancel();
        return;
      }
      if (_noFormCount >= 6 || _fillRunning) {
        return;
      }
      _fillRunning = true;
      try {
        await _controller.runJavaScript(
          buildAutoFillScript(
            account: widget.account,
            password: password,
            submit: true,
          ),
        );
      } catch (_) {
        // 页面正在跳转时注入会失败，等待下一次重试。
      } finally {
        _fillRunning = false;
      }
    });
  }

  void _onJsMessage(JavaScriptMessage message) {
    try {
      final decoded = jsonDecode(message.message);
      if (decoded is! Map) {
        return;
      }
      if (decoded['type'] == 'header') {
        _onHeaderMeasured(decoded['height']);
        return;
      }
      if (decoded['type'] == 'upload') {
        _onUploadReported(decoded['status'], decoded['reason']);
        return;
      }
      if (decoded['type'] != 'autofill') {
        return;
      }
      final status = decoded['status'];
      if (status == 'filled') {
        _autoFillLocked = true;
        _fillTimer?.cancel();
        _fillTimer = null;
        if (mounted && !_tipShown) {
          _tipShown = true;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('已自动填入账号密码，正在登录…'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        _scheduleHeaderProbe(3500);
      } else if (status == 'submitted' || status == 'submitted_enter') {
        _autoFillLocked = true;
        _fillTimer?.cancel();
        _fillTimer = null;
        _scheduleHeaderProbe(3500);
      } else if (status == 'already_filled') {
        _autoFillLocked = true;
        _fillTimer?.cancel();
        _fillTimer = null;
      } else if (status == 'no_form') {
        _noFormCount++;
        if (_noFormCount >= 6) {
          _fillTimer?.cancel();
          _fillTimer = null;
        }
      }
    } catch (_) {
      // 忽略非法消息。
    }
  }

  void _onResourceError(WebResourceError error) {
    if (error.isForMainFrame == false) {
      return;
    }
    final description = error.description.toLowerCase();
    if (description.contains('err_aborted') ||
        description.contains('cancelled') ||
        description.contains('canceled')) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _error = error.description;
      _loading = false;
    });
  }

  void _onSslAuthError(SslAuthError error) {
    unawaited(_resolveSslAuthError(error));
  }

  Future<void> _resolveSslAuthError(SslAuthError error) async {
    if (_sslTrusted) {
      await error.proceed();
      return;
    }
    if (!mounted) {
      await error.cancel();
      return;
    }
    if (_sslDialogOpen) {
      await error.cancel();
      return;
    }
    _sslDialogOpen = true;
    final description = error.platform.description;
    final detail = description.isEmpty ? '证书校验失败' : description;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('证书不受信任'),
        content: Text(
          '该站点提供的证书无法验证：\n$detail\n\n'
          '绿联 NAS 常使用自签名证书。继续访问将信任本次会话中的所有证书错误，'
          '请确认你连接的是自己的设备与可信网络。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('继续访问'),
          ),
        ],
      ),
    );
    _sslDialogOpen = false;
    if (accepted == true) {
      _sslTrusted = true;
      await error.proceed();
    } else {
      await error.cancel();
    }
  }

  void _onUrlChange(UrlChange change) {
    final url = change.url;
    if (url == null || !mounted) {
      return;
    }
    setState(() => _currentUrl = url);
  }

  void _reload() {
    setState(() {
      _error = null;
      _loading = true;
      _progress = 0;
    });
    _controller.reload();
  }

  Future<void> _relogin() async {
    _fillTimer?.cancel();
    _fillTimer = null;
    _autoFillLocked = false;
    _tipShown = false;
    _noFormCount = 0;
    try {
      await WebViewCookieManager().clearCookies();
      await _controller.clearCache();
      await _controller.clearLocalStorage();
    } catch (_) {
      // 部分 ROM 清理缓存可能失败，继续重载。
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _error = null;
      _loading = true;
      _progress = 0;
      _pageTitle = '';
    });
    await _controller.loadRequest(Uri.parse(widget.url));
  }

  Future<void> _copyUrl() async {
    var url = _currentUrl ?? widget.url;
    try {
      final current = await _controller.currentUrl();
      if (current != null && current.isNotEmpty) {
        url = current;
      }
    } catch (_) {
      // 使用已知地址。
    }
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已复制当前地址：$url')));
  }

  void _onMenuSelected(_MenuAction action) {
    switch (action) {
      case _MenuAction.copyUrl:
        unawaited(_copyUrl());
      case _MenuAction.upload:
        unawaited(_startUpload());
      case _MenuAction.downloads:
        _openDownloads();
      case _MenuAction.reload:
        _reload();
      case _MenuAction.relogin:
        unawaited(_relogin());
      case _MenuAction.exit:
        unawaited(_closeBrowser());
    }
  }

  /// 先恢复系统栏并等 Insets 稳定，再返回登录页，避免登录页左侧布局跳动。
  Future<void> _closeBrowser() async {
    if (_closing) {
      return;
    }
    _closing = true;
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    await _invokeNativeImmersive(false);
    await Future<void>.delayed(const Duration(milliseconds: 280));
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _handleSystemBack() async {
    if (_islandCtrl.value > 0.4) {
      _collapseIsland();
      return;
    }
    try {
      if (await _controller.canGoBack()) {
        await _controller.goBack();
        return;
      }
    } catch (_) {
      // 无法查询时直接退出。
    }
    if (mounted) {
      unawaited(_closeBrowser());
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_handleSystemBack());
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.canvasTop,
        body: Stack(
          children: [
            Positioned.fill(child: WebViewWidget(controller: _controller)),
            if (!_pageRevealed)
              const Positioned.fill(
                child: ColoredBox(
                  color: AppColors.canvasTop,
                  child: Center(
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(strokeWidth: 2.6),
                    ),
                  ),
                ),
              ),
            if (_error != null)
              Positioned.fill(
                child: _ErrorPane(
                  message: _error!,
                  address: widget.addressLabel,
                  onRetry: _reload,
                  onExit: () => unawaited(_closeBrowser()),
                ),
              ),
            AnimatedBuilder(
              animation: _islandCtrl,
              builder: (context, _) {
                final openness = Curves.easeOutCubic.transform(
                  _islandCtrl.value,
                );
                return Stack(
                  children: [
                    if (openness > 0.01)
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _handleScrimTap,
                          child: ColoredBox(
                            color: Colors.black.withValues(
                              alpha: 0.16 * openness,
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      child: SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [_buildIsland(context, openness)],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIsland(BuildContext context, double openness) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    const collapsedWidth = 140.0;
    final expandedWidth = (screenWidth * 0.72).clamp(420.0, 660.0).toDouble();
    final barHeight = _headerBarHeight.clamp(30.0, 64.0).toDouble();
    final expandedHeight = barHeight + 40;
    final islandWidth =
        collapsedWidth + (expandedWidth - collapsedWidth) * openness;
    final islandHeight = barHeight + (expandedHeight - barHeight) * openness;
    final details = ((openness - 0.3) / 0.5).clamp(0.0, 1.0).toDouble();
    // 动画过程中做高斯模糊，定格后恢复清晰。
    final blurSigma = _islandCtrl.isAnimating
        ? 3.2 * math.sin(math.pi * _islandCtrl.value)
        : 0.0;

    final background = Color.lerp(
      const Color(0x8C0B3D27),
      const Color(0xF7FFFFFF),
      openness,
    )!;
    final borderColor = Color.lerp(
      Colors.white.withValues(alpha: 0.28),
      AppColors.line,
      openness,
    )!;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _handleIslandTap,
      onVerticalDragUpdate: _onIslandDragUpdate,
      onVerticalDragEnd: _onIslandDragEnd,
      child: Container(
        width: islandWidth,
        height: islandHeight,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(islandHeight / 2),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: AppColors.ink.withValues(alpha: 0.08 + 0.10 * openness),
              blurRadius: 8 + 16 * openness,
              offset: Offset(0, 3 + 3 * openness),
            ),
          ],
        ),
        child: _blurLayer(
          blurSigma,
          Stack(
            children: [
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: 1 - details,
                  child: Center(child: _collapsedIndicator()),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                ignoring: details < 0.6,
                child: Opacity(
                  opacity: details,
                  child: OverflowBox(
                    maxWidth: expandedWidth,
                    maxHeight: expandedHeight,
                    alignment: Alignment.center,
                    child: SizedBox(
                      width: expandedWidth,
                      height: expandedHeight,
                      child: _islandActions(context),
                    ),
                  ),
                ),
              ),
            ),
            if (_loading)
              Positioned(
                left: 12,
                right: 12,
                bottom: 4,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: _progress <= 0 ? null : _progress / 100,
                    minHeight: 2.4,
                    backgroundColor: Colors.transparent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _blurLayer(double sigma, Widget child) {
    if (sigma <= 0.05) {
      return child;
    }
    return ImageFiltered(
      imageFilter: ImageFilter.blur(
        sigmaX: sigma,
        sigmaY: sigma,
        tileMode: TileMode.decal,
      ),
      child: child,
    );
  }

  Widget _collapsedIndicator() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: _loading
                ? const Color(0xFFFFC53D)
                : const Color(0xFF5BE49B),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 34,
          height: 3,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }

  Widget _islandActions(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 8),
        _IslandIconButton(
          icon: Icons.close_rounded,
          tooltip: '关闭并返回登录页',
          onPressed: () => unawaited(_closeBrowser()),
        ),
        Container(width: 1, height: 22, color: AppColors.line),
        _IslandIconButton(
          icon: Icons.arrow_back_rounded,
          tooltip: '网页后退',
          onPressed: _canGoBack ? () => unawaited(_controller.goBack()) : null,
        ),
        _IslandIconButton(
          icon: Icons.refresh_rounded,
          tooltip: '刷新',
          onPressed: _reload,
        ),
        _IslandIconButton(
          icon: Icons.upload_file_rounded,
          tooltip: '上传文件到当前文件夹',
          onPressed: () => unawaited(_startUpload()),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _pageTitle.isEmpty ? '绿联云' : _pageTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Icon(
                    widget.url.startsWith('https://')
                        ? Icons.lock_rounded
                        : Icons.wifi_rounded,
                    size: 11,
                    color: AppColors.muted,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      _loading
                          ? '${widget.addressLabel} · $_progress%'
                          : widget.addressLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(
          width: 38,
          height: 38,
          child: PopupMenuButton<_MenuAction>(
            tooltip: '更多操作',
            padding: EdgeInsets.zero,
            iconSize: 20,
            icon: const Icon(Icons.more_horiz_rounded, color: AppColors.ink),
            onSelected: _onMenuSelected,
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: _MenuAction.copyUrl,
                child: _MenuRow(icon: Icons.copy_rounded, label: '复制当前地址'),
              ),
              const PopupMenuItem(
                value: _MenuAction.upload,
                child: _MenuRow(
                  icon: Icons.upload_file_rounded,
                  label: '上传文件到当前文件夹',
                ),
              ),
              const PopupMenuItem(
                value: _MenuAction.downloads,
                child: _MenuRow(icon: Icons.download_rounded, label: '下载管理'),
              ),
              PopupMenuItem(
                value: _MenuAction.reload,
                child: _MenuRow(icon: Icons.refresh_rounded, label: '重新加载'),
              ),
              PopupMenuItem(
                value: _MenuAction.relogin,
                child: _MenuRow(
                  icon: Icons.restart_alt_rounded,
                  label: '清除会话并自动登录',
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: _MenuAction.exit,
                child: _MenuRow(icon: Icons.logout_rounded, label: '返回登录页'),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
      ],
    );
  }
}

class _IslandIconButton extends StatelessWidget {
  const _IslandIconButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: 19,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 38, height: 38),
      color: AppColors.ink,
      disabledColor: AppColors.ink.withValues(alpha: 0.24),
      icon: Icon(icon),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.muted),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(fontSize: 13)),
      ],
    );
  }
}

class _ErrorPane extends StatelessWidget {
  const _ErrorPane({
    required this.message,
    required this.address,
    required this.onRetry,
    required this.onExit,
  });

  final String message;
  final String address;
  final VoidCallback onRetry;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.canvasTop,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 66,
                  height: 66,
                  decoration: BoxDecoration(
                    color: AppColors.brand.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.cloud_off_rounded,
                    size: 30,
                    color: AppColors.brandDark,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  '无法打开绿联云',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  address,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.6,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '请确认 NAS 已开机、地址与端口正确，且平板与设备处于同一网络。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.6,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onExit,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('返回登录'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('重试'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
