import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import 'package:flutter_hbb/common/widgets/login.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/desktop_home_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';

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

  int _selectedPage = 0;
  bool _showLoginPage = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
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

  @override
  void onWindowClose() async {
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
                      ? const Stack(
                          children: [
                            Offstage(
                              child: DesktopHomePage(
                                key: ValueKey(
                                    'simplelink-login-main-window-lifecycle'),
                              ),
                            ),
                            _SimpleLinkLoginPage(),
                          ],
                        )
                      : IndexedStack(
                          index: _selectedPage,
                          children: [
                            _ProductHomePage(
                              onOpenDevices: () => _selectPage(1),
                            ),
                            const _DeviceListPage(),
                            const _MembershipPage(),
                            DesktopSettingPage(
                              key: const ValueKey('simplelink-settings-page'),
                              initialTabkey: SettingsTabKey.general,
                            ),
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
            icon: Icons.workspace_premium_outlined,
            selectedIcon: Icons.workspace_premium_rounded,
            label: '会员',
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
            if (loginPage)
              _WindowActionButton(
                tooltip: translate('Settings'),
                icon: Icons.settings_outlined,
                onPressed: () => _selectPage(3),
              )
            else
              Obx(() {
                final userName = gFFI.userModel.userName.value;
                final isLoggedIn = userName.isNotEmpty;
                return TextButton.icon(
                  onPressed: isLoggedIn ? () => _selectPage(2) : _openLoginPage,
                  icon: CircleAvatar(
                    radius: 13,
                    backgroundColor: _brandColor.withOpacity(0.12),
                    child: Icon(
                      isLoggedIn ? Icons.person : Icons.login,
                      color: _brandColor,
                      size: 15,
                    ),
                  ),
                  label: Text(
                    isLoggedIn
                        ? gFFI.userModel.displayNameOrUserName
                        : translate('Login'),
                  ),
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

class _SimpleLinkLoginPage extends StatefulWidget {
  const _SimpleLinkLoginPage();

  @override
  State<_SimpleLinkLoginPage> createState() => _SimpleLinkLoginPageState();
}

class _SimpleLinkLoginPageState extends State<_SimpleLinkLoginPage> {
  int _loginMode = 0;

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
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(72, 48, 72, 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          flex: 11,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const _LoginPageHeadline(),
                              const SizedBox(height: 30),
                              _LoginPanel(
                                selectedMode: _loginMode,
                                onModeChanged: (mode) =>
                                    setState(() => _loginMode = mode),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 64),
                        const Expanded(
                          flex: 9,
                          child: _LoginBenefitsPanel(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 46),
                    const _LoginSecurityNote(),
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
              '简连远程助手',
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
    required this.onModeChanged,
  });

  final int selectedMode;
  final ValueChanged<int> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 438,
      padding: const EdgeInsets.fromLTRB(36, 28, 36, 34),
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
      child: Column(
        children: [
          _LoginModeTabs(
            selectedMode: selectedMode,
            onModeChanged: onModeChanged,
          ),
          const SizedBox(height: 30),
          _LoginInput(
            icon: Icons.phone_iphone_outlined,
            hintText: selectedMode == 0 ? '手机号' : '手机号 / 邮箱',
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: _LoginInput(
                  icon: selectedMode == 0
                      ? Icons.verified_user_outlined
                      : Icons.lock_outline,
                  hintText: selectedMode == 0 ? '验证码' : '密码',
                  obscureText: selectedMode == 1,
                ),
              ),
              if (selectedMode == 0) ...[
                const SizedBox(width: 14),
                SizedBox(
                  height: 50,
                  width: 118,
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
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 36),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: loginDialog,
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
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
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
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
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
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
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
          label: '手机号登录',
          selected: selectedMode == 0,
          onTap: () => onModeChanged(0),
        ),
        const SizedBox(width: 78),
        _LoginModeTab(
          label: '密码登录',
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
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? const Color(0xFF1769FF)
                    : const Color(0xFF4E5869),
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: selected ? 80 : 0,
              height: 3,
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
      height: 50,
      child: TextField(
        obscureText: obscureText,
        style: const TextStyle(fontSize: 15),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: const TextStyle(
            color: Color(0xFFADB5C2),
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          prefixIcon: Icon(icon, color: const Color(0xFF7E8898), size: 20),
          prefixIconConstraints: const BoxConstraints(minWidth: 48),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
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
        SizedBox(height: 26),
        _LoginDeviceIllustration(),
        SizedBox(height: 26),
        _BenefitRow(
          icon: Icons.devices_outlined,
          iconColor: Color(0xFF1769FF),
          backgroundColor: Color(0xFFEAF2FF),
          title: '手机/电脑都可远控',
          subtitle: '跨平台远程控制，随时随地高效协助',
        ),
        SizedBox(height: 20),
        _BenefitRow(
          icon: Icons.inventory_2_outlined,
          iconColor: Color(0xFF1769FF),
          backgroundColor: Color(0xFFEAF2FF),
          title: '设备管理',
          subtitle: '轻松管理设备，分组分类一目了然',
        ),
        SizedBox(height: 20),
        _BenefitRow(
          icon: Icons.workspace_premium_outlined,
          iconColor: Color(0xFFFF9B2F),
          backgroundColor: Color(0xFFFFF0DB),
          title: '会员订阅',
          subtitle: '灵活套餐选择，享受更多高级功能',
        ),
        SizedBox(height: 20),
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
      height: 210,
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
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: backgroundColor,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 28),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF273148),
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFF8A93A3),
                  fontSize: 13,
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
          '简连远程助手',
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
  const _ProductHomePage({required this.onOpenDevices});

  final VoidCallback onOpenDevices;

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
                    const _LoginBanner(),
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
  const _LoginBanner();

  @override
  Widget build(BuildContext context) {
    return Obx(
      () {
        final isLoggedIn = gFFI.userModel.userName.value.isNotEmpty;
        return Container(
          height: 44,
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
              Expanded(
                child: Text(
                  isLoggedIn ? '已登录账号，可同步设备与会员权益' : '登录账号后可同步设备与会员权益',
                  style: const TextStyle(
                    color: Color(0xFF2354A1),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(Icons.close, color: Color(0xFF91A8CC), size: 18),
            ],
          ),
        );
      },
    );
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
          final online = model.connectStatus > 0;
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
                    online ? '在线' : '离线',
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
                '将设备 ID 和连接验证码告知伙伴，对方即可发起远程协助。',
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
  const _MembershipPage();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildAccountCard(context),
              const SizedBox(height: 18),
              Wrap(
                spacing: 18,
                runSpacing: 18,
                children: const [
                  _PlanCard(
                    name: '个人版',
                    price: '¥99 / 年',
                    features: [
                      '无限远程连接',
                      '文件传输',
                      '高清画质',
                      '手机控制电脑',
                      '多设备管理',
                    ],
                    highlighted: true,
                  ),
                  _PlanCard(
                    name: '企业版',
                    price: '¥2999 / 年起',
                    features: [
                      '企业账号',
                      '多设备管理',
                      '连接日志',
                      '专属技术支持',
                      '权限与组织管理',
                    ],
                  ),
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
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Theme.of(context).dividerColor),
        ),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 27,
                backgroundColor: Color(0xFFEAF2FF),
                child: Icon(Icons.person, color: Color(0xFF1769FF), size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isLoggedIn
                          ? gFFI.userModel.displayNameOrUserName
                          : translate('Account'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(isLoggedIn ? '当前套餐：免费版' : '登录后同步设备与会员权益'),
                  ],
                ),
              ),
              if (!isLoggedIn)
                ElevatedButton(
                  onPressed: loginDialog,
                  child: Text(translate('Login')),
                ),
            ],
          ),
        ),
      );
    });
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.name,
    required this.price,
    required this.features,
    this.highlighted = false,
  });

  final String name;
  final String price;
  final List<String> features;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    const brandColor = Color(0xFF1769FF);
    return SizedBox(
      width: 360,
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: highlighted ? brandColor : Theme.of(context).dividerColor,
            width: highlighted ? 1.5 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.workspace_premium_rounded,
                    color: highlighted ? const Color(0xFFFFA53D) : brandColor,
                  ),
                  const SizedBox(width: 9),
                  Text(
                    name,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                price,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: brandColor,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 18),
              for (final feature in features)
                Padding(
                  padding: const EdgeInsets.only(bottom: 11),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        color: brandColor,
                        size: 18,
                      ),
                      const SizedBox(width: 9),
                      Expanded(child: Text(feature)),
                    ],
                  ),
                ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: null,
                  child: const Text('支付接入后开放'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
