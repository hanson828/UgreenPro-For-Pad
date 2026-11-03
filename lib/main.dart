import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/login_screen.dart';
import 'services/app_lock_service.dart';
import 'theme/app_theme.dart';
import 'widgets/app_lock_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  // 先把应用锁状态读出来，避免首帧闪一下登录页再盖锁屏。
  await AppLockService.instance.load();
  runApp(const UgreenCloudShellApp());
}

class UgreenCloudShellApp extends StatelessWidget {
  const UgreenCloudShellApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '绿联云平板端',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      themeMode: ThemeMode.light,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // 应用锁盖在整个导航栈外面，进浏览器页之后同样会挡住。
      builder: (context, child) =>
          AppLockGate(child: child ?? const SizedBox.shrink()),
      home: const LoginScreen(),
    );
  }
}
