import 'dart:convert';

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
  RemoteControlLoginResult(this.token, this.user, this.canControl);

  final String token;
  final Map<String, dynamic> user;
  final bool canControl;
}

class RemoteControlApi {
  static bool get isConfigured => server.isNotEmpty;

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
      await bind.mainSetLocalOption(key: _backendMarker, value: 'Y');
      await bind.mainSetOption(
          key: 'custom-rendezvous-server',
          value: (data['id_server'] ?? '').toString());
      await bind.mainSetOption(
          key: 'relay-server', value: (data['relay_server'] ?? '').toString());
      await bind.mainSetOption(
          key: 'key', value: (data['public_key'] ?? '').toString());
      await bind.mainSetOption(
          key: 'api-server', value: (data['api_server'] ?? '').toString());
      return true;
    } catch (_) {
      if (isEnabled) rethrow;
      return false;
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
    return RemoteControlLoginResult(token, user, member['can_control'] == true);
  }

  static Future<bool> canControl() async {
    final baseUrl = server;
    final token = bind.mainGetLocalOption(key: 'access_token');
    if (token.isEmpty) {
      throw RemoteControlApiException('请先登录');
    }
    final response = await http.get(Uri.parse('$baseUrl/api/remote/status'),
        headers: {'token': token});
    return _decode(response)['can_control'] == true;
  }
}
