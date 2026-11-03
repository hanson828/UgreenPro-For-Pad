/// 连接方式：局域网直连或 UGREENlink 远程访问。
enum ConnectionMode {
  lan('局域网', 'http://<NAS IP>:9999'),
  link('UGREENlink', 'https://ug.link/<ID>');

  const ConnectionMode(this.label, this.example);

  final String label;
  final String example;
}

/// 一条保存在本机的账号记录（密码可空，取决于是否勾选"记住账号密码"）。
class SavedAccount {
  const SavedAccount({
    required this.mode,
    required this.input,
    required this.url,
    required this.account,
    required this.updatedAt,
    this.password,
  });

  /// 连接方式。
  final ConnectionMode mode;

  /// 用户输入时的原始地址 / UGREENlink ID。
  final String input;

  /// 解析后的完整访问地址。
  final String url;

  final String account;

  /// 仅当用户选择记住密码时存在。
  final String? password;

  /// 最近更新时间（毫秒时间戳）。
  final int updatedAt;

  String get id => '${mode.name}|$input|$account';

  String get addressLabel {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) {
      return input;
    }
    if (mode == ConnectionMode.link) {
      final id = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
      return id.isEmpty ? uri.host : 'ug.link/$id';
    }
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.host}$port';
  }

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'input': input,
    'url': url,
    'account': account,
    'password': password,
    'updatedAt': updatedAt,
  };

  factory SavedAccount.fromJson(Map<String, dynamic> json) {
    final modeName = json['mode'] as String?;
    return SavedAccount(
      mode: ConnectionMode.values.firstWhere(
        (mode) => mode.name == modeName,
        orElse: () => ConnectionMode.lan,
      ),
      input: json['input'] as String? ?? '',
      url: json['url'] as String? ?? '',
      account: json['account'] as String? ?? '',
      password: json['password'] as String?,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 上次使用的连接信息（不包含密码）。
class LastSession {
  const LastSession({
    required this.mode,
    required this.input,
    required this.account,
    required this.url,
  });

  final ConnectionMode mode;
  final String input;
  final String account;
  final String url;

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'input': input,
    'account': account,
    'url': url,
  };

  factory LastSession.fromJson(Map<String, dynamic> json) {
    final modeName = json['mode'] as String?;
    return LastSession(
      mode: ConnectionMode.values.firstWhere(
        (mode) => mode.name == modeName,
        orElse: () => ConnectionMode.lan,
      ),
      input: json['input'] as String? ?? '',
      account: json['account'] as String? ?? '',
      url: json['url'] as String? ?? '',
    );
  }
}
