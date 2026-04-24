import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'theme/botanical_theme.dart';
import 'screens/splash_screen.dart';
import 'services/fcm_service.dart';
import 'services/firebase_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseMessaging.onBackgroundMessage(onFcmBackgroundMessage);
  await Hive.initFlutter();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  runApp(const CheonhongApp());
}

class CheonhongApp extends StatefulWidget {
  const CheonhongApp({super.key});

  @override
  State<CheonhongApp> createState() => _CheonhongAppState();
}

class _CheonhongAppState extends State<CheonhongApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      FirebaseService().checkDayRollover()
          .timeout(const Duration(seconds: 5))
          .catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'CHEONHONG STUDIO',
      debugShowCheckedModeBanner: false,
      theme: BotanicalTheme.light(),
      themeMode: ThemeMode.light,
      home: const SplashScreen(),
    );
  }
}