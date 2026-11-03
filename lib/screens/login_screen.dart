import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/saved_account.dart';
import '../services/address_resolver.dart';
import '../services/credential_store.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_mark.dart';
import 'browser_screen.dart';
import 'security_settings_screen.dart';

/// 重新设计的绿联云登录页。
///
/// 支持局域网 / UGREENlink 两种连接方式，可记住账号密码并自动填充登录。
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _store = const CredentialStore();
  final _addressCtrl = TextEditingController();
  final _accountCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _accountFocus = FocusNode();
  final _passwordFocus = FocusNode();

  ConnectionMode _mode = ConnectionMode.lan;
  List<SavedAccount> _accounts = const [];
  bool _rememberPassword = true;
  bool _autoLogin = true;
  bool _obscurePassword = true;
  bool _busy = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    _accountCtrl.dispose();
    _passwordCtrl.dispose();
    _accountFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    try {
      final accounts = await _store.loadAccounts();
      final last = await _store.loadLastSession();
      if (!mounted) {
        return;
      }
      SavedAccount? matched;
      if (last != null) {
        for (final account in accounts) {
          if (account.mode == last.mode &&
              account.account == last.account &&
              account.input == last.input) {
            matched = account;
            break;
          }
        }
        _mode = last.mode;
        _addressCtrl.text = last.input;
        _accountCtrl.text = last.account;
      } else if (accounts.isNotEmpty) {
        final account = accounts.first;
        _mode = account.mode;
        _addressCtrl.text = account.input;
        _accountCtrl.text = account.account;
        matched = account;
      }
      if (matched?.password != null) {
        _passwordCtrl.text = matched!.password!;
        _rememberPassword = true;
      }
      setState(() {
        _accounts = accounts;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String get _preview {
    final raw = _addressCtrl.text.trim();
    if (raw.isEmpty) {
      return _mode == ConnectionMode.lan
          ? '默认访问 http://<NAS IP>:9999'
          : '示例：https://ug.link/myNAS123';
    }
    final resolution = AddressResolver.resolve(_mode, raw);
    if (resolution.url != null) {
      return '将访问 ${resolution.url}';
    }
    return _mode == ConnectionMode.lan
        ? '支持 IP、域名，HTTP 9999 / HTTPS 9443'
        : '支持 UGREENlink ID 或完整 ug.link 地址';
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final resolution = AddressResolver.resolve(_mode, _addressCtrl.text);
    if (!resolution.isValid) {
      setState(() => _error = resolution.error);
      return;
    }
    final account = _accountCtrl.text.trim();
    if (account.isEmpty) {
      setState(() => _error = '请输入绿联云账号');
      _accountFocus.requestFocus();
      return;
    }
    final password = _passwordCtrl.text;
    if (password.isEmpty) {
      setState(() => _error = '请输入登录密码');
      _passwordFocus.requestFocus();
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final input = _addressCtrl.text.trim();
    final url = resolution.url!;
    final record = SavedAccount(
      mode: _mode,
      input: input,
      url: url,
      account: account,
      password: _rememberPassword ? password : null,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    String? saveError;
    try {
      await _store.upsertAccount(record);
      await _store.saveLastSession(
        LastSession(
          mode: _mode,
          input: input,
          account: account,
          url: url,
        ),
      );
    } catch (_) {
      saveError = '凭据保存失败，本次登录仍可继续';
    }

    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    if (saveError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(saveError)));
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BrowserScreen(
          url: url,
          addressLabel: resolution.display ?? input,
          account: account,
          password: password,
          autoLogin: _autoLogin,
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    await _reloadAccounts();
  }

  Future<void> _reloadAccounts() async {
    try {
      final accounts = await _store.loadAccounts();
      if (mounted) {
        setState(() => _accounts = accounts);
      }
    } catch (_) {
      // 读取失败时保留当前列表。
    }
  }

  Future<void> _showAccountPicker() async {
    if (_accounts.isEmpty) {
      return;
    }
    FocusScope.of(context).unfocus();
    final selected = await showDialog<SavedAccount>(
      context: context,
      builder: (_) => AccountPickerDialog(
        accounts: _accounts,
        store: _store,
      ),
    );
    await _reloadAccounts();
    if (!mounted || selected == null) {
      return;
    }
    setState(() {
      _mode = selected.mode;
      _addressCtrl.text = selected.input;
      _accountCtrl.text = selected.account;
      _passwordCtrl.text = selected.password ?? '';
      _rememberPassword = selected.password != null;
      _error = null;
    });
  }

  void _clearError() {
    if (_error != null) {
      setState(() => _error = null);
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: AppColors.canvasBottom,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        body: Stack(
          children: [
            const _LoginBackdrop(),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final metrics = _TabletMetrics.from(constraints);
                  return SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: metrics.pageHorizontal,
                      vertical: metrics.pageVertical,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight:
                            (constraints.maxHeight - metrics.pageVertical * 2)
                                .clamp(0.0, double.infinity)
                                .toDouble(),
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: metrics.maxContentWidth,
                          ),
                          child: metrics.wide
                              ? _buildWideLayout(metrics)
                              : ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 540,
                                  ),
                                  child: _buildNarrowLayout(metrics),
                                ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Positioned(
              right: 10,
              top: 6,
              child: SafeArea(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SecuritySettingsScreen(),
                      ),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Icon(
                        Icons.shield_outlined,
                        size: 22,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWideLayout(_TabletMetrics metrics) {
    // 用右侧卡片决定整体高度，左侧面板绝对定位填满同高，避免 IntrinsicHeight
    // 在包含输入框、Switch 时低估高度导致卡片溢出。
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 28.0;
        final heroWidth = (constraints.maxWidth - gap) * 10 / 19;
        return Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: heroWidth,
              child: _HeroPanel(
                compact: metrics.compact,
                headlineSize: metrics.heroHeadlineSize,
              ),
            ),
            Padding(
              padding: EdgeInsets.only(left: heroWidth + gap),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: metrics.cardMaxWidth),
                  child: _Entrance(child: _buildCard(metrics)),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildNarrowLayout(_TabletMetrics metrics) {
    return Column(
      children: [
        const BrandTitle(
          markSize: 44,
          title: '绿联云',
          subtitle: 'ANDROID 平板端',
        ),
        const SizedBox(height: 22),
        _Entrance(child: _buildCard(metrics)),
      ],
    );
  }

  Widget _buildCard(_TabletMetrics metrics) {
    final compact = metrics.compact;
    final fieldGap = compact ? 12.0 : 16.0;
    return Container(
      padding: metrics.cardPadding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF173A2A).withValues(alpha: 0.09),
            blurRadius: 44,
            offset: const Offset(0, 22),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '登录绿联云',
            style: TextStyle(
              fontSize: compact ? 23 : 25,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
          SizedBox(height: compact ? 4 : 6),
          const Text(
            '连接你的私有云，继续平板上的大屏体验',
            style: TextStyle(fontSize: 12.5, color: AppColors.muted),
          ),
          SizedBox(height: compact ? 14 : 22),
          _ModeSwitcher(
            value: _mode,
            onChanged: (mode) {
              setState(() {
                _mode = mode;
                _error = null;
              });
            },
          ),
          SizedBox(height: compact ? 14 : 20),
          _FieldLabel(
            label: _mode == ConnectionMode.lan ? '设备地址' : 'UGREENlink ID',
          ),
          const SizedBox(height: 7),
          TextField(
            controller: _addressCtrl,
            textInputAction: TextInputAction.next,
            keyboardType: TextInputType.text,
            onChanged: (_) => _clearError(),
            onSubmitted: (_) => _accountFocus.requestFocus(),
            decoration: InputDecoration(
              hintText: _mode == ConnectionMode.lan
                  ? '192.168.31.70 或 nas.local'
                  : '例如 myNAS123',
              prefixIcon: Icon(
                _mode == ConnectionMode.lan
                    ? Icons.dns_rounded
                    : Icons.public_rounded,
                size: 20,
              ),
              suffixIcon: _addressCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清空地址',
                      onPressed: () {
                        _addressCtrl.clear();
                        _clearError();
                      },
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
            ),
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              const Icon(
                Icons.link_rounded,
                size: 13,
                color: AppColors.muted,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  _preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.muted,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: fieldGap),
          const _FieldLabel(label: '绿联云账号'),
          const SizedBox(height: 7),
          TextField(
            controller: _accountCtrl,
            focusNode: _accountFocus,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.username],
            onChanged: (_) => _clearError(),
            onSubmitted: (_) => _passwordFocus.requestFocus(),
            decoration: InputDecoration(
              hintText: '账号',
              prefixIcon: const Icon(Icons.person_outline_rounded, size: 20),
              suffixIcon: _accounts.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '选择已保存的账号',
                      onPressed: _showAccountPicker,
                      icon: const Icon(Icons.history_rounded, size: 20),
                    ),
            ),
          ),
          SizedBox(height: fieldGap),
          const _FieldLabel(label: '密码'),
          const SizedBox(height: 7),
          TextField(
            controller: _passwordCtrl,
            focusNode: _passwordFocus,
            obscureText: _obscurePassword,
            autocorrect: false,
            enableSuggestions: false,
            smartDashesType: SmartDashesType.disabled,
            smartQuotesType: SmartQuotesType.disabled,
            enableIMEPersonalizedLearning: false,
            autofillHints: const [AutofillHints.password],
            textInputAction: TextInputAction.done,
            onChanged: (_) => _clearError(),
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: '输入登录密码',
              prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
              suffixIcon: IconButton(
                tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                onPressed: () {
                  setState(() => _obscurePassword = !_obscurePassword);
                },
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 19,
                ),
              ),
            ),
          ),
          SizedBox(height: compact ? 8 : 10),
          Row(
            children: [
              Expanded(
                child: _SwitchRow(
                  label: '记住账号密码',
                  value: _rememberPassword,
                  onChanged: (value) {
                    setState(() => _rememberPassword = value);
                  },
                ),
              ),
              Expanded(
                child: _SwitchRow(
                  label: '自动登录',
                  value: _autoLogin,
                  onChanged: (value) {
                    setState(() => _autoLogin = value);
                  },
                ),
              ),
            ],
          ),
          if (_autoLogin) ...[
            SizedBox(height: compact ? 3 : 6),
            const Row(
              children: [
                Icon(
                  Icons.bolt_rounded,
                  size: 13,
                  color: AppColors.brandDark,
                ),
                SizedBox(width: 5),
                Expanded(
                  child: Text(
                    '进入网页后自动填入账号密码并提交登录',
                    style: TextStyle(fontSize: 10.5, color: AppColors.muted),
                  ),
                ),
              ],
            ),
          ],
          if (_error != null) ...[
            SizedBox(height: compact ? 10 : 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.danger.withValues(alpha: 0.18),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 16,
                    color: AppColors.danger,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.danger,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          SizedBox(height: compact ? 12 : 18),
          _GradientButton(
            label: '登录并进入',
            icon: Icons.arrow_forward_rounded,
            busy: _busy,
            onPressed: (_busy || _loading) ? null : _submit,
          ),
          SizedBox(height: compact ? 8 : 14),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.verified_user_rounded,
                size: 13,
                color: AppColors.brandDark,
              ),
              SizedBox(width: 6),
              Flexible(
                child: Text(
                  '凭据经 Android Keystore 加密，仅保存在本机',
                  style: TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ),
            ],
          ),
          if (!compact) ...[
            const SizedBox(height: 14),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'UGOS Pro · v1.0.38',
                  style: TextStyle(fontSize: 10.5, color: AppColors.muted),
                ),
                Text(
                  'ANDROID TABLET',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: AppColors.muted,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 根据平板可用宽高与宽高比计算登录页排版参数。
///
/// 4:3、16:10、16:9 等横屏平板会自动调整左右留白、内容最大宽度与纵向间距；
/// 高度较小的设备进入紧凑模式，隐藏次要页脚并压缩间距，尽量保证一屏完成登录。
class _TabletMetrics {
  const _TabletMetrics({
    required this.wide,
    required this.compact,
    required this.pageHorizontal,
    required this.pageVertical,
    required this.maxContentWidth,
    required this.heroHeadlineSize,
    required this.cardPadding,
    required this.cardMaxWidth,
  });

  factory _TabletMetrics.from(BoxConstraints constraints) {
    final width = constraints.maxWidth;
    final height = constraints.maxHeight.isFinite
        ? constraints.maxHeight
        : 800.0;
    final wide = width >= 900 && width / height >= 1.15;
    final compact = height < 740;
    final baseHeadline = width >= 1100
        ? 40.0
        : (width >= 960 ? 36.0 : 33.0);
    final pageVertical = compact
        ? (height * 0.03).clamp(14.0, 26.0)
        : (height * 0.045).clamp(20.0, 40.0);

    return _TabletMetrics(
      wide: wide,
      compact: compact,
      pageHorizontal: (width * 0.035).clamp(20.0, 44.0).toDouble(),
      pageVertical: pageVertical.toDouble(),
      maxContentWidth: (width * 0.92).clamp(1000.0, 1440.0).toDouble(),
      heroHeadlineSize: compact ? baseHeadline - 5 : baseHeadline,
      cardPadding: compact
          ? const EdgeInsets.fromLTRB(24, 22, 24, 16)
          : const EdgeInsets.fromLTRB(28, 30, 28, 22),
      cardMaxWidth: 480,
    );
  }

  final bool wide;
  final bool compact;
  final double pageHorizontal;
  final double pageVertical;
  final double maxContentWidth;
  final double heroHeadlineSize;
  final EdgeInsets cardPadding;
  final double cardMaxWidth;
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
        letterSpacing: 0.2,
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          Transform.scale(
            scale: 0.72,
            child: Switch(
              value: value,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 2),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeSwitcher extends StatelessWidget {
  const _ModeSwitcher({required this.value, required this.onChanged});

  final ConnectionMode value;
  final ValueChanged<ConnectionMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F6F3),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (final mode in ConnectionMode.values)
            Expanded(
              child: _ModeItem(
                mode: mode,
                selected: mode == value,
                onTap: () => onChanged(mode),
              ),
            ),
        ],
      ),
    );
  }
}

class _ModeItem extends StatelessWidget {
  const _ModeItem({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final ConnectionMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: 42,
      decoration: BoxDecoration(
        color: selected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: selected
              ? AppColors.brand.withValues(alpha: 0.22)
              : Colors.transparent,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: AppColors.brandInk.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: onTap,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  mode == ConnectionMode.lan
                      ? Icons.wifi_rounded
                      : Icons.language_rounded,
                  size: 16,
                  color: selected ? AppColors.brandDark : AppColors.muted,
                ),
                const SizedBox(width: 6),
                Text(
                  mode.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? AppColors.brandDark : AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.label,
    required this.icon,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: onPressed,
          child: Ink(
            height: 52,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1CC47C), AppColors.brandDark],
              ),
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                  color: AppColors.brand.withValues(alpha: 0.28),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (busy)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  else
                    Icon(icon, size: 19, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Entrance extends StatelessWidget {
  const _Entrance({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 18 * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({required this.compact, required this.headlineSize});

  final bool compact;
  final double headlineSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.heroStart, AppColors.heroMid, AppColors.heroEnd],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandInk.withValues(alpha: 0.2),
            blurRadius: 48,
            offset: const Offset(0, 24),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: Stack(
          children: [
            Positioned(
              top: -110,
              right: -90,
              child: _Blob(
                size: 360,
                color: AppColors.brand.withValues(alpha: 0.35),
              ),
            ),
            Positioned(
              bottom: -150,
              left: -120,
              child: _Blob(
                size: 420,
                color: const Color(0xFF0EA5A0).withValues(alpha: 0.2),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 30 : 38,
                compact ? 26 : 36,
                compact ? 30 : 38,
                compact ? 24 : 32,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: compact
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.spaceBetween,
                children: [
                  BrandTitle(
                    light: true,
                    markSize: compact ? 44 : 50,
                    title: '绿联云',
                    subtitle: 'UGREEN CLOUD · TABLET',
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: compact ? 24 : 44),
                      Text(
                        '把绿联云，\n装进平板。',
                        style: TextStyle(
                          fontSize: headlineSize,
                          height: 1.16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: compact ? 12 : 18),
                      Text(
                        '为 Android 平板打造的绿联云大屏访问入口。\n重新设计的登录体验，账号密码加密保存在本机，\n一处登录，直达大屏桌面。',
                        style: TextStyle(
                          fontSize: compact ? 13 : 14,
                          height: compact ? 1.65 : 1.8,
                          color: Colors.white.withValues(alpha: 0.72),
                        ),
                      ),
                      SizedBox(height: compact ? 22 : 32),
                      const _FeatureRow(
                        icon: Icons.aspect_ratio_rounded,
                        title: '为平板而生的桌面视野',
                        detail: '完整加载绿联云网页端，横竖屏自适应',
                      ),
                      SizedBox(height: compact ? 14 : 18),
                      const _FeatureRow(
                        icon: Icons.shield_rounded,
                        title: '凭据只留在本机',
                        detail: '账号密码经 Android Keystore 加密',
                      ),
                      SizedBox(height: compact ? 14 : 18),
                      const _FeatureRow(
                        icon: Icons.bolt_rounded,
                        title: '打开即登录',
                        detail: '自动识别登录表单并填充、提交',
                      ),
                    ],
                  ),
                  if (!compact)
                    Padding(
                      padding: const EdgeInsets.only(top: 34),
                      child: Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: AppColors.brand,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'HTTP 9999  ·  HTTPS 9443  ·  UGREENLINK',
                            style: TextStyle(
                              fontSize: 10.5,
                              letterSpacing: 1.2,
                              color: Colors.white.withValues(alpha: 0.45),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Icon(icon, size: 18, color: const Color(0xFF8CE7B4)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                style: TextStyle(
                  fontSize: 11.5,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}

class _LoginBackdrop extends StatelessWidget {
  const _LoginBackdrop();

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.canvasTop,
              Color(0xFFF1F8F4),
              AppColors.canvasBottom,
            ],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -140,
              right: -100,
              child: _Blob(
                size: 440,
                color: AppColors.brand.withValues(alpha: 0.15),
              ),
            ),
            Positioned(
              bottom: -180,
              left: -140,
              child: _Blob(
                size: 520,
                color: const Color(0xFF0E7490).withValues(alpha: 0.09),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _DotGridPainter()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  const _DotGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.ink.withValues(alpha: 0.032);
    const step = 28.0;
    for (var x = 14.0; x < size.width; x += step) {
      for (var y = 14.0; y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), 1.1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotGridPainter oldDelegate) => false;
}

/// 已保存账号的选择与删除弹窗。
class AccountPickerDialog extends StatefulWidget {
  const AccountPickerDialog({
    super.key,
    required this.accounts,
    required this.store,
  });

  final List<SavedAccount> accounts;
  final CredentialStore store;

  @override
  State<AccountPickerDialog> createState() => _AccountPickerDialogState();
}

class _AccountPickerDialogState extends State<AccountPickerDialog> {
  late final List<SavedAccount> _items = List.of(widget.accounts);

  Future<void> _delete(SavedAccount account) async {
    try {
      await widget.store.removeAccount(account);
    } catch (_) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _items.removeWhere((item) => item.id == account.id));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 540),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 12, 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.history_rounded,
                    color: AppColors.brandDark,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '已保存的账号',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    tooltip: '关闭',
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: _items.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        '暂无记录',
                        style: TextStyle(color: AppColors.muted),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _items.length,
                      separatorBuilder: (_, _) => const Divider(
                        height: 1,
                        indent: 68,
                        endIndent: 16,
                      ),
                      itemBuilder: (context, index) {
                        final account = _items[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.only(
                            left: 20,
                            right: 8,
                          ),
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: AppColors.brand.withValues(
                              alpha: 0.12,
                            ),
                            child: Text(
                              account.account.isEmpty
                                  ? '?'
                                  : account.account.substring(0, 1).toUpperCase(),
                              style: const TextStyle(
                                color: AppColors.brandDark,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          title: Text(
                            account.account,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            '${account.mode.label} · ${account.addressLabel}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.muted,
                            ),
                          ),
                          trailing: IconButton(
                            tooltip: '删除这条记录',
                            onPressed: () => _delete(account),
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 19,
                              color: AppColors.muted,
                            ),
                          ),
                          onTap: () => Navigator.of(context).pop(account),
                        );
                      },
                    ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Row(
                children: [
                  Icon(Icons.lock_rounded, size: 13, color: AppColors.muted),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '密码仅保存在本机安全存储中',
                      style: TextStyle(fontSize: 11, color: AppColors.muted),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
