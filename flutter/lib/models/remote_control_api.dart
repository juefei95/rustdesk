import 'dart:convert';

import '../consts.dart';
import '../config/remote_control_config.dart';
import '../utils/http_service.dart' as http;
import 'platform_model.dart';

const _backendMarker = 'remote-control-backend';

class RemoteControlApiException implements Exception {
  RemoteControlApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class RemoteControlLoginResult {
  RemoteControlLoginResult(this.token, this.user, this.membership);

  final String token;
  final Map<String, dynamic> user;
  final RemoteControlMembership membership;
}

class RemoteControlMembership {
  const RemoteControlMembership({
    required this.canControl,
    required this.trialGiven,
    required this.packageName,
    required this.expireTime,
    required this.remainingSeconds,
    required this.controlEnabled,
  });

  final bool canControl;
  final bool trialGiven;
  final String packageName;
  final String expireTime;
  final int remainingSeconds;
  final bool? controlEnabled;

  factory RemoteControlMembership.fromJson(Map<String, dynamic> json) {
    return RemoteControlMembership(
      canControl: json['can_control'] == true,
      trialGiven: json['trial_given'] == 1 || json['trial_given'] == true,
      packageName: (json['package_name'] ?? '').toString().trim(),
      expireTime: (json['expire_time'] ?? '').toString().trim(),
      remainingSeconds:
          int.tryParse((json['remaining_seconds'] ?? '').toString()) ?? 0,
      controlEnabled: json['control_enabled'] == null
          ? null
          : json['control_enabled'] == 1 || json['control_enabled'] == true,
    );
  }

  String get entitlementName => packageName.isNotEmpty ? packageName : '免费版';

  bool get hasPaidMembership => packageName.isNotEmpty;

  bool get isEntitlementExpired =>
      expireTime.isNotEmpty && remainingSeconds <= 0;

  String get noControlMessage {
    if (isEntitlementExpired) {
      return '会员权益已到期，请前往会员中心重新开通后继续使用远程控制。';
    }
    if (!trialGiven && !hasPaidMembership) {
      return '当前账号暂无远程控制权限，可以领取体验或升级权益。';
    }
    if (controlEnabled == false) {
      return '当前账号暂无远程控制权限，原因：控制权限已被管理员禁用。';
    }
    return '当前账号暂无远程控制权限，原因：会员权益状态异常，请联系管理员。';
  }
}

class RemoteControlPackage {
  const RemoteControlPackage({
    required this.id,
    required this.name,
    required this.days,
    required this.price,
    required this.originalPrice,
    required this.recommended,
    required this.description,
  });

  final int id;
  final String name;
  final int days;
  final String price;
  final String originalPrice;
  final bool recommended;
  final String description;

  factory RemoteControlPackage.fromJson(Map<String, dynamic> json) {
    return RemoteControlPackage(
      id: int.tryParse((json['id'] ?? '').toString()) ?? 0,
      name: (json['name'] ?? '').toString().trim(),
      days: int.tryParse((json['days'] ?? '').toString()) ?? 0,
      price: (json['price'] ?? '').toString().trim(),
      originalPrice: (json['original_price'] ?? '').toString().trim(),
      recommended: json['recommended'] == 1 || json['recommended'] == true,
      description: (json['description'] ?? '').toString().trim(),
    );
  }
}

class RemoteControlPaymentOrder {
  const RemoteControlPaymentOrder({
    required this.orderNo,
    required this.payment,
  });

  final String orderNo;
  final Map<String, dynamic> payment;

  String? get qrCodeUrl => _findString(payment, const [
        'code_url',
        'qr_code',
        'qrcode',
        'qr_url',
      ]);

  static String? _findString(Map<String, dynamic> value, List<String> keys) {
    for (final entry in value.entries) {
      if (keys.contains(entry.key) && entry.value is String) {
        final result = (entry.value as String).trim();
        if (result.isNotEmpty) return result;
      }
      if (entry.value is Map<String, dynamic>) {
        final result = _findString(entry.value as Map<String, dynamic>, keys);
        if (result != null) return result;
      }
    }
    return null;
  }
}

class RemoteControlPaymentStatus {
  const RemoteControlPaymentStatus({
    required this.isComplete,
    required this.providerStatus,
  });

  final bool isComplete;
  final String providerStatus;
}

class WechatQrLoginSession {
  WechatQrLoginSession({
    required this.scene,
    required this.qrUrl,
    required this.expiresIn,
  });

  final String scene;
  final String qrUrl;
  final int expiresIn;
}

class RemoteControlApi {
  static const accessTokenKey = 'remote_control_access_token';

  static bool get isConfigured => server.isNotEmpty;

  static bool get hasRendezvousServer =>
      bind.mainGetOptionSync(key: 'custom-rendezvous-server').trim().isNotEmpty;

  static bool get isEnabled =>
      bind.mainGetLocalOption(key: _backendMarker) == 'Y';

  static String get server =>
      remoteControlApiServer.trim().replaceFirst(RegExp(r'/+$'), '');

