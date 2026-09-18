import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import 'package:flutter_hbb/common/widgets/login.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/desktop_home_page.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/remote_control_api.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';

const _simpleLinkAutoStartOption = 'simplelink-auto-start';
const _simpleLinkCloseToTrayOption = 'simplelink-close-to-tray';

class SimpleLinkDesktopPage extends StatefulWidget {
  const SimpleLinkDesktopPage({
    Key? key,
    required this.onOpenSettings,
  }) : super(key: key);

  final VoidCallback onOpenSettings;

  @override
  State<SimpleLinkDesktopPage> createState() => _SimpleLinkDesktopPageState();
}

class _SimpleLinkDesktopPageState extends State<SimpleLinkDesktopPage>
    with WindowListener {
  static const _brandColor = Color(0xFF1769FF);
  static const _sidebarColor = Color(0xFFF7F9FC);
  static const _trayChannel = MethodChannel('org.rustdesk.rustdesk/tray');

  int _selectedPage = 0;
  bool _showLoginPage = false;
  bool _allowDestroyOnClose = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    unawaited(_ensureTrayIcon());
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _allowDestroyOnClose = true;
      }
    });
    _trayChannel.setMethodCallHandler((call) async {
      if (call.method == 'openSettings') {
        await windowManager.show();
        await windowManager.focus();
        _selectPage(3);
      }
    });
  }

  @override
  void dispose() {
    _trayChannel.setMethodCallHandler(null);
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _hideToTray() async {
    await _ensureTrayIcon();
    await windowManager.setPreventClose(true);
    await windowManager.hide();
  }

  Future<void> _ensureTrayIcon() async {
    if (!Platform.isWindows) {
      return;
    }
    try {
      await Process.start(
        Platform.resolvedExecutable,
        const ['--tray'],
        mode: ProcessStartMode.detached,
      );
    } catch (err) {
      debugPrint('Failed to start tray process: $err');
    }
  }

  Future<void> _quitAllProcesses() async {
    if (!Platform.isWindows) {
      await windowManager.destroy();
      return;
    }
    try {
      await windowManager.setPreventClose(false);
      await Process.start(
        Platform.resolvedExecutable,
        const ['--quit-all'],
        mode: ProcessStartMode.detached,
      );
    } catch (err) {
      debugPrint('Failed to quit all processes: $err');
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    }
  }

  @override
  void onWindowClose() async {
    if (_allowDestroyOnClose &&
        bind.mainGetLocalOption(key: _simpleLinkCloseToTrayOption) == 'N') {
      await _quitAllProcesses();
      return;
    }
    await _hideToTray();
    super.onWindowClose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          _buildTopBar(context, loginPage: _showLoginPage),
          const Divider(height: 1),
          Expanded(
            child: Row(
              children: [
                _buildSidebar(context),
                const VerticalDivider(width: 1),
                Expanded(
                  child: _showLoginPage
                      ? Stack(
                          children: [
                            const Offstage(
                              child: DesktopHomePage(
                                key: ValueKey(
                                    'simplelink-login-main-window-lifecycle'),
                              ),
                            ),
                            _SimpleLinkLoginPage(
                              onLoginSuccess: () => _selectPage(0),
                            ),
                          ],
                        )
                      : IndexedStack(
                          index: _selectedPage,
                          children: [
                            _ProductHomePage(
                              onOpenDevices: () => _selectPage(1),
                              onOpenMembership: () => _selectPage(2),
                            ),
                            const _DeviceListPage(),
                            _MembershipPage(onLogin: _openLoginPage),
                            const _SimpleLinkSettingsPage(),
                            // Keeps the existing main-window lifecycle active while
                            // the commercial pages replace its visible interface.
                            const DesktopHomePage(
                              key: ValueKey('simplelink-main-window-lifecycle'),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(BuildContext context) {
    return Container(
      width: 150,
      color: _sidebarColor,
      padding: const EdgeInsets.fromLTRB(12, 24, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _NavigationItem(
            icon: Icons.home_outlined,
            selectedIcon: Icons.home_rounded,
            label: '首页',
            selected: _selectedPage == 0,
            onTap: () => _selectPage(0),
          ),
          _NavigationItem(
            icon: Icons.devices_outlined,
            selectedIcon: Icons.devices_rounded,
            label: '设备列表',
            selected: _selectedPage == 1,
            onTap: () => _selectPage(1),
          ),
          _NavigationItem(
            icon: Icons.card_membership_outlined,
            selectedIcon: Icons.card_membership_rounded,
            label: '会员中心',
            selected: _selectedPage == 2,
            onTap: () => _selectPage(2),
          ),
          _NavigationItem(
            icon: Icons.settings_outlined,
            selectedIcon: Icons.settings_rounded,
            label: translate('Settings'),
            selected: _selectedPage == 3,
            onTap: () => _selectPage(3),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, {required bool loginPage}) {
    return Material(
      color: Colors.white,
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanStart: (_) => windowManager.startDragging(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: const Align(
                    alignment: Alignment.centerLeft,
                    child: _BrandMark(),
                  ),
                ),
              ),
            ),
            if (!loginPage)
              Obx(() {
                final userName = gFFI.userModel.userName.value;
                final isLoggedIn = userName.isNotEmpty;
                if (!isLoggedIn) {
                  return TextButton.icon(
                    onPressed: _openLoginPage,
                    icon: CircleAvatar(
                      radius: 13,
                      backgroundColor: _brandColor.withOpacity(0.12),
                      child: const Icon(
                        Icons.login,
                        color: _brandColor,
                        size: 15,
                      ),
                    ),
                    label: Text(translate('Login')),
                  );
                }
                return _AccountMenuButton(
                  userName: gFFI.userModel.displayNameOrUserName,
                  onProfile: () => _selectPage(2),
                  onLogout: logOutConfirmDialog,
                );
              }),
            const SizedBox(width: 6),
            _WindowActionButton(
              tooltip: translate('Minimize'),
              icon: Icons.remove_rounded,
              onPressed: windowManager.minimize,
            ),
            _WindowActionButton(
              tooltip: translate('Maximize'),
              icon: Icons.crop_square_rounded,
              onPressed: () async {
                if (await windowManager.isMaximized()) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              },
            ),
            _WindowActionButton(
              tooltip: '最小化到托盘',
              icon: Icons.close_rounded,
              onPressed: _hideToTray,
              close: true,
            ),
          ],
        ),
      ),
    );
  }

  void _selectPage(int page) {
    if (!_showLoginPage && _selectedPage == page) {
      return;
    }
    setState(() {
      _selectedPage = page;
      _showLoginPage = false;
    });
  }

  void _openLoginPage() {
    if (_showLoginPage) {
      return;
    }
    setState(() => _showLoginPage = true);
  }
}

enum _AccountMenuAction {
  profile,
  logout,
}

class _AccountMenuButton extends StatelessWidget {
  const _AccountMenuButton({
    required this.userName,
    required this.onProfile,
    required this.onLogout,
  });

  final String userName;
  final VoidCallback onProfile;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_AccountMenuAction>(
      tooltip: '账号菜单',
      offset: const Offset(0, 40),
      color: Colors.white,
      elevation: 8,
      constraints: const BoxConstraints(minWidth: 188),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      onSelected: (action) {
        switch (action) {
          case _AccountMenuAction.profile:
            onProfile();
            break;
          case _AccountMenuAction.logout:
            onLogout();
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
          child: _AccountMenuHeader(userName: userName),
        ),
        const PopupMenuItem(
          value: _AccountMenuAction.profile,
          height: 40,
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '个人信息',
            style: TextStyle(
              color: Color(0xFF334155),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const PopupMenuItem(
          value: _AccountMenuAction.logout,
          height: 40,
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '退出登录',
            style: TextStyle(
              color: Color(0xFFE5484D),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Container(
          height: 36,
          padding: const EdgeInsets.fromLTRB(8, 0, 10, 0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFDDE7F5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 13,
                backgroundColor: const Color(0xFFFFE8B7),
                child: const Icon(
                  Icons.person,
                  color: Color(0xFF111827),
                  size: 15,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                userName,
                style: const TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.keyboard_arrow_up_rounded,
                color: Color(0xFF64748B),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountMenuHeader extends StatelessWidget {
  const _AccountMenuHeader({required this.userName});

  final String userName;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F8FC),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 18,
            backgroundColor: Color(0xFF2F80ED),
            child: Text(
              '用',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  userName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  '微信已登录',
                  style: TextStyle(
                    color: Color(0xFF7A8798),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SimpleLinkLoginPage extends StatefulWidget {
  const _SimpleLinkLoginPage({
    required this.onLoginSuccess,
  });

  final VoidCallback onLoginSuccess;

  @override
  State<_SimpleLinkLoginPage> createState() => _SimpleLinkLoginPageState();
}

class _SimpleLinkLoginPageState extends State<_SimpleLinkLoginPage> {
  int _loginMode = 0;
  bool _showPasswordLogin = false;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF8FBFF),
      child: Stack(
        children: [
          const Positioned.fill(
            child:
                IgnorePointer(child: CustomPaint(painter: _HomeWavePainter())),
          ),
          const Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _LoginBackgroundPainter()),
            ),
          ),
          Center(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final horizontalPadding =
                    constraints.maxWidth < 900 ? 32.0 : 72.0;
                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    32,
                    horizontalPadding,
                    72,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      width: 1000,
                      child: Column(
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                flex: 13,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const _LoginPageHeadline(),
                                    const SizedBox(height: 30),
                                    _LoginPanel(
                                      selectedMode: _loginMode,
                                      showPasswordLogin: _showPasswordLogin,
                                      onLoginSuccess: widget.onLoginSuccess,
                                      onModeChanged: (mode) => setState(() {
                                        _loginMode = mode;
                                        _showPasswordLogin = false;
                                      }),
                                      onTogglePasswordLogin: () => setState(() {
                                        if (_showPasswordLogin) {
                                          _loginMode = 0;
                                          _showPasswordLogin = false;
                                        } else {
                                          _showPasswordLogin = true;
                                        }
                                      }),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 42),
                              const Expanded(
                                flex: 7,
                                child: _LoginBenefitsPanel(),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 26,
            child: _LoginSecurityNote(),
          ),
        ],
      ),
    );
  }
}

class _LoginPageHeadline extends StatelessWidget {
  const _LoginPageHeadline();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const _LargeBrandIcon(),
        const SizedBox(width: 22),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              '点连远程助手',
              style: TextStyle(
                color: Color(0xFF16213A),
                fontSize: 38,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 16),
            Text(
              '3秒连接电脑，远程协助更简单',
              style: TextStyle(
                color: Color(0xFF7B8494),
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LargeBrandIcon extends StatelessWidget {
  const _LargeBrandIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 68,
      height: 68,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2994FF), Color(0xFF1254DF)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2B1769FF),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: const Icon(Icons.link_rounded, color: Colors.white, size: 42),
    );
  }
}

class _LoginPanel extends StatelessWidget {
  const _LoginPanel({
    required this.selectedMode,
    required this.showPasswordLogin,
    required this.onLoginSuccess,
    required this.onModeChanged,
    required this.onTogglePasswordLogin,
  });

  final int selectedMode;
  final bool showPasswordLogin;
  final VoidCallback onLoginSuccess;
  final ValueChanged<int> onModeChanged;
  final VoidCallback onTogglePasswordLogin;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 500,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(44, 30, 44, 36),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE6EBF3)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1A15345F),
                  blurRadius: 22,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: SizedBox(
              height: 486,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: showPasswordLogin
                    ? _PasswordLoginContent(
                        key: ValueKey('simplelink-password-login'),
                        onLoginSuccess: onLoginSuccess,
                      )
                    : _TabbedLoginContent(
                        key: const ValueKey('simplelink-tabbed-login'),
                        selectedMode: selectedMode,
                        onLoginSuccess: onLoginSuccess,
                        onModeChanged: onModeChanged,
                      ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            child: _LoginModeCornerSwitch(
              showPasswordLogin: showPasswordLogin,
              onTap: onTogglePasswordLogin,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginModeCornerSwitch extends StatelessWidget {
  const _LoginModeCornerSwitch({
    required this.showPasswordLogin,
    required this.onTap,
  });

  final bool showPasswordLogin;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: showPasswordLogin ? '切换到微信登录' : '切换到用户名密码登录',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 70,
          height: 70,
          child: Stack(
            children: [
              ClipPath(
                clipper: const _LoginCornerClipper(),
                child: Container(color: const Color(0xFF5B86F7)),
              ),
              Positioned(
                left: 10,
                top: 10,
                child: Icon(
                  showPasswordLogin
                      ? Icons.qr_code_2_rounded
                      : Icons.desktop_windows_outlined,
                  color: Colors.white,
                  size: 27,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoginCornerClipper extends CustomClipper<Path> {
  const _LoginCornerClipper();

  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _TabbedLoginContent extends StatelessWidget {
  const _TabbedLoginContent({
    Key? key,
    required this.selectedMode,
    required this.onLoginSuccess,
    required this.onModeChanged,
  }) : super(key: key);

  final int selectedMode;
  final VoidCallback onLoginSuccess;
  final ValueChanged<int> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _LoginModeTabs(
          selectedMode: selectedMode,
          onModeChanged: onModeChanged,
        ),
        const SizedBox(height: 24),
        if (selectedMode == 0)
          _WechatLoginContent(onLoginSuccess: onLoginSuccess),
        if (selectedMode == 1)
          _MobileLoginContent(onLoginSuccess: onLoginSuccess),
      ],
    );
  }
}

class _LoginModeTabs extends StatelessWidget {
  const _LoginModeTabs({
    required this.selectedMode,
    required this.onModeChanged,
  });

  final int selectedMode;
  final ValueChanged<int> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _LoginModeTab(
          label: '微信扫码',
          selected: selectedMode == 0,
          onTap: () => onModeChanged(0),
        ),
        const SizedBox(width: 96),
        _LoginModeTab(
          label: '手机号登录',
          selected: selectedMode == 1,
          onTap: () => onModeChanged(1),
        ),
      ],
    );
  }
}

class _LoginModeTab extends StatelessWidget {
  const _LoginModeTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? const Color(0xFF1769FF)
                    : const Color(0xFF4E5869),
                fontSize: 21,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 11),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: selected ? 100 : 0,
              height: 4,
              decoration: BoxDecoration(
                color: selected ? const Color(0xFF1769FF) : Colors.transparent,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WechatLoginContent extends StatefulWidget {
  const _WechatLoginContent({
    Key? key,
    required this.onLoginSuccess,
  }) : super(key: key);

  final VoidCallback onLoginSuccess;

  @override
  State<_WechatLoginContent> createState() => _WechatLoginContentState();
}

class _WechatLoginContentState extends State<_WechatLoginContent> {
  static const _pollInterval = Duration(seconds: 2);

  Timer? _pollTimer;
  String _scene = '';
  String _qrUrl = '';
  String _statusText = '正在获取二维码...';
  String _errorText = '';
  bool _loading = false;
  bool _polling = false;
  DateTime? _expiresAt;

  @override
  void initState() {
    super.initState();
    _loadQrCode();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadQrCode() async {
    _pollTimer?.cancel();
    setState(() {
      _loading = true;
      _scene = '';
      _qrUrl = '';
      _errorText = '';
      _statusText = '正在获取二维码...';
      _expiresAt = null;
    });
    try {
      await RemoteControlApi.discoverAndSyncConfig();
      if (!RemoteControlApi.isConfigured) {
        throw RemoteControlApiException('请先配置 FastAdmin 会员系统地址');
      }
      final session = await RemoteControlApi.wechatQrLoginSession();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _scene = session.scene;
        _qrUrl = session.qrUrl;
        _statusText = '请使用微信扫码登录';
        _expiresAt = DateTime.now().add(Duration(seconds: session.expiresIn));
      });
      _pollTimer = Timer.periodic(_pollInterval, (_) => _pollLoginStatus());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _statusText = '二维码获取失败';
        _errorText = e.toString();
      });
    }
  }

  Future<void> _pollLoginStatus() async {
    if (_scene.isEmpty || _polling) return;
    final expiresAt = _expiresAt;
    if (expiresAt != null && DateTime.now().isAfter(expiresAt)) {
      _pollTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _statusText = '二维码已过期';
        _errorText = '请刷新二维码后重新扫码';
      });
      return;
    }
    _polling = true;
    try {
      final result = await RemoteControlApi.queryWechatQrLogin(_scene);
      if (result == null) {
        if (!mounted) return;
        setState(() {});
        return;
      }
      _pollTimer?.cancel();
      await gFFI.userModel.applyRemoteControlLoginResult(result);
      if (!mounted) return;
      setState(() {
        _statusText = '登录成功';
        _errorText = '';
      });
      showToast('微信登录成功');
      widget.onLoginSuccess();
    } catch (e) {
      _pollTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _statusText = '微信登录失败';
        _errorText = e.toString();
      });
    } finally {
      _polling = false;
    }
  }

  int get _remainingSeconds {
    final expiresAt = _expiresAt;
    if (expiresAt == null) return 0;
    final remaining = expiresAt.difference(DateTime.now()).inSeconds;
    return remaining > 0 ? remaining : 0;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          _statusText,
          style: TextStyle(
            color:
                _errorText.isEmpty ? const Color(0xFF16213A) : Colors.redAccent,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFFE6EBF3)),
          ),
          child: SizedBox(
            width: 238,
            height: 238,
            child: _buildQrCode(),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 30,
          child: _buildLoginHint(),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 20,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              SizedBox(
                width: 18,
                height: 18,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.all(Radius.circular(3)),
                    border: Border.fromBorderSide(
                      BorderSide(color: Color(0xFFB8C0CC)),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8),
              Text(
                '记住我的登录状态',
                style: TextStyle(
                  color: Color(0xFF5F6978),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQrCode() {
    if (_loading && _qrUrl.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_qrUrl.isEmpty) {
      return Center(
        child: IconButton(
          tooltip: '刷新二维码',
          icon: const Icon(Icons.refresh_rounded, color: Color(0xFF1769FF)),
          onPressed: _loadQrCode,
        ),
      );
    }
    return Image.network(
      _qrUrl,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) {
        return Center(
          child: IconButton(
            tooltip: '刷新二维码',
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF1769FF)),
            onPressed: _loadQrCode,
          ),
        );
      },
    );
  }

  Widget _buildLoginHint() {
    if (_errorText.isNotEmpty) {
      return TextButton.icon(
        onPressed: _loadQrCode,
        icon: const Icon(Icons.refresh_rounded, size: 18),
        label: const Text(
          '刷新二维码',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      );
    }
    if (_qrUrl.isEmpty) {
      return const SizedBox.shrink();
    }
    return Text(
      '二维码有效期倒计时 ${_remainingSeconds}秒',
      style: const TextStyle(
        color: Color(0xFF7B8494),
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _MobileLoginContent extends StatelessWidget {
  const _MobileLoginContent({
    Key? key,
    required this.onLoginSuccess,
  }) : super(key: key);

  final VoidCallback onLoginSuccess;

  Future<void> _openLoginDialog() async {
    final result = await loginDialog();
    if (result == true) {
      onLoginSuccess();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _LoginInput(
          icon: Icons.phone_iphone_outlined,
          hintText: '手机号',
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            const Expanded(
              child: _LoginInput(
                icon: Icons.verified_user_outlined,
                hintText: '验证码',
              ),
            ),
            const SizedBox(width: 14),
            SizedBox(
              height: 56,
              width: 132,
              child: OutlinedButton(
                onPressed: () {},
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1769FF),
                  side: const BorderSide(color: Color(0xFFD8E3F5)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                child: const Text(
                  '获取验证码',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 38),
        SizedBox(
          width: double.infinity,
          height: 58,
          child: ElevatedButton(
            onPressed: _openLoginDialog,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1769FF),
              foregroundColor: Colors.white,
              elevation: 6,
              shadowColor: const Color(0x4D1769FF),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: const Text(
              '登录',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }
}

class _PasswordLoginContent extends StatelessWidget {
  const _PasswordLoginContent({
    Key? key,
    required this.onLoginSuccess,
  }) : super(key: key);

  final VoidCallback onLoginSuccess;

  Future<void> _openLoginDialog() async {
    final result = await loginDialog();
    if (result == true) {
      onLoginSuccess();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 4),
        const Text(
          '密码登录',
          style: TextStyle(
            color: Color(0xFF16213A),
            fontSize: 28,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 30),
        const _LoginInput(
          icon: Icons.person_outline,
          hintText: '用户名',
        ),
        const SizedBox(height: 24),
        const _LoginInput(
          icon: Icons.lock_outline,
          hintText: '密码',
          obscureText: true,
        ),
        const SizedBox(height: 38),
        SizedBox(
          width: double.infinity,
          height: 58,
          child: ElevatedButton(
            onPressed: _openLoginDialog,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1769FF),
              foregroundColor: Colors.white,
              elevation: 6,
              shadowColor: const Color(0x4D1769FF),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: const Text(
              '登录',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(height: 26),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Text(
              '注册账号',
              style: TextStyle(
                color: Color(0xFF1769FF),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(width: 22),
            SizedBox(
              height: 18,
              child: VerticalDivider(width: 1, color: Color(0xFFD6DCE8)),
            ),
            SizedBox(width: 22),
            Text(
              '忘记密码',
              style: TextStyle(
                color: Color(0xFF1769FF),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LoginInput extends StatelessWidget {
  const _LoginInput({
    required this.icon,
    required this.hintText,
    this.obscureText = false,
  });

  final IconData icon;
  final String hintText;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: TextField(
        obscureText: obscureText,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: const TextStyle(
            color: Color(0xFFADB5C2),
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
          prefixIcon: Icon(icon, color: const Color(0xFF7E8898), size: 22),
          prefixIconConstraints: const BoxConstraints(minWidth: 54),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: Color(0xFFDDE3EC)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: Color(0xFF7FB1FF)),
          ),
        ),
      ),
    );
  }
}

class _LoginBenefitsPanel extends StatelessWidget {
  const _LoginBenefitsPanel();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: const [
        SizedBox(height: 14),
        _LoginDeviceIllustration(),
        SizedBox(height: 18),
        _BenefitRow(
          icon: Icons.devices_outlined,
          iconColor: Color(0xFF1769FF),
          backgroundColor: Color(0xFFEAF2FF),
          title: '手机/电脑都可远控',
          subtitle: '跨平台远程控制，随时随地高效协助',
        ),
        SizedBox(height: 14),
        _BenefitRow(
          icon: Icons.inventory_2_outlined,
          iconColor: Color(0xFF1769FF),
          backgroundColor: Color(0xFFEAF2FF),
          title: '设备管理',
          subtitle: '轻松管理设备，分组分类一目了然',
        ),
        SizedBox(height: 14),
        _BenefitRow(
          icon: Icons.workspace_premium_outlined,
          iconColor: Color(0xFFFF9B2F),
          backgroundColor: Color(0xFFFFF0DB),
          title: '会员订阅',
          subtitle: '灵活套餐选择，享受更多高级功能',
        ),
        SizedBox(height: 14),
        _BenefitRow(
          icon: Icons.support_agent_outlined,
          iconColor: Color(0xFF1769FF),
          backgroundColor: Color(0xFFEAF2FF),
          title: '企业售后支持',
          subtitle: '专业团队支持，快速响应售后无忧',
        ),
      ],
    );
  }
}

class _LoginDeviceIllustration extends StatelessWidget {
  const _LoginDeviceIllustration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 150,
      child: CustomPaint(
        painter: _LoginDevicePainter(),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: backgroundColor,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 23),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF273148),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFF8A93A3),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LoginSecurityNote extends StatelessWidget {
  const _LoginSecurityNote();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: const [
        Icon(Icons.lock_outline, color: Color(0xFF9AA3B2), size: 16),
        SizedBox(width: 8),
        Text(
          '数据传输全程加密，保障您的信息安全',
          style: TextStyle(color: Color(0xFF8A93A3), fontSize: 13),
        ),
      ],
    );
  }
}

class _LoginBackgroundPainter extends CustomPainter {
  const _LoginBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFEFF6FF)
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(size.width * 0.64, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height * 0.88)
      ..cubicTo(
        size.width * 0.86,
        size.height * 0.9,
        size.width * 0.78,
        size.height * 0.73,
        size.width * 0.64,
        size.height * 0.79,
      )
      ..cubicTo(
        size.width * 0.54,
        size.height * 0.84,
        size.width * 0.56,
        size.height * 0.44,
        size.width * 0.66,
        0,
      )
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LoginDevicePainter extends CustomPainter {
  const _LoginDevicePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.5, size.height * 0.72);
    final shadowPaint = Paint()..color = const Color(0x180D5EDB);
    canvas.drawOval(
      Rect.fromCenter(center: center, width: size.width * 0.62, height: 70),
      shadowPaint,
    );

    final laptopRect =
        Rect.fromLTWH(size.width * 0.24, size.height * 0.34, 142, 90);
    final laptopBody = RRect.fromRectAndRadius(
      laptopRect,
      const Radius.circular(5),
    );
    canvas.drawRRect(
      laptopBody,
      Paint()..color = const Color(0xFF123E8D),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        laptopRect.deflate(8),
        const Radius.circular(3),
      ),
      Paint()..color = const Color(0xFF1769FF),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.21, size.height * 0.76, 178, 16),
        const Radius.circular(5),
      ),
      Paint()..color = const Color(0xFFEAF2FF),
    );
    canvas.drawPath(
      Path()
        ..moveTo(size.width * 0.27, size.height * 0.68)
        ..lineTo(size.width * 0.65, size.height * 0.68)
        ..lineTo(size.width * 0.75, size.height * 0.76)
        ..lineTo(size.width * 0.18, size.height * 0.76)
        ..close(),
      Paint()..color = const Color(0xFFFFFFFF),
    );

    final phoneRect =
        Rect.fromLTWH(size.width * 0.69, size.height * 0.46, 52, 92);
    final phone = RRect.fromRectAndRadius(
      phoneRect,
      const Radius.circular(8),
    );
    canvas.drawRRect(phone, Paint()..color = const Color(0xFF123E8D));
    canvas.drawRRect(
      RRect.fromRectAndRadius(phoneRect.deflate(5), const Radius.circular(5)),
      Paint()..color = const Color(0xFF2F85FF),
    );

    final logoPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(size.width * 0.45, size.height * 0.55),
        radius: 13,
      ),
      2.35,
      3.4,
      false,
      logoPaint,
    );
    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(size.width * 0.51, size.height * 0.55),
        radius: 13,
      ),
      -0.8,
      3.4,
      false,
      logoPaint,
    );

    final phoneLogoPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(size.width * 0.74, size.height * 0.67),
        radius: 8,
      ),
      2.35,
      3.4,
      false,
      phoneLogoPaint,
    );
    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(size.width * 0.79, size.height * 0.67),
        radius: 8,
      ),
      -0.8,
      3.4,
      false,
      phoneLogoPaint,
    );

    final dashedPaint = Paint()
      ..color = const Color(0xFF7FB1FF)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < 8; i++) {
      final start = 0.4 + i * 0.32;
      canvas.drawArc(
        Rect.fromCenter(
          center: Offset(size.width * 0.62, size.height * 0.44),
          width: 118,
          height: 62,
        ),
        start,
        0.16,
        false,
        dashedPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _WindowActionButton extends StatelessWidget {
  const _WindowActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.close = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool close;

  @override
  Widget build(BuildContext context) {
    final hoverColor =
        close ? const Color(0xFFE81123) : const Color(0xFFEAF2FF);
    final foregroundColor = close ? Colors.white : const Color(0xFF445066);
    return SizedBox(
      width: 44,
      height: 44,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            hoverColor: hoverColor,
            child: Icon(icon, size: 17, color: close ? null : foregroundColor),
          ),
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2994FF), Color(0xFF1254DF)],
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Icon(Icons.link_rounded, color: Colors.white, size: 15),
        ),
        const SizedBox(width: 8),
        Text(
          '点连远程助手',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF17213A),
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const brandColor = Color(0xFF1769FF);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? const Color(0xFFEAF2FF) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Icon(
                  selected ? selectedIcon : icon,
                  size: 22,
                  color: selected ? brandColor : const Color(0xFF586174),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      color: selected ? brandColor : const Color(0xFF313746),
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
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

class _ProductHomePage extends StatelessWidget {
  const _ProductHomePage({
    required this.onOpenDevices,
    required this.onOpenMembership,
  });

  final VoidCallback onOpenDevices;
  final VoidCallback onOpenMembership;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF8FAFD),
      child: Stack(
        children: [
          const Positioned.fill(
            child:
                IgnorePointer(child: CustomPaint(painter: _HomeWavePainter())),
          ),
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 48),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _LoginBanner(onOpenMembership: onOpenMembership),
                    _HomeTwoColumnLayout(onOpenDevices: onOpenDevices),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeTwoColumnLayout extends StatelessWidget {
  const _HomeTwoColumnLayout({required this.onOpenDevices});

  final VoidCallback onOpenDevices;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final leftColumn = Column(
          children: [
            const _CurrentDeviceCard(),
            const SizedBox(height: 24),
            _RecentSessionsCard(onMore: onOpenDevices),
          ],
        );
        if (constraints.maxWidth < 560) {
          return Column(
            children: [
              leftColumn,
              const SizedBox(height: 24),
              const _QuickConnectCard(),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 48, child: leftColumn),
            const SizedBox(width: 24),
            const Expanded(flex: 52, child: _QuickConnectCard()),
          ],
        );
      },
    );
  }

}

class _LoginBanner extends StatelessWidget {
  const _LoginBanner({required this.onOpenMembership});

  final VoidCallback onOpenMembership;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () {
        final isLoggedIn = gFFI.userModel.userName.value.isNotEmpty;
        final membership = gFFI.userModel.remoteMembership.value;
        final isPaidMember = membership?.hasPaidMembership == true;
        final expiryLabel = isPaidMember ? '会员到期时间' : '体验到期时间';
        return Container(
          height: isLoggedIn ? 62 : 44,
          margin: const EdgeInsets.only(bottom: 24),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF3FF),
            border: Border.all(color: const Color(0xFFB9D4FF)),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.check_circle,
                color: Color(0xFF1769FF),
                size: 20,
              ),
              const SizedBox(width: 12),
              if (isLoggedIn) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1769FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.workspace_premium_rounded,
                        color: Colors.white,
                        size: 15,
                      ),
                      SizedBox(width: 4),
                      Text(
                        isPaidMember ? '会员' : '免费版',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: isLoggedIn
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            membership == null
                                ? '当前套餐：权益同步中'
                                : '当前套餐：${membership.entitlementName}',
                            style: const TextStyle(
                              color: Color(0xFF2354A1),
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            membership?.expireTime.isNotEmpty == true
                                ? '$expiryLabel：${membership!.expireTime}'
                                : '$expiryLabel：暂未获取',
                            style: const TextStyle(
                              color: Color(0xFF5F7190),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      )
                    : const Text(
                        '登录账号后可同步设备与会员权益',
                        style: TextStyle(
                          color: Color(0xFF2354A1),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
              if (isLoggedIn &&
                  membership != null &&
                  !membership.trialGiven &&
                  !isPaidMember) ...[
                const SizedBox(width: 12),
                const _ClaimTrialButton(compact: true),
              ] else if (isLoggedIn && membership != null) ...[
                const SizedBox(width: 12),
                SizedBox(
                  width: 104,
                  height: 34,
                  child: ElevatedButton(
                    onPressed: () => _openMembership(
                      context,
                      membership.canControl,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1769FF),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      '升级权益',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _openMembership(
    BuildContext context,
    bool hasActiveEntitlement,
  ) async {
    if (!hasActiveEntitlement) {
      onOpenMembership();
      return;
    }
    final shouldOpen = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('现有权益尚未结束'),
        content: const Text('升级套餐后，剩余权益时长将与新套餐时长累计计算。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('暂不升级'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('前往升级'),
          ),
        ],
      ),
    );
    if (shouldOpen == true) {
      onOpenMembership();
    }
  }
}

class _ClaimTrialButton extends StatelessWidget {
  const _ClaimTrialButton({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final claiming = gFFI.userModel.remoteTrialClaiming.value;
      return SizedBox(
        width: compact ? 114 : 128,
        height: compact ? 34 : 38,
        child: ElevatedButton(
          onPressed: claiming
              ? null
              : () async {
                  try {
                    await gFFI.userModel.claimRemoteControlTrial();
                    showToast('已领取 3 天免费体验');
                  } catch (e) {
                    showToast(e.toString());
                  }
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1769FF),
            foregroundColor: Colors.white,
            elevation: 0,
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(
            claiming ? '领取中...' : '领取 3 天体验',
            style: TextStyle(
              fontSize: compact ? 12 : 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    });
  }

}

class _CurrentDeviceCard extends StatelessWidget {
  const _CurrentDeviceCard();

  @override
  Widget build(BuildContext context) {
    final model = gFFI.serverModel;
    return _ProductCard(
      child: AnimatedBuilder(
        animation: model,
        builder: (context, child) {
          final serverConfigured = RemoteControlApi.hasRendezvousServer;
          final online = serverConfigured && model.connectStatus > 0;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _CardTitle(
                icon: Icons.devices_outlined,
                title: '当前设备',
              ),
              const SizedBox(height: 20),
              const Text(
                '您的设备 ID',
                style: TextStyle(color: Color(0xFF7A8394), fontSize: 14),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      model.serverId.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF1769FF),
                        fontSize: 34,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: online
                          ? const Color(0xFF19B76B)
                          : const Color(0xFFAAB1BD),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    online ? '在线' : '服务失联',
                    style: TextStyle(
                      fontSize: 13,
                      color: online
                          ? const Color(0xFF19B76B)
                          : const Color(0xFF7A8394),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _copyText(
                        context,
                        model.serverId.text,
                        '设备 ID 已复制',
                      ),
                      icon: const Icon(Icons.copy_outlined, size: 17),
                      label: const Text('复制ID'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        foregroundColor: const Color(0xFF1769FF),
                        side: const BorderSide(color: Color(0xFF1769FF)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _shareDevice(context),
                      icon: const Icon(Icons.share_outlined, size: 17),
                      label: const Text('分享'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        foregroundColor: const Color(0xFF1769FF),
                        side: const BorderSide(color: Color(0xFF1769FF)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                serverConfigured
                    ? '将设备 ID 和连接验证码告知伙伴，对方即可发起远程协助。'
                    : '服务失联，远程不可用，请先配置服务器。',
                style: TextStyle(
                  color: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.color
                      ?.withOpacity(0.58),
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _copyText(
    BuildContext context,
    String value,
    String message,
  ) async {
    if (value.isEmpty || value == '-') {
      return;
    }
    await Clipboard.setData(ClipboardData(text: value.replaceAll(' ', '')));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 1)),
      );
    }
  }

  Future<void> _shareDevice(BuildContext context) async {
    final model = gFFI.serverModel;
    final text = '设备 ID：${model.serverId.text}\n'
        '连接验证码：${model.serverPasswd.text}';
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('设备连接信息已复制，可粘贴发送给伙伴'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }
}

class _QuickConnectCard extends StatefulWidget {
  const _QuickConnectCard({this.large = false});

  final bool large;

  @override
  State<_QuickConnectCard> createState() => _QuickConnectCardState();
}

class _QuickConnectCardState extends State<_QuickConnectCard> {
  final _idController = IDTextEditingController();
  final _passwordController = TextEditingController();
  final _idFocusNode = FocusNode();
  bool _connecting = false;

  @override
  void dispose() {
    _idController.dispose();
    _passwordController.dispose();
    _idFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ProductCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(
            icon: Icons.add_link_rounded,
            title: '快速连接',
          ),
          SizedBox(height: widget.large ? 32 : 24),
          const Text('输入伙伴 ID', style: TextStyle(fontSize: 14)),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('simplelink-peer-id'),
            controller: _idController,
            focusNode: _idFocusNode,
            autofocus: widget.large,
            inputFormatters: [IDTextInputFormatter()],
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            decoration: _inputDecoration(
              hintText: '请输入伙伴的设备 ID',
              icon: Icons.person_outline,
            ),
          ),
          const SizedBox(height: 20),
          const Text('连接验证码（可选）', style: TextStyle(fontSize: 14)),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('simplelink-peer-password'),
            controller: _passwordController,
            obscureText: true,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _startConnection(),
            decoration: _inputDecoration(
              hintText: '无人值守设备可填写验证码',
              icon: Icons.lock_outline,
            ),
          ),
          SizedBox(height: widget.large ? 32 : 28),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              key: const ValueKey('simplelink-connect-button'),
              onPressed: _connecting ? null : _startConnection,
              icon: _connecting
                  ? const SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.desktop_windows_outlined, size: 22),
              label: Text(_connecting ? '正在连接…' : '连接远程电脑'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1769FF),
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hintText,
    required IconData icon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(
        color: Color(0xFF9AA3B2),
        fontSize: 14,
      ),
      prefixIcon: Icon(icon, size: 20),
      prefixIconConstraints: const BoxConstraints(minWidth: 48),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      filled: true,
      fillColor: const Color(0xFFFBFCFE),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFD9DFEA)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFD9DFEA)),
      ),
    );
  }

  Future<void> _startConnection() async {
    final id = trimID(_idController.text);
    if (id.isEmpty) {
      _idFocusNode.requestFocus();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入伙伴的设备 ID')),
      );
      return;
    }
    setState(() => _connecting = true);
    try {
      await connect(
        context,
        id,
        password: _passwordController.text.trim().isEmpty
            ? null
            : _passwordController.text.trim(),
      );
    } finally {
      if (mounted) {
        setState(() => _connecting = false);
      }
    }
  }
}

class _RecentSessionsCard extends StatefulWidget {
  const _RecentSessionsCard({required this.onMore});

  final VoidCallback onMore;

  @override
  State<_RecentSessionsCard> createState() => _RecentSessionsCardState();
}

class _RecentSessionsCardState extends State<_RecentSessionsCard> {
  @override
  void initState() {
    super.initState();
    bind.mainLoadRecentPeers();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 236,
      child: _ProductCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: _CardTitle(
                    icon: Icons.history_rounded,
                    title: '最近会话',
                  ),
                ),
                TextButton(
                  onPressed: widget.onMore,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('更多', style: TextStyle(fontSize: 13)),
                      Icon(Icons.chevron_right, size: 18),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: AnimatedBuilder(
                animation: gFFI.recentPeersModel,
                builder: (context, child) {
                  final peers = gFFI.recentPeersModel.peers.take(3).toList();
                  if (peers.isEmpty) {
                    return const Center(
                      child: Text(
                        '暂无最近会话',
                        style: TextStyle(color: Color(0xFF8A93A3)),
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (final peer in peers) _RecentPeerRow(peer: peer),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _RecentPeerAction { remoteControl, fileTransfer }

class _RecentPeerRow extends StatelessWidget {
  const _RecentPeerRow({required this.peer});

  final Peer peer;

  @override
  Widget build(BuildContext context) {
    final displayName = peer.alias.isNotEmpty
        ? peer.alias
        : peer.hostname.isNotEmpty
            ? peer.hostname
            : peer.username.isNotEmpty
                ? peer.username
                : peer.id;
    return SizedBox(
      height: 53,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => connect(context, peer.id),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2FF),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(
                Icons.desktop_windows_outlined,
                color: Color(0xFF1769FF),
                size: 21,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    formatID(peer.id),
                    style: const TextStyle(
                      color: Color(0xFF8A93A3),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: peer.online
                    ? const Color(0xFF19B76B)
                    : const Color(0xFFAAB1BD),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              peer.online ? '在线' : '离线',
              style: const TextStyle(color: Color(0xFF737D8E), fontSize: 12),
            ),
            PopupMenuButton<_RecentPeerAction>(
              padding: EdgeInsets.zero,
              iconSize: 19,
              tooltip: '更多',
              onSelected: (action) {
                connect(
                  context,
                  peer.id,
                  isFileTransfer: action == _RecentPeerAction.fileTransfer,
                );
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _RecentPeerAction.remoteControl,
                  child: Text('远程控制'),
                ),
                PopupMenuItem(
                  value: _RecentPeerAction.fileTransfer,
                  child: Text('文件传输'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeWavePainter extends CustomPainter {
  const _HomeWavePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final backWave = Path()
      ..moveTo(0, size.height * 0.78)
      ..cubicTo(
        size.width * 0.18,
        size.height * 0.67,
        size.width * 0.28,
        size.height * 0.93,
        size.width * 0.48,
        size.height * 0.82,
      )
      ..cubicTo(
        size.width * 0.68,
        size.height * 0.71,
        size.width * 0.81,
        size.height * 0.93,
        size.width,
        size.height * 0.78,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(backWave, Paint()..color = const Color(0xFFE8F2FF));

    final frontWave = Path()
      ..moveTo(0, size.height * 0.88)
      ..cubicTo(
        size.width * 0.22,
        size.height * 0.75,
        size.width * 0.38,
        size.height,
        size.width * 0.62,
        size.height * 0.88,
      )
      ..cubicTo(
        size.width * 0.78,
        size.height * 0.8,
        size.width * 0.9,
        size.height * 0.96,
        size.width,
        size.height * 0.86,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(frontWave, Paint()..color = const Color(0xFFF1F7FF));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE0E5ED)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A14294D),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _CardTitle extends StatelessWidget {
  const _CardTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF1769FF), size: 22),
        const SizedBox(width: 10),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}

class _DeviceListPage extends StatefulWidget {
  const _DeviceListPage();

  @override
  State<_DeviceListPage> createState() => _DeviceListPageState();
}

class _DeviceListPageState extends State<_DeviceListPage> {
  @override
  void initState() {
    super.initState();
    bind.mainLoadRecentPeers();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF8FAFD),
      child: AnimatedBuilder(
        animation: gFFI.recentPeersModel,
        builder: (context, _) {
          final peers = gFFI.recentPeersModel.peers
              .where((peer) => peer.id != gFFI.id)
              .toList();
          return SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: _ProductCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _DeviceSectionHeader(
                        title: '最近连接',
                        icon: Icons.history_rounded,
                      ),
                      const SizedBox(height: 24),
                      _DeviceSectionHeader(
                        title: '我的设备（${peers.length + 1}）',
                        icon: Icons.devices_rounded,
                        actions: [
                          IconButton(
                            onPressed: () {},
                            icon: const Icon(Icons.sort_rounded),
                            tooltip: '排序',
                          ),
                          IconButton(
                            onPressed: () {},
                            icon: const Icon(Icons.filter_alt_outlined),
                            tooltip: '筛选',
                          ),
                        ],
                      ),
                      const Divider(height: 20),
                      _DeviceListRow(
                        name: '本机设备',
                        platform: _platformLabel(kPeerPlatformWindows),
                        id: gFFI.id,
                        online: true,
                        isCurrent: true,
                      ),
                      ...peers.map(
                        (peer) => _DeviceListRow(
                          name: peer.alias.isNotEmpty
                              ? peer.alias
                              : (peer.hostname.isNotEmpty
                                  ? peer.hostname
                                  : peer.username.isNotEmpty
                                      ? peer.username
                                      : peer.id),
                          platform: _platformLabel(peer.platform),
                          id: peer.id,
                          online: peer.online,
                          onTap: () => connect(context, peer.id),
                        ),
                      ),
                      if (peers.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 36),
                          child: Center(
                            child: Text(
                              '暂无其他设备，输入设备 ID 即可快速连接',
                              style: TextStyle(color: Color(0xFF8A93A3)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DeviceSectionHeader extends StatelessWidget {
  const _DeviceSectionHeader(
      {required this.title, required this.icon, this.actions = const []});

  final String title;
  final IconData icon;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 21, color: const Color(0xFF1769FF)),
        const SizedBox(width: 10),
        Text(title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const Spacer(),
        ...actions,
      ],
    );
  }
}

class _DeviceListRow extends StatelessWidget {
  const _DeviceListRow(
      {required this.name,
      required this.platform,
      required this.id,
      required this.online,
      this.isCurrent = false,
      this.onTap});

  final String name;
  final String platform;
  final String id;
  final bool online;
  final bool isCurrent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final platformIcon = platform == 'Windows'
        ? Icons.window_rounded
        : platform == 'macOS' || platform == 'iPad'
            ? Icons.apple
            : platform == 'Android'
                ? Icons.android_rounded
                : Icons.devices_other_rounded;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                    color: online
                        ? const Color(0xFF19B76B)
                        : const Color(0xFFB6BDC8),
                    shape: BoxShape.circle)),
            const SizedBox(width: 14),
            Icon(platformIcon, size: 24, color: const Color(0xFF1769FF)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text('$platform · 北京市 · ${formatID(id)}',
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF8A93A3))),
                  ]),
            ),
            if (isCurrent)
              Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: const Color(0xFFEAF2FF),
                      borderRadius: BorderRadius.circular(6)),
                  child: const Text('本设备',
                      style: TextStyle(
                          color: Color(0xFF1769FF),
                          fontSize: 12,
                          fontWeight: FontWeight.w600))),
          ],
        ),
      ),
    );
  }
}

String _platformLabel(String platform) {
  if (platform == kPeerPlatformMacOS) return 'macOS';
  if (platform == kPeerPlatformAndroid) return 'Android';
  if (platform == kPeerPlatformLinux) return 'Linux';
  return 'Windows';
}

class _MembershipPage extends StatelessWidget {
  const _MembershipPage({required this.onLogin});

  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 18),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildAccountCard(context),
              const SizedBox(height: 18),
              const Text(
                '选择会员套餐',
                style: TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '开通会员，畅享稳定高效的远程控制体验',
                style: TextStyle(
                  color: Color(0xFF667085),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 18),
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _PlanCard(
                      days: '1天',
                      price: '¥0.99',
                      subtitle: '临时应急',
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: _PlanCard(
                      days: '7天',
                      price: '¥2.99',
                      subtitle: '短期使用',
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: _PlanCard(
                      days: '30天',
                      price: '¥6.99',
                      subtitle: '长期使用、主推',
                      recommended: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 34),
              Row(
                children: const [
                  Expanded(child: Divider(color: Color(0xFFCBD5E1))),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 18),
                    child: Text(
                      '简单连接，让远程更高效',
                      style: TextStyle(
                        color: Color(0xFF8492A6),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Expanded(child: Divider(color: Color(0xFFCBD5E1))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAccountCard(BuildContext context) {
    return Obx(() {
      final userName = gFFI.userModel.userName.value;
      final isLoggedIn = userName.isNotEmpty;
      final membership = gFFI.userModel.remoteMembership.value;
      final isPaidMember = membership?.hasPaidMembership == true;
      final expiryLabel = isPaidMember ? '会员到期时间' : '体验到期时间';
      return Container(
        height: 92,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFD8DEE9)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x08000000),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 28,
                backgroundColor: Color(0xFFEAF2FF),
                child: Icon(Icons.person, color: Color(0xFF1769FF), size: 30),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isLoggedIn
                          ? gFFI.userModel.displayNameOrUserName
                          : '账户',
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isLoggedIn
                          ? membership == null
                              ? '当前套餐：权益同步中'
                              : '当前套餐：${membership.entitlementName}  ·  $expiryLabel：${membership.expireTime.isEmpty ? '暂未获取' : membership.expireTime}'
                          : '登录后同步设备与会员权益',
                      style: const TextStyle(
                        color: Color(0xFF344054),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isLoggedIn)
                SizedBox(
                  width: 86,
                  height: 38,
                  child: ElevatedButton(
                    onPressed: onLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1769FF),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      '登录',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                )
              else if (membership != null &&
                  !membership.trialGiven &&
                  !isPaidMember)
                const _ClaimTrialButton(),
            ],
          ),
        ),
      );
    });
  }
}

class _SimpleLinkSettingsPage extends StatefulWidget {
  const _SimpleLinkSettingsPage();

  @override
  State<_SimpleLinkSettingsPage> createState() =>
      _SimpleLinkSettingsPageState();
}

class _SimpleLinkSettingsPageState extends State<_SimpleLinkSettingsPage> {
  static const _brandColor = Color(0xFF1769FF);

  late bool _autoStart;
  late bool _closeToTray;
  late bool _savedAutoStart;
  late bool _savedCloseToTray;

  @override
  void initState() {
    super.initState();
    _savedAutoStart =
        bind.mainGetLocalOption(key: _simpleLinkAutoStartOption) != 'N';
    _savedCloseToTray =
        bind.mainGetLocalOption(key: _simpleLinkCloseToTrayOption) != 'N';
    _autoStart = _savedAutoStart;
    _closeToTray = _savedCloseToTray;
  }

  Future<void> _save() async {
    await bind.mainSetLocalOption(
      key: _simpleLinkAutoStartOption,
      value: _autoStart ? 'Y' : 'N',
    );
    await bind.mainSetLocalOption(
      key: _simpleLinkCloseToTrayOption,
      value: _closeToTray ? 'Y' : 'N',
    );
    if (!mounted) return;
    setState(() {
      _savedAutoStart = _autoStart;
      _savedCloseToTray = _closeToTray;
    });
    showToast('设置已保存');
  }

  void _cancel() {
    setState(() {
      _autoStart = _savedAutoStart;
      _closeToTray = _savedCloseToTray;
    });
    bind.mainSetLocalOption(
      key: _simpleLinkCloseToTrayOption,
      value: _savedCloseToTray ? 'Y' : 'N',
    );
  }

  void _restoreDefaults() {
    setState(() {
      _autoStart = true;
      _closeToTray = true;
    });
    bind.mainSetLocalOption(
      key: _simpleLinkCloseToTrayOption,
      value: 'Y',
    );
  }

  void _setCloseToTray(bool value) {
    setState(() => _closeToTray = value);
    bind.mainSetLocalOption(
      key: _simpleLinkCloseToTrayOption,
      value: value ? 'Y' : 'N',
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF7FAFF),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE4EAF4)),
          ),
          child: Column(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(32, 28, 32, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '常规设置',
                            style: TextStyle(
                              color: Color(0xFF111827),
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _SettingsCheckRow(
                            title: '开机时自动启动',
                            value: _autoStart,
                            onChanged: (value) =>
                                setState(() => _autoStart = value),
                          ),
                          _SettingsCheckRow(
                            title: '关闭窗口时最小化到托盘',
                            value: _closeToTray,
                            onChanged: _setCloseToTray,
                          ),
                          const SizedBox(height: 12),
                          const Divider(height: 1, color: Color(0xFFE4EAF4)),
                          _SettingsActionRow(
                            icon: Icons.refresh_rounded,
                            title: '检查更新',
                            onTap: () => showToast('检查更新功能暂未接入'),
                          ),
                          const Divider(height: 1, color: Color(0xFFE4EAF4)),
                          _SettingsActionRow(
                            icon: Icons.language_rounded,
                            title: '官方网站',
                            onTap: () => showToast('官方网站暂未配置'),
                          ),
                          const Divider(height: 1, color: Color(0xFFE4EAF4)),
                          _SettingsActionRow(
                            icon: Icons.description_outlined,
                            title: '用户协议',
                            onTap: () => showToast('用户协议暂未配置'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE4EAF4)),
              SizedBox(
                height: 76,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      SizedBox(
                        height: 38,
                        child: OutlinedButton.icon(
                          onPressed: _restoreDefaults,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('恢复默认设置'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF334155),
                            side:
                                const BorderSide(color: Color(0xFFDDE5F0)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      SizedBox(
                        width: 88,
                        height: 38,
                        child: OutlinedButton(
                          onPressed: _cancel,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF334155),
                            side:
                                const BorderSide(color: Color(0xFFDDE5F0)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          child: const Text('取消'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 96,
                        height: 38,
                        child: ElevatedButton(
                          onPressed: _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _brandColor,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          child: const Text('保存'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsCheckRow extends StatelessWidget {
  const _SettingsCheckRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: value,
              onChanged: (value) => onChanged(value ?? false),
              activeColor: const Color(0xFF1769FF),
              side: const BorderSide(color: Color(0xFFBAC6D8)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(width: 18),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF1F2937),
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsActionRow extends StatelessWidget {
  const _SettingsActionRow({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 62,
        child: Row(
          children: [
            Icon(icon, size: 22, color: const Color(0xFF1F2937)),
            const SizedBox(width: 18),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF1F2937),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF1F2937),
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.days,
    required this.price,
    required this.subtitle,
    this.recommended = false,
  });

  final String days;
  final String price;
  final String subtitle;
  final bool recommended;

  @override
  Widget build(BuildContext context) {
    const brandColor = Color(0xFF1769FF);
    const features = ['远程连接', '文件传输', '高清画质', '多设备使用'];
    return Container(
      height: 350,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: recommended ? const Color(0xFFF7FBFF) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: recommended ? brandColor : const Color(0xFFDDE5F0),
          width: recommended ? 2 : 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          if (recommended)
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                width: 72,
                height: 36,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: brandColor,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(10),
                  ),
                ),
                child: const Text(
                  '推荐',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_month_rounded,
                      color: brandColor,
                      size: 24,
                    ),
                    const SizedBox(width: 14),
                    Text(
                      days,
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  price,
                  style: const TextStyle(
                    color: brandColor,
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF4B5563),
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                const Divider(color: Color(0xFFDDE5F0), height: 1),
                const SizedBox(height: 10),
                for (final feature in features)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          color: brandColor,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            feature,
                            style: const TextStyle(
                              color: Color(0xFF344054),
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: recommended
                      ? ElevatedButton(
                          onPressed: () => showToast('支付功能暂未接入'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: brandColor,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            '立即开通',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        )
                      : OutlinedButton(
                          onPressed: () => showToast('支付功能暂未接入'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: brandColor,
                            side: const BorderSide(color: Color(0xFF94BFFF)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            '立即开通',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
