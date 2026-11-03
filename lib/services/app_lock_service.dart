import 'dart:isolate';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../widgets/fingerprint_dialog.dart';
import 'fingerprint_auth.dart';
import 'pin_hash.dart';

/// 解锁方式的两种类型，二选一。
enum UnlockMethod {
  pin('数字密码'),
  pattern('图形密码');

  const UnlockMethod(this.label);

  final String label;

  static UnlockMethod fromStorage(String? raw) {
    return raw == 'pattern' ? UnlockMethod.pattern : UnlockMethod.pin;
  }

  String get storageValue => this == UnlockMethod.pattern ? 'pattern' : 'pin';
}

/// 应用锁：进入 App（冷启动、或后台超过一分钟回来）时可选要求的本地验证。
///
/// 两种凭据互斥，二选一：
/// - 4-6 位数字密码；
/// - 图形密码（3x3 九点，至少连 4 个点）。
/// 二者都以「随机盐 + HMAC-SHA256 迭代」哈希后存 Android Keystore 加密的
/// secure storage，明文不落盘。
/// 另外可以开启系统指纹（弹窗自绘，见 widgets/fingerprint_dialog.dart）。
class AppLockService extends ChangeNotifier {
  AppLockService._();

  static final AppLockService instance = AppLockService._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
    ),
  );

  static const _enabledKey = 'ugreen_shell_lock_enabled_v1';
  static const _hashKey = 'ugreen_shell_lock_hash_v1';
  static const _saltKey = 'ugreen_shell_lock_salt_v1';
  static const _bioKey = 'ugreen_shell_lock_bio_v1';
  static const _methodKey = 'ugreen_shell_lock_method_v1';

  final FingerprintAuth _fingerprint = FingerprintAuth.instance;

  bool _loaded = false;
  bool _enabled = false;
  bool _biometric = false;
  UnlockMethod _method = UnlockMethod.pin;
  FingerprintAvailability _fingerprintStatus =
      const FingerprintAvailability.unknown();
  String? _hash;
  String? _salt;

  bool get isLoaded => _loaded;

  /// 只有开关打开且确实存过凭据才算启用。
  bool get isEnabled => _enabled && hasSecret;

  bool get biometricEnabled => _biometric && isEnabled;

  bool get biometricAvailable => _fingerprintStatus.usable;

  FingerprintAvailability get fingerprintStatus => _fingerprintStatus;

  UnlockMethod get method => _method;

  bool get hasSecret =>
      (_hash?.isNotEmpty ?? false) && (_salt?.isNotEmpty ?? false);

  Future<void> load() async {
    try {
      _enabled = await _storage.read(key: _enabledKey) == '1';
      _biometric = await _storage.read(key: _bioKey) == '1';
      _method = UnlockMethod.fromStorage(await _storage.read(key: _methodKey));
      _hash = await _storage.read(key: _hashKey);
      _salt = await _storage.read(key: _saltKey);
    } catch (_) {
      _enabled = false;
      _biometric = false;
      _method = UnlockMethod.pin;
      _hash = null;
      _salt = null;
    }
    _fingerprintStatus = await _fingerprint.status();
    _loaded = true;
    notifyListeners();
  }

  /// 重新检测指纹硬件 / 录入状态（用户可能刚去系统设置里录入完）。
  Future<FingerprintAvailability> refreshFingerprint() async {
    _fingerprintStatus = await _fingerprint.status();
    notifyListeners();
    return _fingerprintStatus;
  }

  /// 保存新的凭据（数字密码或图形密码），同时切换解锁方式。
  Future<void> setSecret(String secret, UnlockMethod method) async {
    final salt = generatePinSalt();
    final hash = await Isolate.run(() => hashPin(secret, salt));
    _salt = salt;
    _hash = hash;
    _method = method;
    await _storage.write(key: _saltKey, value: salt);
    await _storage.write(key: _hashKey, value: hash);
    await _storage.write(key: _methodKey, value: method.storageValue);
    notifyListeners();
  }

  /// 校验用户输入的凭据（数字密码或图形密码的点位串）。
  Future<bool> verifySecret(String secret) async {
    final salt = _salt;
    final hash = _hash;
    if (salt == null || hash == null || secret.isEmpty) {
      return false;
    }
    final candidate = await Isolate.run(() => hashPin(secret, salt));
    return constantTimeEquals(candidate, hash);
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    await _storage.write(key: _enabledKey, value: value ? '1' : '0');
    notifyListeners();
  }

  Future<void> setBiometricEnabled(bool value) async {
    _biometric = value;
    await _storage.write(key: _bioKey, value: value ? '1' : '0');
    notifyListeners();
  }

  /// 关闭应用锁：同时清掉凭据与指纹开关。
  Future<void> disable() async {
    _enabled = false;
    _biometric = false;
    _hash = null;
    _salt = null;
    await _storage.write(key: _enabledKey, value: '0');
    await _storage.write(key: _bioKey, value: '0');
    await _storage.delete(key: _hashKey);
    await _storage.delete(key: _saltKey);
    await _storage.delete(key: _methodKey);
    notifyListeners();
  }

  /// 调起自己画的指纹弹窗，验证通过返回 true。
  Future<bool> authenticateFingerprint(BuildContext context) async {
    final status = _fingerprintStatus.usable
        ? _fingerprintStatus
        : await refreshFingerprint();
    if (!status.usable) {
      return false;
    }
    if (!context.mounted) {
      return false;
    }
    return showFingerprintDialog(context);
  }
}