  static Map<String, dynamic> _decode(http.Response response) {
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    if (body is! Map<String, dynamic>) {
      throw RemoteControlApiException('Invalid server response');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RemoteControlApiException(
          (body['msg'] ?? 'HTTP ${response.statusCode}').toString());
    }
    if (body['code'] != 1) {
      throw RemoteControlApiException(
          (body['msg'] ?? 'Request failed').toString());
    }
    final data = body['data'];
    if (data is! Map<String, dynamic>) {
      throw RemoteControlApiException('Invalid server response');
    }
    return data;
  }

  static Future<bool> discoverAndSyncConfig() async {
    final baseUrl = server;
    if (baseUrl.isEmpty) return false;
    try {
      final response =
          await http.get(Uri.parse('$baseUrl/api/remote/client/config'));
      final data = _decode(response);
      final idServer = (data['id_server'] ?? '').toString().trim();
      if (idServer.isEmpty) {
        await bind.mainSetLocalOption(key: _backendMarker, value: 'N');
        await bind.mainSetOption(key: 'custom-rendezvous-server', value: '');
        return false;
      }
      await bind.mainSetLocalOption(key: _backendMarker, value: 'Y');
      await bind.mainSetOption(
          key: 'custom-rendezvous-server', value: idServer);
      await bind.mainSetOption(
          key: 'relay-server', value: (data['relay_server'] ?? '').toString());
      await bind.mainSetOption(
          key: 'key', value: (data['public_key'] ?? '').toString());
      await bind.mainSetOption(
          key: 'api-server', value: (data['api_server'] ?? '').toString());
      await _setPunchOptionDefault(kOptionEnableUdpPunch, true);
      await _setPunchOptionDefault(kOptionEnableIpv6Punch, false);
      return true;
    } catch (_) {
      if (isEnabled) rethrow;
      return false;
    }
  }

  static Future<void> _setPunchOptionDefault(String key, bool enabled) async {
    if (bind.mainGetLocalOption(key: key).isEmpty) {
      await bind.mainSetLocalOption(key: key, value: enabled ? 'Y' : 'N');
    }
  }

