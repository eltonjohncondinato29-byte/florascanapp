part of '../main.dart';

// ==================== APP ROOT / AUTH GATE ====================
/// Root widget - manages authentication state and theme mode
class FloraScanApp extends StatefulWidget {
  const FloraScanApp({super.key});

  @override
  State<FloraScanApp> createState() => _FloraScanAppState();
}

class _FloraScanAppState extends State<FloraScanApp>
    with WidgetsBindingObserver {
  bool _authenticated = false;
  bool _authReady = false;
  bool _isDarkMode = false;
  late AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeAuthState();

    // Set up lifecycle listener for session expiry
    _lifecycleListener = AppLifecycleListener(
      onShow: _handleAppResumed,
      onPause: _handleAppPaused,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lifecycleListener.dispose();
    super.dispose();
  }

  /// Handles app being resumed - checks for session timeout
  /// If more than 5 minutes have passed, signs out the user
  Future<void> _handleAppResumed() async {
    final lastActiveTime = await _readSecureInt(_lastActiveTimeKey);
    if (lastActiveTime == 0) return; // First app launch

    final lastActive = DateTime.fromMillisecondsSinceEpoch(lastActiveTime);
    final now = DateTime.now();
    const sessionTimeout = Duration(minutes: 5);

    // If more than 5 minutes have passed, expire the session
    if (now.difference(lastActive) > sessionTimeout) {
      await supabase.auth.signOut();
      if (!mounted) return;
      setState(() {
        _authenticated = false;
      });
    }
  }

  /// Handles app being paused - records the time for session timeout tracking
  void _handleAppPaused() {
    // Record the time when app was paused
    unawaited(
      _writeSecureInt(
        _lastActiveTimeKey,
        DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// Handles user sign-out - clears authentication state
  Future<void> _handleSignOut() async {
    await supabase.auth.signOut();
    setState(() => _authenticated = false);
  }

  /// Handles successful sign-in - updates authentication state
  void _handleSignedIn() => setState(() => _authenticated = true);

  /// Initializes authentication state - signs out user on app start to show login screen
  Future<void> _initializeAuthState() async {
    // Always sign out on app start to show login screen
    await supabase.auth.signOut();

    if (!mounted) return;
    setState(() {
      _authenticated = false;
      _authReady = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FloraScan',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: kGreenMid),
        useMaterial3: true,
        fontFamily: 'sans-serif',
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: kGreenMid,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: 'sans-serif',
        brightness: Brightness.dark,
      ),
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: !_authReady
          ? const _AuthLoadingScreen()
          : _authenticated
          ? MyHomePage(
              title: 'FloraScan',
              onSignOut: _handleSignOut,
              onThemeChanged: (isDark) => setState(() => _isDarkMode = isDark),
              isDarkMode: _isDarkMode,
            )
          : AuthPage(onSignedIn: _handleSignedIn),
    );
  }
}

// --- Auth Page ----------------------------------------------------------------
