import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Global reference for Supabase
late final SupabaseClient supabase;
const appSecureStorage = FlutterSecureStorage();
const _rememberMeKey = 'remember_me';
const _rememberedEmailKey = 'remembered_email';

// Rate limiting constants
const _loginAttemptsKey = 'login_attempts';
const _loginAttemptTimestampKey = 'login_attempt_timestamp';
const _maxLoginAttempts = 5;
const _loginCooldownDuration = Duration(minutes: 5);

// Session expiry constants
const _lastActiveTimeKey = 'last_active_time';

Future<bool> _readSecureBool(String key) async {
  return await appSecureStorage.read(key: key) == 'true';
}

Future<void> _writeSecureBool(String key, bool value) async {
  await appSecureStorage.write(key: key, value: value.toString());
}

Future<int> _readSecureInt(String key) async {
  final value = await appSecureStorage.read(key: key);
  return int.tryParse(value ?? '') ?? 0;
}

Future<void> _writeSecureInt(String key, int value) async {
  await appSecureStorage.write(key: key, value: value.toString());
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://jhnieqvxetoymdagmaqj.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpobmllcXZ4ZXRveW1kYWdtYXFqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYxMjEzODUsImV4cCI6MjA5MTY5NzM4NX0.ePriJ0Wr4NJXV4m5Hy8aIV4iuF0mUYK4-uGQQyHZzSE',
  );

  supabase = Supabase.instance.client;
  runApp(const FloraScanApp());
}

// ─── Theme Colors ────────────────────────────────────────────────────────────
const kGreenDark = Color(0xFF1B5E20);
const kGreenMid = Color(0xFF2E7D32);
const kGreenAccent = Color(0xFF4CAF50);
const kGreenLight = Color(0xFFA5D6A7);
const kGreenPale = Color(0xFFE8F5E9);
const kGreenGradientTop = Color(0xFFFFFFFF);
const kGreenGradientBottom = Color(0xFFB9F5CB);
const kCardBg = Colors.white;
const kTextDark = Color(0xFF1C3A21);
const kTextMid = Color(0xFF4A4A4A);
const kTextLight = Color(0xFF8A8A8A);
const kDivider = Color(0xFFEEEEEE);

