import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('commercial home uses the product flow instead of the legacy UI', () {
    final source = File(
      'lib/desktop/pages/simplelink_desktop_page.dart',
    ).readAsStringSync();
    final mainSource = File('lib/main.dart').readAsStringSync();

    final stackStart = source.indexOf('child: IndexedStack(');
    final productHome = source.indexOf('_ProductHomePage(', stackStart);
    final devicePage = source.indexOf('_DeviceListPage()', stackStart);
    final legacyHome = source.indexOf('DesktopHomePage(', stackStart);
    expect(stackStart, greaterThanOrEqualTo(0));
    expect(productHome, greaterThan(stackStart));
    expect(productHome, lessThan(devicePage));
    expect(devicePage, lessThan(legacyHome));
    expect(source, contains("ValueKey('simplelink-peer-id')"));
    expect(source, contains("ValueKey('simplelink-connect-button')"));
    expect(source, contains("label: '首页'"));
    expect(source, contains('const _LoginBanner()'));
    expect(source, contains('class _LoginBanner'));
    expect(source, isNot(contains('TextButton(onPressed: onLogin')));
    expect(source, contains('BoxConstraints(maxWidth: 980)'));
    expect(source, contains('EdgeInsets.all(24)'));
    expect(source, contains('fontSize: 34'));
    expect(source, contains('height: 236'));
    expect(source, contains('class _HomeTwoColumnLayout'));
    expect(
      source,
      contains('Expanded(flex: 48, child: leftColumn)'),
      reason:
          'Current device and recent sessions must stay in the left column.',
    );
    expect(source, contains('class _RecentPeerRow'));
    expect(source, contains('class _WindowActionButton'));
    expect(source, contains('onPressed: _hideToTray'));
    expect(source, contains('Future<void> _hideToTray() async'));
    expect(source, contains('with WindowListener'));
    expect(source, isNot(contains('onPressed: windowManager.close')));
    expect(source, isNot(contains('Icons.crop_square_rounded')));
    expect(source, isNot(contains('onDoubleTap: _toggleMaximize')));
    expect(source, contains("label: const Text('分享')"));
    expect(source, contains("label: const Text('复制ID')"));
    expect(source, contains('color: Colors.white'));
    expect(source, contains('await connect('));
    expect(mainSource, contains("windowManager.setTitle('简连远程助手')"));
    expect(mainSource, contains('const Size(1024, 730)'));
    expect(source, contains("label: '设备列表'"));
    expect(source, isNot(contains('class _RemoteAssistancePage')));
    expect(source, contains('class _DeviceListPage'));
    expect(source, contains('class _DeviceListRow'));
    expect(source, contains('Icons.filter_alt_outlined'));

    final desktopTabSource = File(
      'lib/desktop/pages/desktop_tab_page.dart',
    ).readAsStringSync();
    final directShell = desktopTabSource.indexOf(
      'body: SimpleLinkDesktopPage(',
    );
    final legacyTab = desktopTabSource.indexOf('body: DesktopTab(');
    expect(directShell, greaterThanOrEqualTo(0));
    expect(legacyTab, greaterThan(directShell));
  });
}
