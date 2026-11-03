import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/saved_account.dart';

/// 账号与密码的本地加密存储。
///
/// 底层使用 Android Keystore（flutter_secure_storage），凭据不会以明文落盘，
/// 也不会离开设备。最多保留 8 条账号记录。
class CredentialStore {
  const CredentialStore();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
    ),
  );

  static const _accountsKey = 'ugreen_shell_accounts_v1';
  static const _sessionKey = 'ugreen_shell_last_session_v1';
  static const _maxAccounts = 8;

  Future<List<SavedAccount>> loadAccounts() async {
    final raw = await _storage.read(key: _accountsKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const [];
    }
    final accounts = <SavedAccount>[];
    for (final item in decoded) {
      if (item is Map) {
        try {
          final account = SavedAccount.fromJson(
            Map<String, dynamic>.from(item),
          );
          if (account.account.isNotEmpty && account.url.isNotEmpty) {
            accounts.add(account);
          }
        } catch (_) {
          // 忽略损坏的单条记录，保留其余数据。
        }
      }
    }
    accounts.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return accounts;
  }

  Future<void> upsertAccount(SavedAccount account) async {
    final accounts = await loadAccounts();
    final next = [
      account,
      ...accounts.where((item) => item.id != account.id),
    ].take(_maxAccounts).toList();
    await _writeAccounts(next);
  }

  Future<void> removeAccount(SavedAccount account) async {
    final accounts = await loadAccounts();
    final next = accounts.where((item) => item.id != account.id).toList();
    await _writeAccounts(next);
  }

  Future<LastSession?> loadLastSession() async {
    final raw = await _storage.read(key: _sessionKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      final session = LastSession.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      if (session.url.isEmpty && session.input.isEmpty) {
        return null;
      }
      return session;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveLastSession(LastSession session) async {
    await _storage.write(
      key: _sessionKey,
      value: jsonEncode(session.toJson()),
    );
  }

  Future<void> _writeAccounts(List<SavedAccount> accounts) async {
    await _storage.write(
      key: _accountsKey,
      value: jsonEncode(accounts.map((item) => item.toJson()).toList()),
    );
  }
}