  static Future<RemoteControlLoginResult> login(
      String account, String password) async {
    final baseUrl = server;
    final response = await http.post(Uri.parse('$baseUrl/api/remote/login'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: Uri(queryParameters: {
          'account': account,
          'password': password,
        }).query);
    return _parseLoginResult(_decode(response), account);
  }

  static Future<void> sendSms(String mobile) async {
    final response = await http.post(Uri.parse('$server/api/remote/sms'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: Uri(queryParameters: {'mobile': mobile}).query);
    _decode(response);
  }

  static Future<RemoteControlLoginResult> mobileLogin(
      String mobile, String captcha) async {
    final response =
        await http.post(Uri.parse('$server/api/remote/mobilelogin'),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: Uri(queryParameters: {
              'mobile': mobile,
              'captcha': captcha,
            }).query);
    return _parseLoginResult(_decode(response), mobile);
  }

  static Future<WechatQrLoginSession> wechatQrLoginSession() async {
    final response = await http
        .get(Uri.parse('$server/addons/wechatqrcodelogin/index/loginqrcode'));
    final data = _decode(response);
    final scene = (data['scene'] ?? '').toString();
    final qrUrl = (data['qr_url'] ?? '').toString();
    final expiresIn =
        int.tryParse((data['expires_in'] ?? '').toString()) ?? 300;
    if (scene.isEmpty || qrUrl.isEmpty) {
      throw RemoteControlApiException('Invalid WeChat QR login response');
    }
    return WechatQrLoginSession(
      scene: scene,
      qrUrl: qrUrl,
      expiresIn: expiresIn,
    );
  }

  static Future<RemoteControlLoginResult?> queryWechatQrLogin(
      String scene) async {
    final uri = Uri.parse('$server/addons/wechatqrcodelogin/index/loginstatus')
        .replace(queryParameters: {'scene': scene});
    final response = await http.get(uri);
    final data = _decode(response);
    final status = (data['status'] ?? '').toString();
    if (status == 'pending' || status == 'authorized') {
      return null;
    }
    if (status != 'logged_in') {
      throw RemoteControlApiException('Unexpected WeChat login status');
    }
    return _parseWechatLoginResult(data);
  }

  static RemoteControlLoginResult _parseLoginResult(
      Map<String, dynamic> data, String fallbackName) {
    final rawUser = data['userinfo'];
    final member = data['member'];
    if (rawUser is! Map<String, dynamic> || member is! Map<String, dynamic>) {
      throw RemoteControlApiException('Invalid server response');
    }
    final token = (rawUser['token'] ?? '').toString();
    if (token.isEmpty) {
      throw RemoteControlApiException('Login response contains no token');
    }
    final user = <String, dynamic>{
      'name': (rawUser['username'] ?? fallbackName).toString(),
      'display_name': (rawUser['nickname'] ?? '').toString(),
      'avatar': (rawUser['avatar'] ?? '').toString(),
      'status': 1,
    };
    return RemoteControlLoginResult(
        token, user, RemoteControlMembership.fromJson(member));
  }

  static RemoteControlLoginResult _parseWechatLoginResult(
      Map<String, dynamic> data) {
    final rawUser = data['userinfo'];
    if (rawUser is! Map<String, dynamic>) {
      throw RemoteControlApiException('Invalid WeChat login response');
    }
    final token = (rawUser['token'] ??
            rawUser['access_token'] ??
            rawUser['accessToken'] ??
            data['token'] ??
            '')
        .toString();
    if (token.isEmpty) {
      throw RemoteControlApiException(
          'WeChat login response contains no token');
    }
    final fallbackName =
        (rawUser['mobile'] ?? rawUser['id'] ?? 'wechat').toString();
    final user = <String, dynamic>{
      'name':
          (rawUser['username'] ?? rawUser['name'] ?? fallbackName).toString(),
      'display_name':
          (rawUser['nickname'] ?? rawUser['display_name'] ?? '').toString(),
      'avatar': (rawUser['avatar'] ?? '').toString(),
      'status': 1,
    };
    final member = data['member'];
    return RemoteControlLoginResult(
      token,
      user,
      member is Map<String, dynamic>
          ? RemoteControlMembership.fromJson(member)
          : const RemoteControlMembership(
              canControl: false,
              trialGiven: false,
              packageName: '',
              expireTime: '',
              remainingSeconds: 0,
              controlEnabled: null,
            ),
    );
  }

  static Future<RemoteControlMembership> membershipStatus() async {
    final token = bind.mainGetLocalOption(key: accessTokenKey);
    if (token.isEmpty) {
      throw RemoteControlApiException('请先登录');
    }
    final response = await http
        .get(Uri.parse('$server/api/remote/status'), headers: {'token': token});
    return RemoteControlMembership.fromJson(_decode(response));
  }

  static Future<RemoteControlMembership> claimTrial() async {
    final token = bind.mainGetLocalOption(key: accessTokenKey);
    if (token.isEmpty) {
      throw RemoteControlApiException('请先登录');
    }
    final response = await http.post(
      Uri.parse('$server/api/remote/claimtrial'),
      headers: {'token': token},
    );
    return RemoteControlMembership.fromJson(_decode(response));
  }

  static Future<List<RemoteControlPackage>> packages() async {
    final response = await http.get(Uri.parse('$server/api/remote/packages'));
    final packages = _decode(response)['packages'];
    if (packages is! List) {
      throw RemoteControlApiException('Invalid package response');
    }
    return packages
        .whereType<Map<String, dynamic>>()
        .map(RemoteControlPackage.fromJson)
        .where((package) => package.id > 0 && package.name.isNotEmpty)
        .toList();
  }

  static Future<RemoteControlPaymentOrder> createPaymentOrder(
      int packageId, String payType) async {
    final token = bind.mainGetLocalOption(key: accessTokenKey);
    if (token.isEmpty) {
      throw RemoteControlApiException('请先登录');
    }
    final response = await http.post(
      Uri.parse('$server/api/remote/order/create'),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'token': token,
      },
      body: Uri(queryParameters: {
        'package_id': packageId.toString(),
        'pay_type': payType,
      }).query,
    );
    final data = _decode(response);
    final order = data['order'];
    final payment = data['payment'];
    if (order is! Map<String, dynamic> || payment is! Map<String, dynamic>) {
      throw RemoteControlApiException('Invalid payment response');
    }
    final orderNo = (order['order_no'] ?? '').toString().trim();
    if (orderNo.isEmpty) {
      throw RemoteControlApiException(
          'Payment response contains no order number');
    }
    return RemoteControlPaymentOrder(orderNo: orderNo, payment: payment);
  }

  static Future<RemoteControlPaymentStatus> paymentStatus(
      String orderNo) async {
    final token = bind.mainGetLocalOption(key: accessTokenKey);
    if (token.isEmpty) {
      throw RemoteControlApiException('请先登录');
    }
    final uri = Uri.parse('$server/api/remote/order/status')
        .replace(queryParameters: {'order_no': orderNo});
    final response = await http.get(uri, headers: {'token': token});
    final order = _decode(response)['order'];
    if (order is! Map<String, dynamic>) {
      throw RemoteControlApiException('Invalid order status response');
    }
    return RemoteControlPaymentStatus(
      isComplete: order['status'] == 1 || order['status'] == '1',
      providerStatus: (order['payment_status'] ?? '').toString(),
    );
  }

  static Future<void> cancelPaymentOrder(String orderNo) async {
    final token = bind.mainGetLocalOption(key: accessTokenKey);
    if (token.isEmpty) {
      throw RemoteControlApiException('请先登录');
    }
    final response = await http.post(
      Uri.parse('$server/api/remote/order/cancel'),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'token': token,
      },
      body: Uri(queryParameters: {'order_no': orderNo}).query,
    );
    _decode(response);
  }

  static Future<bool> canControl() async {
    return (await membershipStatus()).canControl;
  }
}
