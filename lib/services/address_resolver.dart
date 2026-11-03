import '../models/saved_account.dart';

/// 地址解析结果，成功时 [url] 为可直接加载的完整地址。
class AddressResolution {
  const AddressResolution._({this.url, this.display, this.error});

  factory AddressResolution.ok(String url, String display) =>
      AddressResolution._(url: url, display: display);

  factory AddressResolution.failure(String message) =>
      AddressResolution._(error: message);

  final String? url;
  final String? display;
  final String? error;

  bool get isValid => url != null;
}

/// 把用户输入转换为绿联云网页地址。
///
/// - 局域网：`192.168.31.70` → `http://192.168.31.70:9999`
/// - 局域网 HTTPS：端口 9443 / 443 或显式 https 时使用 https
/// - UGREENlink：`myNAS123` → `https://ug.link/myNAS123`
abstract final class AddressResolver {
  static const int defaultHttpPort = 9999;
  static const int defaultHttpsPort = 9443;

  static AddressResolution resolve(ConnectionMode mode, String raw) {
    final value = raw.trim();
    if (value.isEmpty) {
      return AddressResolution.failure(
        mode == ConnectionMode.lan ? '请输入 NAS 的 IP 地址或域名' : '请输入 UGREENlink ID',
      );
    }
    if (RegExp(r'\s').hasMatch(value)) {
      return AddressResolution.failure('地址中不能包含空格');
    }
    return mode == ConnectionMode.lan
        ? _resolveLan(value)
        : _resolveLink(value);
  }

  static AddressResolution _resolveLan(String value) {
    var candidate = value;
    final schemePattern = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://');
    if (!schemePattern.hasMatch(candidate)) {
      final portMatch = RegExp(r':(\d{1,5})(?:/|$)').firstMatch(candidate);
      final port = int.tryParse(portMatch?.group(1) ?? '');
      final scheme = (port == 443 || port == defaultHttpsPort)
          ? 'https'
          : 'http';
      candidate = '$scheme://$candidate';
    }

    final uri = Uri.tryParse(candidate);
    if (uri == null || uri.host.isEmpty) {
      return AddressResolution.failure('地址格式不正确，示例：192.168.31.70');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return AddressResolution.failure('仅支持 http:// 或 https:// 地址');
    }

    final port = uri.hasPort
        ? uri.port
        : (uri.scheme == 'https' ? defaultHttpsPort : defaultHttpPort);
    final normalized = Uri(scheme: uri.scheme, host: uri.host, port: port);
    return AddressResolution.ok(normalized.toString(), _displayLan(normalized));
  }

  static AddressResolution _resolveLink(String value) {
    final looksLikeAddress =
        value.contains('.') || value.contains('/') || value.contains('://');
    if (looksLikeAddress) {
      var candidate = value;
      if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(candidate)) {
        candidate = 'https://$candidate';
      }
      final uri = Uri.tryParse(candidate);
      if (uri == null || uri.host.isEmpty) {
        return AddressResolution.failure('远程访问地址格式不正确');
      }
      if (uri.host != 'ug.link' && !uri.host.endsWith('.ug.link')) {
        return AddressResolution.failure(
          '请输入 UGREENlink ID，或 https://ug.link/ 开头的完整地址',
        );
      }
      final id = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
      if (id.isEmpty) {
        return AddressResolution.failure('请在 https://ug.link/ 后填写 ID');
      }
      final normalized = Uri(
        scheme: 'https',
        host: uri.host,
        path: '/$id',
      );
      return AddressResolution.ok(normalized.toString(), 'ug.link/$id');
    }

    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{1,62}$').hasMatch(value)) {
      return AddressResolution.failure('UGREENlink ID 只能包含字母、数字、- 和 _');
    }
    return AddressResolution.ok('https://ug.link/$value', 'ug.link/$value');
  }

  static String _displayLan(Uri uri) {
    final isDefaultPort =
        (uri.scheme == 'http' && uri.port == 80) ||
        (uri.scheme == 'https' && uri.port == 443);
    return uri.hasPort && !isDefaultPort
        ? '${uri.host}:${uri.port}'
        : uri.host;
  }
}