// ==================== APP ROOT / AUTH GATE ====================
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

  /// Handles app being shown/resumed
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

  /// Handles app being paused/minimized
  void _handleAppPaused() {
    // Record the time when app was paused
    unawaited(
      _writeSecureInt(
        _lastActiveTimeKey,
        DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> _handleSignOut() async {
    await supabase.auth.signOut();
    setState(() => _authenticated = false);
  }

  void _handleSignedIn() => setState(() => _authenticated = true);

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

// ─── Auth Page ────────────────────────────────────────────────────────────────

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, required this.onSignedIn});
  final VoidCallback onSignedIn;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = false;
  String? _errorMessage;
  static const int _signupLimit = 5;

  @override
  void initState() {
    super.initState();
    _loadRememberedLogin();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ─── Password Strength Validation ─────────────────────────────────────────

  /// Returns null if valid, or an error string describing what's missing.
  String? _validatePassword(String password) {
    if (password.length < 8) {
      return 'Password must be at least 8 characters.';
    }
    if (!password.contains(RegExp(r'[A-Z]'))) {
      return 'Password must contain at least one uppercase letter.';
    }
    if (!password.contains(RegExp(r'[a-z]'))) {
      return 'Password must contain at least one lowercase letter.';
    }
    if (!password.contains(RegExp(r'[0-9]'))) {
      return 'Password must contain at least one number.';
    }
    if (!password.contains(
      RegExp(r'[!@#\$%^&*(),.?":{}|<>_\-+=\[\]\\\/`~;]'),
    )) {
      return 'Password must contain at least one symbol (e.g. @, #, !).';
    }
    return null;
  }

  /// Returns a color-coded strength label.
  _PasswordStrength _getStrength(String password) {
    int score = 0;
    if (password.length >= 8) {
      score++;
    }
    if (password.contains(RegExp(r'[A-Z]'))) {
      score++;
    }
    if (password.contains(RegExp(r'[a-z]'))) {
      score++;
    }
    if (password.contains(RegExp(r'[0-9]'))) {
      score++;
    }
    if (password.contains(RegExp(r'[!@#\$%^&*(),.?":{}|<>_\-+=\[\]\\\/`~;]'))) {
      score++;
    }

    if (score <= 2) {
      return _PasswordStrength.weak;
    }
    if (score <= 4) {
      return _PasswordStrength.medium;
    }
    return _PasswordStrength.strong;
  }

  void _onPasswordChanged(String value) {
    setState(() {}); // rebuild to update the strength bar live
  }

  Future<void> _loadRememberedLogin() async {
    final shouldRemember = await _readSecureBool(_rememberMeKey);
    final rememberedEmail =
        await appSecureStorage.read(key: _rememberedEmailKey) ?? '';

    if (!mounted) return;
    setState(() {
      _rememberMe = shouldRemember;
      if (shouldRemember && rememberedEmail.isNotEmpty) {
        _emailController.text = rememberedEmail;
      }
    });
  }

  Future<void> _persistLoginPreference(String email) async {
    await _writeSecureBool(_rememberMeKey, _rememberMe);
    if (_rememberMe) {
      await appSecureStorage.write(key: _rememberedEmailKey, value: email);
      return;
    }
    await appSecureStorage.delete(key: _rememberedEmailKey);
  }

  Future<void> _showForgotPasswordDialog() async {
    final resetEmailController = TextEditingController(
      text: _emailController.text.trim(),
    );
    final navigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    String? dialogError;
    var dialogLoading = false;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> sendReset() async {
              final email = resetEmailController.text.trim();
              var resetSent = false;
              if (email.isEmpty) {
                setDialogState(
                  () => dialogError = 'Enter the email for your account.',
                );
                return;
              }

              setDialogState(() {
                dialogLoading = true;
                dialogError = null;
              });

              try {
                await supabase.auth.resetPasswordForEmail(email);
                if (!mounted) return;
                _emailController.text = email;
                resetSent = true;
                navigator.pop();
                scaffoldMessenger.showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Password reset email sent. Check your inbox.',
                    ),
                  ),
                );
              } catch (_) {
                setDialogState(() {
                  dialogError =
                      'Unable to send reset email right now. Please try again.';
                });
              } finally {
                if (mounted && !resetSent) {
                  setDialogState(() => dialogLoading = false);
                }
              }
            }

            return AlertDialog(
              title: const Text('Reset password'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Enter your email and we will send a password reset link.',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: resetEmailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (dialogError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      dialogError!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: dialogLoading
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: dialogLoading ? null : sendReset,
                  child: dialogLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Send'),
                ),
              ],
            );
          },
        );
      },
    );

    resetEmailController.dispose();
  }

  Future<void> _submit() async {
    setState(() => _errorMessage = null);

    final email = _emailController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty || (!_isLogin && username.isEmpty)) {
      setState(() => _errorMessage = 'Please fill all required fields.');
      return;
    }

    // Check if user is in cooldown (only for login)
    if (_isLogin && await _isInCooldown()) {
      final remainingSeconds = await _getRemainingCooldownSeconds();
      setState(
        () => _errorMessage =
            'Too many failed login attempts. Try again in ${_formatCooldownTime(remainingSeconds)}',
      );
      return;
    }

    // Password strength check on signup
    if (!_isLogin) {
      final pwError = _validatePassword(password);
      if (pwError != null) {
        setState(() => _errorMessage = pwError);
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      if (_isLogin) {
        final response = await supabase.auth.signInWithPassword(
          email: email,
          password: password,
        );
        if (response.user == null && response.session == null) {
          // Login failed - increment failed attempts
          await _incrementLoginAttempts();
          final attempts = await _readSecureInt(_loginAttemptsKey);
          final remainingAttempts = _maxLoginAttempts - attempts;

          if (remainingAttempts <= 0) {
            final remainingSeconds = await _getRemainingCooldownSeconds();
            setState(
              () => _errorMessage =
                  'Account locked. Try again in ${_formatCooldownTime(remainingSeconds)}',
            );
          } else {
            setState(
              () => _errorMessage =
                  'Unable to sign in. Check your credentials. ($remainingAttempts attempts remaining)',
            );
          }
        } else {
          // Login successful - reset failed attempts
          await _resetLoginAttempts();
          await _persistLoginPreference(email);
          widget.onSignedIn();
        }
      } else {
        final canSignUp = await _checkSignupLimit();
        if (!canSignUp) return;

        final response = await supabase.auth.signUp(
          email: email,
          password: password,
          data: {'username': username},
        );

        if (response.user == null) {
          setState(
            () => _errorMessage =
                'Sign up failed. Please verify your email and try again.',
          );
        } else {
          if (response.session != null) {
            widget.onSignedIn();
          } else {
            setState(() {
              _errorMessage =
                  'Sign up succeeded. Please confirm your email and log in.';
              _isLogin = true;
            });
          }
        }
      }
    } catch (error) {
      final msg = error.toString().toLowerCase();
      setState(() {
        if (msg.contains('over_email_send_rate_limit')) {
          _errorMessage =
              'Too many signup attempts. Wait a few minutes and try again.';
        } else if (_isLogin) {
          if (msg.contains('invalid login credentials') ||
              msg.contains('invalid_grant') ||
              msg.contains('invalid password')) {
            _errorMessage = 'Login failed. Check your email and password.';
          } else if (msg.contains('confirm') ||
              msg.contains('email not confirmed')) {
            _errorMessage =
                'Email not confirmed. Please check your inbox and verify.';
          } else {
            _errorMessage = 'Login failed. Please try again.';
          }
        } else {
          _errorMessage =
              'Signup failed. Please try again or log in if you already have an account.';
        }
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<int?> _getRemoteUserCount() async {
    for (final table in ['profiles', 'users']) {
      try {
        final rows = await supabase.from(table).select('id') as List<dynamic>;
        return rows.length;
      } catch (_) {}
    }
    return null;
  }

  Future<bool> _checkSignupLimit() async {
    final remoteCount = await _getRemoteUserCount();
    if (remoteCount != null && remoteCount >= _signupLimit) {
      setState(
        () => _errorMessage =
            'Signup limit reached. Only $_signupLimit users can register.',
      );
      return false;
    }
    return true;
  }

  // ─── Rate Limiting Methods ────────────────────────────────────────────────
  /// Increments login attempt counter
  Future<void> _incrementLoginAttempts() async {
    final attempts = await _readSecureInt(_loginAttemptsKey);
    await _writeSecureInt(_loginAttemptsKey, attempts + 1);
    await _writeSecureInt(
      _loginAttemptTimestampKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Resets login attempt counter
  Future<void> _resetLoginAttempts() async {
    await appSecureStorage.delete(key: _loginAttemptsKey);
    await appSecureStorage.delete(key: _loginAttemptTimestampKey);
  }

  /// Checks if user is currently in cooldown period
  Future<bool> _isInCooldown() async {
    final attempts = await _readSecureInt(_loginAttemptsKey);
    if (attempts < _maxLoginAttempts) return false;

    final lastAttemptTime = await _readSecureInt(_loginAttemptTimestampKey);
    final lastAttempt = DateTime.fromMillisecondsSinceEpoch(lastAttemptTime);
    final now = DateTime.now();

    final isInCooldown = now.difference(lastAttempt) < _loginCooldownDuration;
    if (!isInCooldown) {
      _resetLoginAttempts();
    }
    return isInCooldown;
  }

  /// Gets remaining cooldown time in seconds
  Future<int> _getRemainingCooldownSeconds() async {
    final lastAttemptTime = await _readSecureInt(_loginAttemptTimestampKey);
    final lastAttempt = DateTime.fromMillisecondsSinceEpoch(lastAttemptTime);
    final now = DateTime.now();
    final remaining =
        _loginCooldownDuration.inSeconds -
        now.difference(lastAttempt).inSeconds;
    return remaining > 0 ? remaining : 0;
  }

  /// Formats remaining cooldown time
  String _formatCooldownTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  Widget _buildTextField({
    required String hint,
    required TextEditingController controller,
    bool isPassword = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14.0),
      child: SizedBox(
        height: 52,
        child: TextField(
          controller: controller,
          obscureText: isPassword ? _obscurePassword : false,
          keyboardType: keyboardType,
          onChanged: isPassword ? _onPasswordChanged : null,
          style: const TextStyle(fontSize: 15, color: kTextDark),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: kTextLight, fontSize: 15),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 0,
              horizontal: 20,
            ),
            suffixIcon: isPassword
                ? IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: kTextLight,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    splashRadius: 20,
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(26),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(26),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(26),
              borderSide: const BorderSide(color: kGreenAccent, width: 1.5),
            ),
          ),
        ),
      ),
    );
  }

  /// Password strength indicator bar (shown on signup only)
  Widget _buildPasswordStrengthBar(String password) {
    if (password.isEmpty) return const SizedBox.shrink();
    final strength = _getStrength(password);
    final (label, color, filledBars) = switch (strength) {
      _PasswordStrength.weak => ('Weak', Colors.redAccent, 1),
      _PasswordStrength.medium => ('Medium', Colors.orange, 3),
      _PasswordStrength.strong => ('Strong', kGreenAccent, 5),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(5, (i) {
              return Expanded(
                child: Container(
                  margin: const EdgeInsets.only(right: 4),
                  height: 4,
                  decoration: BoxDecoration(
                    color: i < filledBars ? color : const Color(0xFFE0E0E0),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 4),
          Text(
            'Password strength: $label',
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Must be 8+ chars with uppercase, lowercase, number & symbol.',
            style: TextStyle(fontSize: 11, color: kTextLight),
          ),
        ],
      ),
    );
  }

  // ==================== MAIN APP SCREEN / TAB SWITCHER ====================
  @override
  Widget build(BuildContext context) {
    final isSignup = !_isLogin;
    final title = _isLogin ? 'LOGIN' : 'SIGNUP';
    final buttonLabel = _isLogin ? 'Login' : 'Sign up';

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [kGreenGradientTop, kGreenGradientBottom],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 48),
                  // Logo circle
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: kGreenMid.withValues(alpha: 0.18),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14.0),
                      child: Image.asset(
                        'assets/images/FloraScan - Logo.png',
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(Icons.eco, size: 48, color: kGreenMid),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Brand name
                  const Text(
                    'FLORA SCAN',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: kGreenDark,
                      letterSpacing: 2.4,
                    ),
                  ),
                  const SizedBox(height: 28),
                  // Page title
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.0,
                      color: kTextDark,
                    ),
                  ),
                  const SizedBox(height: 32),
                  // ==================== LOGIN / SIGNUP FIELDS ====================
                  _buildTextField(
                    hint: 'Email',
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  // ==================== SIGNUP ONLY: USERNAME ====================
                  if (isSignup)
                    _buildTextField(
                      hint: 'Username',
                      controller: _usernameController,
                    ),
                  // ==================== PASSWORD FIELD ====================
                  _buildTextField(
                    hint: 'Password',
                    controller: _passwordController,
                    isPassword: true,
                  ),
                  // ==================== LOGIN ONLY: REMEMBER ME / FORGOT PASSWORD ====================
                  if (_isLogin)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Checkbox(
                            value: _rememberMe,
                            onChanged: _isLoading
                                ? null
                                : (value) => setState(
                                    () => _rememberMe = value ?? false,
                                  ),
                            activeColor: kGreenMid,
                          ),
                          const Expanded(
                            child: Text(
                              'Remember me',
                              style: TextStyle(
                                color: kTextMid,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _isLoading
                                ? null
                                : _showForgotPasswordDialog,
                            style: TextButton.styleFrom(
                              foregroundColor: kGreenMid,
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 32),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text(
                              'Forgot password?',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  // ==================== SIGNUP ONLY: PASSWORD STRENGTH ====================
                  if (isSignup)
                    _buildPasswordStrengthBar(_passwordController.text),
                  // ==================== AUTH ERROR MESSAGE ====================
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _errorMessage!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                  ] else
                    const SizedBox(height: 12),
                  // ==================== LOGIN / SIGNUP BUTTON ====================
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(26),
                        ),
                        backgroundColor: const Color(0xFF7BE8A1),
                        foregroundColor: Colors.black87,
                        elevation: 0,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.black54,
                                strokeWidth: 2.5,
                              ),
                            )
                          : Text(
                              buttonLabel,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  // ==================== SWITCH BETWEEN LOGIN AND SIGNUP ====================
                  if (_isLogin)
                    RichText(
                      text: TextSpan(
                        text: "Don't have a Account? ",
                        style: const TextStyle(color: kTextMid, fontSize: 13),
                        children: [
                          WidgetSpan(
                            child: GestureDetector(
                              onTap: _isLoading
                                  ? null
                                  : () => setState(() {
                                      _isLogin = false;
                                      _errorMessage = null;
                                    }),
                              child: const Text(
                                'Signup',
                                style: TextStyle(
                                  color: kGreenMid,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    RichText(
                      text: TextSpan(
                        text: 'Already have an account? ',
                        style: const TextStyle(color: kTextMid, fontSize: 13),
                        children: [
                          WidgetSpan(
                            child: GestureDetector(
                              onTap: _isLoading
                                  ? null
                                  : () => setState(() {
                                      _isLogin = true;
                                      _usernameController.clear();
                                      _errorMessage = null;
                                    }),
                              child: const Text(
                                'Login',
                                style: TextStyle(
                                  color: kGreenMid,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== AUTH LOADING SCREEN ====================
class _AuthLoadingScreen extends StatelessWidget {
  const _AuthLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator(color: kGreenMid)),
    );
  }
}

enum _PasswordStrength { weak, medium, strong }

// ─── Data Model ───────────────────────────────────────────────────────────────

// ==================== LEAF SCAN REPORT DATA MODEL ====================
class LeafScanReport {
  LeafScanReport({
    required this.leafName,
    required this.timestamp,
    required this.lengthCm,
    required this.widthCm,
    required this.areaCm2,
    required this.chlorophyllValue,
    required this.status,
    required this.fertilizer,
  });

  final String leafName;
  final DateTime timestamp;
  final double lengthCm;
  final double widthCm;
  final double areaCm2;
  final int chlorophyllValue;
  final String status;
  final String fertilizer;

  // Convert to JSON for storage
  Map<String, dynamic> toJson() => {
    'leafName': leafName,
    'timestamp': timestamp.toIso8601String(),
    'lengthCm': lengthCm,
    'widthCm': widthCm,
    'areaCm2': areaCm2,
    'chlorophyllValue': chlorophyllValue,
    'status': status,
    'fertilizer': fertilizer,
  };

  // Create from JSON
  factory LeafScanReport.fromJson(Map<String, dynamic> json) => LeafScanReport(
    leafName: json['leafName'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
    lengthCm: (json['lengthCm'] as num).toDouble(),
    widthCm: (json['widthCm'] as num).toDouble(),
    areaCm2: (json['areaCm2'] as num).toDouble(),
    chlorophyllValue: json['chlorophyllValue'] as int,
    status: json['status'] as String,
    fertilizer: json['fertilizer'] as String,
  );
}

// ─── Main Home ────────────────────────────────────────────────────────────────

// ==================== HOME PAGE / MAIN APP TABS ====================
class MyHomePage extends StatefulWidget {
  const MyHomePage({
    super.key,
    required this.title,
    required this.onSignOut,
    required this.onThemeChanged,
    required this.isDarkMode,
  });

  final String title;
  final Future<void> Function() onSignOut;
  final Function(bool) onThemeChanged;
  final bool isDarkMode;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final _leafNameController = TextEditingController();
  final _lengthController = TextEditingController();
  final _widthController = TextEditingController();
  final Map<DeviceIdentifier, BluetoothDevice> _foundDevices = {};

  int _selectedIndex = 0;
  bool _isScanning = false;
  bool _isConnected = false;
  String _connectionStatus = 'Disconnected';
  int? _chlorophyllValue;
  BluetoothCharacteristic? _chlorophyllCharacteristic;
  final List<LeafScanReport> _reports = [];
  StreamSubscription<List<ScanResult>>? _scanSubscription;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _leafNameController.dispose();
    _lengthController.dispose();
    _widthController.dispose();
    _saveReports(); // Save reports before disposing
    super.dispose();
  }

  // Get user-specific storage key
  String _getUserReportsKey() {
    final userId = supabase.auth.currentUser?.id ?? 'unknown';
    return 'leaf_scan_reports_$userId';
  }

  // Save reports to secure storage (user-specific)
  Future<void> _saveReports() async {
    final jsonList = _reports.map((r) => r.toJson()).toList();
    final jsonString = jsonEncode(jsonList);
    await appSecureStorage.write(key: _getUserReportsKey(), value: jsonString);
  }

  // Load reports from secure storage (user-specific)
  Future<void> _loadReports() async {
    try {
      final jsonString = await appSecureStorage.read(key: _getUserReportsKey());
      if (jsonString != null && jsonString.isNotEmpty) {
        final jsonList = jsonDecode(jsonString) as List<dynamic>;
        if (mounted) {
          setState(() {
            _reports.clear();
            _reports.addAll(
              jsonList.map(
                (json) => LeafScanReport.fromJson(json as Map<String, dynamic>),
              ),
            );
          });
        }
      }
    } catch (e) {
      // Silently handle error loading reports
    }
  }

  Future<void> _startScan() async {
    if (_isScanning) return;
    setState(() {
      _isScanning = true;
      _foundDevices.clear();
      _connectionStatus = 'Scanning for SPAD-style devices...';
    });

    _scanSubscription?.cancel();
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        for (var result in results) {
          final device = result.device;
          if (device.platformName.isNotEmpty ||
              result.advertisementData.advName.isNotEmpty) {
            _foundDevices[device.remoteId] = device;
          }
        }
        _connectionStatus = _foundDevices.isEmpty
            ? 'Scanning... no matching devices yet.'
            : 'Select a device from the list below.';
      });
    });

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    } catch (error) {
      setState(() => _connectionStatus = 'Bluetooth scan failed: $error');
    } finally {
      setState(() {
        _isScanning = false;
        if (_foundDevices.isEmpty) {
          _connectionStatus = 'No compatible leaf meter found. Try again.';
        }
      });
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect(
        license: License.free,
        timeout: const Duration(seconds: 10),
        autoConnect: false,
      );
      final services = await device.discoverServices();
      BluetoothCharacteristic? readableCharacteristic;

      for (var service in services) {
        for (var characteristic in service.characteristics) {
          if (characteristic.properties.read) {
            readableCharacteristic = characteristic;
            break;
          }
        }
        if (readableCharacteristic != null) break;
      }

      setState(() {
        _isConnected = true;
        _chlorophyllCharacteristic = readableCharacteristic;
        _connectionStatus =
            'Connected to ${device.platformName.isNotEmpty ? device.platformName : device.remoteId}';
      });
    } catch (error) {
      setState(() {
        _isConnected = false;
        _connectionStatus = 'Device connection failed: $error';
      });
    }
  }

  Future<void> _readChlorophyllValue() async {
    if (_isConnected && _chlorophyllCharacteristic != null) {
      try {
        final data = await _chlorophyllCharacteristic!.read();
        final value = _parseChlorophyllData(data);
        setState(() {
          _chlorophyllValue = value;
          _connectionStatus = 'Chlorophyll value received: $value';
        });
        return;
      } catch (error) {
        setState(
          () => _connectionStatus = 'Failed to read sensor data: $error',
        );
      }
    }

    final simulatedValue = 20 + Random().nextInt(61);
    setState(() {
      _chlorophyllValue = simulatedValue;
      _connectionStatus = 'Simulated chlorophyll data: $simulatedValue';
    });
  }

  int _parseChlorophyllData(List<int> data) {
    if (data.isEmpty) return 0;
    if (data.length == 1) return data.first.clamp(0, 100);
    final combined = data[0] | (data.length > 1 ? data[1] << 8 : 0);
    return combined.clamp(0, 100);
  }

  String _fertilizerRecommendation(int value) {
    if (value >= 55) return 'Healthy leaf — no extra fertilizer required.';
    if (value >= 40) {
      return 'Moderate chlorophyll — use balanced NPK fertilizer.';
    }
    return 'Low chlorophyll — apply nitrogen-rich fertilizer.';
  }

  String _leafHealthStatus(int value) {
    if (value >= 55) return 'Healthy';
    if (value >= 40) return 'Mild stress';
    return 'Needs attention';
  }

  Future<void> _saveScanReport() async {
    final name = _leafNameController.text.trim();
    final lengthCm = double.tryParse(_lengthController.text) ?? 0;
    final widthCm = double.tryParse(_widthController.text) ?? 0;
    final chlorophyll = _chlorophyllValue;

    if (name.isEmpty || lengthCm <= 0 || widthCm <= 0 || chlorophyll == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please fill all fields.')));
      return;
    }

    final areaCm2 = double.parse((lengthCm * widthCm).toStringAsFixed(2));
    final report = LeafScanReport(
      leafName: name,
      timestamp: DateTime.now(),
      lengthCm: lengthCm,
      widthCm: widthCm,
      areaCm2: areaCm2,
      chlorophyllValue: chlorophyll,
      status: _leafHealthStatus(chlorophyll),
      fertilizer: _fertilizerRecommendation(chlorophyll),
    );

    try {
      await supabase.schema('florascan').from('leaf_scans').insert({
        'leaf_classification': name,
        'leaf_size_cm2': areaCm2,
        'chlorophyll_content': chlorophyll,
        'raw_red_signal': 0,
        'raw_nir_signal': 0,
        'user_id':
            supabase.auth.currentUser?.id ??
            '00000000-0000-0000-0000-000000000000',
      });

      setState(() {
        _reports.insert(0, report);
        _leafNameController.clear();
        _lengthController.clear();
        _widthController.clear();
        _chlorophyllValue = null;
        _connectionStatus = 'Saved to Cloud!';
      });
      await _saveReports(); // Save to local storage
    } catch (e) {
      setState(() => _connectionStatus = 'Database Error: $e');
    }
  }

  void _selectTab(int index) => setState(() => _selectedIndex = index);

  // ─── Bottom Nav ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final tabs = [
      _buildDashboardTab(),
      _buildHistoryTab(),
      _buildScanTab(),
      _buildReportsTab(),
      _buildProfileTab(),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F5),
      body: tabs[_selectedIndex],
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ==================== BOTTOM NAVIGATION ====================
  Widget _buildBottomNav() {
    final items = [
      {'icon': Icons.home_filled, 'label': 'Dashboard'},
      {'icon': Icons.history, 'label': 'History'},
      {'icon': Icons.qr_code_scanner, 'label': ''},
      {'icon': Icons.bar_chart_rounded, 'label': 'Reports'},
      {'icon': Icons.person_outline, 'label': 'Profile'},
    ];

    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(items.length, (i) {
          final isCenter = i == 2;
          final isSelected = _selectedIndex == i;
          final icon = items[i]['icon'] as IconData;
          final label = items[i]['label'] as String;

          if (isCenter) {
            return GestureDetector(
              onTap: () => _selectTab(i),
              child: Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: kGreenMid,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: kGreenMid.withValues(alpha: 0.4),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.qr_code_scanner,
                  color: Colors.white,
                  size: 26,
                ),
              ),
            );
          }

          return GestureDetector(
            onTap: () => _selectTab(i),
            child: SizedBox(
              width: 60,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 22,
                    color: isSelected ? kGreenMid : const Color(0xFFB0BEC5),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      color: isSelected ? kGreenMid : const Color(0xFFB0BEC5),
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  // ─── Dashboard Tab ────────────────────────────────────────────────────────

  // ==================== DASHBOARD TAB ====================
  Widget _buildDashboardTab() {
    final user = supabase.auth.currentUser;
    final username =
        user?.userMetadata?['username'] as String? ??
        user?.email?.split('@').first ??
        'Researcher';
    final latestReport = _reports.isNotEmpty ? _reports.first : null;
    final recentReports = _reports.take(3).toList();

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Top Bar: notification + settings on right, logo CENTERED ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Logo perfectly centered
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: kGreenMid.withValues(alpha: 0.15),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Image.asset(
                            'assets/images/FloraScan - Logo.png',
                            fit: BoxFit.contain,
                            errorBuilder: (c, e, s) => const Icon(
                              Icons.eco,
                              color: kGreenMid,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'FLORA SCAN',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          color: kGreenDark,
                          letterSpacing: 1.6,
                        ),
                      ),
                    ],
                  ),
                  // Icons pinned to the right
                  Positioned(
                    right: 0,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.settings_outlined,
                            color: kTextMid,
                            size: 22,
                          ),
                          onPressed: () => _showSettingsBottomSheet(context),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // Welcome text
            Text(
              'Welcome, ${_capitalize(username)}!',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: kTextDark,
              ),
            ),
            const SizedBox(height: 16),
            // ── Cards ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  // ── Current Scan card (prototype style) ──────────────────
                  _dashCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Left: label + big number + subtitle + timestamp
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Current Scan',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: kTextDark,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                latestReport != null
                                    ? '${latestReport.chlorophyllValue}'
                                    : '--',
                                style: const TextStyle(
                                  fontSize: 52,
                                  fontWeight: FontWeight.w800,
                                  color: kTextDark,
                                  height: 1.0,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Chl Index',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: kTextMid,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                latestReport != null
                                    ? 'Last Updated ${_formatDate(latestReport.timestamp)}'
                                    : 'No scan yet',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: kTextLight,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Right: device icon box
                        Container(
                          width: 56,
                          height: 72,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F0F0),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.devices_other,
                            color: kTextMid,
                            size: 30,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  // ── Recent Activity card (prototype: listed rows) ─────────
                  _dashCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Recent Activity',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: kTextDark,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (recentReports.isEmpty)
                          const Text(
                            'No activity yet. Save a scan to build history.',
                            style: TextStyle(fontSize: 13, color: kTextLight),
                          )
                        else
                          ...recentReports.map(
                            (r) => Padding(
                              padding: const EdgeInsets.only(bottom: 5.0),
                              child: Text(
                                '${r.leafName}  |  ${_formatDate(r.timestamp)}  |  Chl Index: ${r.chlorophyllValue}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: kTextMid,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  // ── Device Status card (prototype style) ──────────────────
                  _dashCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Device Status',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: kTextDark,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            // Device icon with green tint when connected
                            Container(
                              width: 48,
                              height: 56,
                              decoration: BoxDecoration(
                                color: _isConnected
                                    ? kGreenPale
                                    : const Color(0xFFF0F0F0),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.devices,
                                color: _isConnected ? kGreenMid : kTextMid,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Device ID: ${_isConnected ? 'Er-F-IOT-001' : 'N/A'}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: kTextMid,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Battery: ${_isConnected ? '95%' : '--'}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: kTextMid,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text(
                                      'Connection: ',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: kTextMid,
                                      ),
                                    ),
                                    Text(
                                      _isConnected ? 'Stable' : 'Not Connected',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: _isConnected
                                            ? kGreenAccent
                                            : Colors.redAccent,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dashCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: kCardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }

  // ─── History Tab ──────────────────────────────────────────────────────────

  // ==================== HISTORY TAB ====================
  Widget _buildHistoryTab() {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 24, 20, 16),
            child: Text(
              'Scan History',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: kTextDark,
              ),
            ),
          ),
          Expanded(
            child: _reports.isEmpty
                ? const Center(
                    child: Text(
                      'No scans yet. Start scanning to see your history.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: kTextLight, fontSize: 14),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _reports.length,
                    itemBuilder: (context, index) {
                      final r = _reports[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: kCardBg,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    r.leafName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: kTextDark,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${r.areaCm2} cm²  •  Chl: ${r.chlorophyllValue}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: kTextMid,
                                    ),
                                  ),
                                  Text(
                                    r.status,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: r.status == 'Healthy'
                                          ? kGreenMid
                                          : Colors.orange,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              _formatTime(r.timestamp),
                              style: const TextStyle(
                                fontSize: 11,
                                color: kTextLight,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ─── Scan Tab ─────────────────────────────────────────────────────────────

  // ==================== SCAN TAB ====================
  Widget _buildScanTab() {
    return SafeArea(
      child: Column(
        children: [
          // Top bar with back arrow and close
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 16, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios,
                    size: 20,
                    color: kTextMid,
                  ),
                  onPressed: () => _selectTab(0),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 22, color: kTextMid),
                  onPressed: () => _selectTab(0),
                ),
              ],
            ),
          ),
          // Scanner crosshair icon
          const Icon(Icons.gps_fixed, size: 38, color: kGreenMid),
          const SizedBox(height: 6),
          const Text(
            'Position leaf in frame',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: kTextMid,
            ),
          ),
          const SizedBox(height: 16),
          // "Camera" frame
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: [
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFF3A6B42),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.eco,
                          size: 80,
                          color: Color(0x55FFFFFF),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: CustomPaint(painter: _CornerBracketPainter()),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Scan fields
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                _scanField('Leaf name / Sample ID', _leafNameController),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _scanField(
                        'Length (cm)',
                        _lengthController,
                        keyboard: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _scanField(
                        'Width (cm)',
                        _widthController,
                        keyboard: TextInputType.number,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Status
          if (_connectionStatus.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Text(
                _connectionStatus,
                style: const TextStyle(fontSize: 12, color: kTextLight),
                textAlign: TextAlign.center,
              ),
            ),
          // Bluetooth devices
          if (_foundDevices.isNotEmpty)
            SizedBox(
              height: 80,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                children: _foundDevices.values.map((device) {
                  return Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: kCardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kGreenLight),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          device.platformName.isNotEmpty
                              ? device.platformName
                              : device.remoteId.toString(),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextButton(
                          onPressed: _isConnected
                              ? null
                              : () => _connectToDevice(device),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 0),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'Connect',
                            style: TextStyle(fontSize: 11, color: kGreenMid),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          const SizedBox(height: 12),
          // Bottom buttons row
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _startScan,
                    icon: const Icon(
                      Icons.bluetooth_searching,
                      size: 16,
                      color: kGreenMid,
                    ),
                    label: Text(
                      _isScanning ? 'Scanning...' : 'Scan Bluetooth Devices',
                      style: const TextStyle(fontSize: 12, color: kGreenMid),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: kGreenMid),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _readChlorophyllValue,
                  child: Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: kGreenMid, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: kGreenMid.withValues(alpha: 0.2),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.qr_code_scanner,
                      color: kGreenMid,
                      size: 26,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _saveScanReport,
                    icon: const Icon(
                      Icons.save_alt,
                      size: 16,
                      color: Colors.white,
                    ),
                    label: const Text(
                      'Save Report',
                      style: TextStyle(fontSize: 12, color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kGreenMid,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
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

  // ==================== SCAN INPUT FIELD ====================
  Widget _scanField(
    String hint,
    TextEditingController controller, {
    TextInputType keyboard = TextInputType.text,
  }) {
    return SizedBox(
      height: 44,
      child: TextField(
        controller: controller,
        keyboardType: keyboard,
        style: const TextStyle(fontSize: 13, color: kTextDark),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: kTextLight, fontSize: 13),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 0,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: const BorderSide(color: kGreenAccent, width: 1.2),
          ),
        ),
      ),
    );
  }

  // ─── Reports Tab ──────────────────────────────────────────────────────────

  // ==================== REPORTS TAB ====================
  Widget _buildReportsTab() {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 24, 20, 16),
            child: Text(
              'Reports',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: kTextDark,
              ),
            ),
          ),
          Expanded(
            child: _reports.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 32.0),
                      child: Text(
                        'No reports yet. Scan a leaf and save to see it here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: kTextLight, fontSize: 14),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _reports.length,
                    itemBuilder: (context, index) {
                      final r = _reports[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: kCardBg,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  r.leafName,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: kTextDark,
                                  ),
                                ),
                                Text(
                                  _formatTime(r.timestamp),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: kTextLight,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Size: ${r.lengthCm} cm × ${r.widthCm} cm = ${r.areaCm2} cm²',
                              style: const TextStyle(
                                fontSize: 13,
                                color: kTextMid,
                              ),
                            ),
                            Text(
                              'Chlorophyll: ${r.chlorophyllValue}   Status: ${r.status}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: kTextMid,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              r.fertilizer,
                              style: const TextStyle(
                                fontSize: 12,
                                color: kGreenMid,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ─── Profile Tab ──────────────────────────────────────────────────────────

  // ==================== PROFILE TAB ====================
  Widget _buildProfileTab() {
    final user = supabase.auth.currentUser;
    final username =
        user?.userMetadata?['username'] as String? ??
        user?.email?.split('@').first ??
        'User';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            const Text(
              'Profile',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: kTextDark,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: kCardBg,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: kGreenPale,
                    child: Text(
                      username.isNotEmpty ? username[0].toUpperCase() : 'U',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: kGreenDark,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _capitalize(username),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: kTextDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user?.email ?? '',
                        style: const TextStyle(fontSize: 13, color: kTextLight),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () async => await widget.onSignOut(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kGreenMid,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Sign out',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Settings Bottom Sheet ─────────────────────────────────────────────────

  /// Shows the Settings bottom sheet with theme, notifications, and about app
  void _showSettingsBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: kCardBg,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: SingleChildScrollView(
                controller: scrollController,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Settings',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: kTextDark,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.close_rounded,
                              color: kTextMid,
                              size: 24,
                            ),
                            onPressed: () => Navigator.pop(context),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // ── Theme Section ────────────────────────────────────
                      _buildSettingsSection(
                        title: 'Theme & Display',
                        children: [
                          _buildSettingsTile(
                            icon: Icons.dark_mode_outlined,
                            title: 'Dark Mode',
                            trailing: Transform.scale(
                              scale: 0.8,
                              child: Switch(
                                value: widget.isDarkMode,
                                onChanged: (value) {
                                  widget.onThemeChanged(value);
                                  Navigator.pop(context);
                                },
                                activeThumbColor: kGreenMid,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // ── Notifications Section ────────────────────────────
                      _buildSettingsSection(
                        title: 'Notifications',
                        children: [
                          _buildSettingsTile(
                            icon: Icons.notifications_outlined,
                            title: 'Push Notifications',
                            subtitle: 'Receive scan alerts and reminders',
                            trailing: Transform.scale(
                              scale: 0.8,
                              child: Switch(
                                value: true,
                                onChanged: (value) {},
                                activeThumbColor: kGreenMid,
                              ),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Divider(height: 1),
                          ),
                          _buildSettingsTile(
                            icon: Icons.email_outlined,
                            title: 'Email Alerts',
                            subtitle: 'Weekly scan summaries',
                            trailing: Transform.scale(
                              scale: 0.8,
                              child: Switch(
                                value: true,
                                onChanged: (value) {},
                                activeThumbColor: kGreenMid,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // ── Data & Privacy Section ───────────────────────────
                      _buildSettingsSection(
                        title: 'Data & Privacy',
                        children: [
                          _buildSettingsTile(
                            icon: Icons.info_outline,
                            title: 'Data Storage',
                            subtitle:
                                'Your scans are encrypted and stored securely',
                            onTap: () {},
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Divider(height: 1),
                          ),
                          _buildSettingsTile(
                            icon: Icons.privacy_tip_outlined,
                            title: 'Privacy Policy',
                            onTap: () {},
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // ── About App Section ────────────────────────────────
                      _buildSettingsSection(
                        title: 'About',
                        children: [
                          _buildSettingsTile(
                            icon: Icons.info_outlined,
                            title: 'About FloraScan',
                            onTap: () => _showAboutDialog(context),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Divider(height: 1),
                          ),
                          _buildSettingsTile(
                            icon: Icons.bug_report_outlined,
                            title: 'App Version',
                            subtitle: 'v1.0.0',
                            onTap: () {},
                          ),
                        ],
                      ),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Builds a settings section with title and children
  Widget _buildSettingsSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: kGreenMid,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFEEEEEE), width: 1),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  /// Builds an individual settings tile
  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap ?? () {},
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: kGreenMid, size: 20),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: kTextDark,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(fontSize: 12, color: kTextLight),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[trailing],
            ],
          ),
        ),
      ),
    );
  }

  /// Shows the About App dialog with detailed information
  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'About FloraScan',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: kTextDark,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: kGreenPale,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Image.asset(
                      'assets/images/FloraScan - Logo.png',
                      fit: BoxFit.contain,
                      errorBuilder: (c, e, s) =>
                          const Icon(Icons.eco, color: kGreenMid, size: 40),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'FloraScan',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: kTextDark,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Version 1.0.0',
                  style: TextStyle(fontSize: 12, color: kTextLight),
                ),
                const SizedBox(height: 16),
                const Text(
                  'About',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: kTextDark,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'FloraScan is an advanced plant health monitoring application that uses Bluetooth connectivity to analyze leaf chlorophyll content and provide real-time health assessments for your plants.',
                  style: TextStyle(fontSize: 13, color: kTextMid, height: 1.5),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Features',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: kTextDark,
                  ),
                ),
                const SizedBox(height: 8),
                ...[
                  '📊 Real-time chlorophyll analysis',
                  '📱 Bluetooth device connectivity',
                  '💾 Cloud data storage with Supabase',
                  '🔒 Secure user authentication',
                  '📈 Detailed scan reports and history',
                  '🌙 Light and Dark mode support',
                ].map(
                  (feature) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      feature,
                      style: const TextStyle(fontSize: 13, color: kTextMid),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '© 2026 FloraScan. All rights reserved.',
                  style: TextStyle(fontSize: 11, color: kTextLight),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close', style: TextStyle(color: kGreenMid)),
            ),
          ],
        );
      },
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} ${dt.hour < 12 ? 'AM' : 'PM'}';

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}';
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ─── Corner Bracket Painter ───────────────────────────────────────────────────

class _CornerBracketPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const len = 28.0;
    const margin = 14.0;

    // Top-left
    canvas.drawLine(
      Offset(margin, margin + len),
      Offset(margin, margin),
      paint,
    );
    canvas.drawLine(
      Offset(margin, margin),
      Offset(margin + len, margin),
      paint,
    );
    // Top-right
    canvas.drawLine(
      Offset(size.width - margin - len, margin),
      Offset(size.width - margin, margin),
      paint,
    );
    canvas.drawLine(
      Offset(size.width - margin, margin),
      Offset(size.width - margin, margin + len),
      paint,
    );
    // Bottom-left
    canvas.drawLine(
      Offset(margin, size.height - margin - len),
      Offset(margin, size.height - margin),
      paint,
    );
    canvas.drawLine(
      Offset(margin, size.height - margin),
      Offset(margin + len, size.height - margin),
      paint,
    );
    // Bottom-right
    canvas.drawLine(
      Offset(size.width - margin - len, size.height - margin),
      Offset(size.width - margin, size.height - margin),
      paint,
    );
    canvas.drawLine(
      Offset(size.width - margin, size.height - margin - len),
      Offset(size.width - margin, size.height - margin),
      paint,
    );
  }

  @override
  bool shouldRepaint(_CornerBracketPainter oldDelegate) => false;
}
