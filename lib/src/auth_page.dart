part of '../main.dart';

/// Authentication page - handles login and signup functionality
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
  bool _isLockedOut = false;
  int _lockoutSecondsRemaining = 0;
  Timer? _lockoutTimer;
  static const String _allowedSignupEmailDomain = '@spamast.edu.ph';

  @override
  void initState() {
    super.initState();
    _loadRememberedLogin();
    _checkLockoutOnInit();
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    _emailController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // --- Password Strength Validation -----------------------------------------

  /// Validates password strength - requires 8+ chars, uppercase, lowercase, number, and symbol
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

  /// Calculates password strength level (weak/medium/strong) based on criteria met
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

  bool _isAllowedSignupEmail(String email) {
    return email.toLowerCase().endsWith(_allowedSignupEmailDomain);
  }

  bool _isDuplicateSignupResponse(AuthResponse response) {
    final identities = response.user?.identities;
    return response.session == null && identities != null && identities.isEmpty;
  }

  /// Checks if email already exists in the profiles table
  /// Returns error message if exists, null if doesn't exist
  Future<Map<String, String>?> _checkIfEmailExists(String email) async {
    try {
      final profileRows = await supabase
          .from('profiles')
          .select('id')
          .eq('email', email)
          .limit(1);

      if (profileRows.isNotEmpty) {
        return {'message': 'Email already Registered.'};
      }
    } catch (_) {
      // profiles table check failed, allow signup to proceed
    }

    return null;
  }

  /// Callback triggered on password change to update strength indicator
  void _onPasswordChanged(String value) {
    setState(() {}); // rebuild to update the strength bar live
  }

  /// Loads previously remembered email if 'Remember Me' was checked
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

  /// Saves or clears the 'Remember Me' preference and email
  Future<void> _persistLoginPreference(String email) async {
    await _writeSecureBool(_rememberMeKey, _rememberMe);
    if (_rememberMe) {
      await appSecureStorage.write(key: _rememberedEmailKey, value: email);
      return;
    }
    await appSecureStorage.delete(key: _rememberedEmailKey);
  }

  /// Shows forgot password dialog - allows user to request password reset email
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

  /// Submits login or signup request - handles authentication flow
  Future<void> _submit() async {
    setState(() => _errorMessage = null);

    final email = _emailController.text.trim().toLowerCase();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty || (!_isLogin && username.isEmpty)) {
      setState(() => _errorMessage = 'Please fill all required fields.');
      return;
    }

    // Check if user is in cooldown (only for login)
    if (_isLogin && _isLockedOut) {
      return; // button should be disabled, but guard anyway
    }
    if (_isLogin && await _isInCooldown()) {
      await _startLockoutTimer();
      return;
    }

    // Password strength check on signup
    if (!_isLogin) {
      if (!_isAllowedSignupEmail(email)) {
        setState(
          () => _errorMessage = 'Use Institutional email address to sign up.',
        );
        return;
      }

      // Check if email already exists and handle accordingly
      final existingUser = await _checkIfEmailExists(email);
      if (existingUser != null) {
        setState(() => _errorMessage = existingUser['message']);
        return;
      }

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
            await _startLockoutTimer();
          } else {
            setState(
              () => _errorMessage =
                  'Incorrect email or password. $remainingAttempts attempt${remainingAttempts == 1 ? '' : 's'} remaining.',
            );
          }
        } else {
          // Login successful - reset failed attempts
          await _resetLoginAttempts();
          await _persistLoginPreference(email);
          widget.onSignedIn();
        }
      } else {
        final response = await supabase.auth.signUp(
          email: email,
          password: password,
          data: {'username': username},
        );

        if (_isDuplicateSignupResponse(response)) {
          setState(() => _errorMessage = 'Email already Registered.');
          _isLogin = true;
          return;
        } else if (response.user == null) {
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
      if (_isLogin) {
        if (msg.contains('over_email_send_rate_limit')) {
          setState(
            () => _errorMessage =
                'Too many login attempts. Wait 5 minutes and try again.',
          );
        } else if (msg.contains('invalid login credentials') ||
            msg.contains('invalid_grant') ||
            msg.contains('invalid password') ||
            msg.contains('invalid email') ||
            msg.contains('wrong password')) {
          // Bad credentials thrown as exception - count the attempt
          await _incrementLoginAttempts();
          final attempts = await _readSecureInt(_loginAttemptsKey);
          final remainingAttempts = _maxLoginAttempts - attempts;
          if (remainingAttempts <= 0) {
            await _startLockoutTimer();
          } else {
            setState(
              () => _errorMessage =
                  'Incorrect email or password. $remainingAttempts attempt${remainingAttempts == 1 ? '' : 's'} remaining.',
            );
          }
        } else if (msg.contains('confirm') ||
            msg.contains('email not confirmed')) {
          setState(
            () => _errorMessage =
                'Email not confirmed. Please check your inbox and verify.',
          );
        } else {
          await _incrementLoginAttempts();
          final attempts = await _readSecureInt(_loginAttemptsKey);
          final remainingAttempts = _maxLoginAttempts - attempts;
          if (remainingAttempts <= 0) {
            await _startLockoutTimer();
          } else {
            setState(
              () => _errorMessage =
                  'Login failed. $remainingAttempts attempt${remainingAttempts == 1 ? '' : 's'} remaining.',
            );
          }
        }
      } else {
        // Signup error handling
        setState(() {
          if (msg.contains('invalid email') || msg.contains('email invalid')) {
            _errorMessage = 'Please enter a valid institutional email address.';
          } else if (msg.contains('already') ||
              msg.contains('registered') ||
              msg.contains('user already')) {
            _errorMessage = 'Email already Registered.';
          } else {
            _errorMessage = 'Email already Registered.';
          }
        });
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // --- Rate Limiting Methods ------------------------------------------------
  /// Increments failed login attempt counter in secure storage
  Future<void> _incrementLoginAttempts() async {
    final attempts = await _readSecureInt(_loginAttemptsKey);
    await _writeSecureInt(_loginAttemptsKey, attempts + 1);
    await _writeSecureInt(
      _loginAttemptTimestampKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Resets failed login attempt counter after successful login
  Future<void> _resetLoginAttempts() async {
    await appSecureStorage.delete(key: _loginAttemptsKey);
    await appSecureStorage.delete(key: _loginAttemptTimestampKey);
  }

  /// Checks if user is currently in cooldown period after max failed attempts
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

  /// Calculates remaining cooldown time in seconds
  Future<int> _getRemainingCooldownSeconds() async {
    final lastAttemptTime = await _readSecureInt(_loginAttemptTimestampKey);
    final lastAttempt = DateTime.fromMillisecondsSinceEpoch(lastAttemptTime);
    final now = DateTime.now();
    final remaining =
        _loginCooldownDuration.inSeconds -
        now.difference(lastAttempt).inSeconds;
    return remaining > 0 ? remaining : 0;
  }

  /// Starts a live countdown timer for the lockout period
  Future<void> _startLockoutTimer() async {
    final remaining = await _getRemainingCooldownSeconds();
    if (!mounted) return;
    setState(() {
      _isLockedOut = true;
      _lockoutSecondsRemaining = remaining;
      _errorMessage = null;
    });
    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _lockoutSecondsRemaining--;
        if (_lockoutSecondsRemaining <= 0) {
          timer.cancel();
          _isLockedOut = false;
          _lockoutSecondsRemaining = 0;
          _resetLoginAttempts();
        }
      });
    });
  }

  /// Checks on app init if a lockout is still active from a previous session
  Future<void> _checkLockoutOnInit() async {
    if (await _isInCooldown()) {
      await _startLockoutTimer();
    }
  }

  /// Formats cooldown time as MM:SS string
  String _formatCooldownTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  /// Builds a reusable text input field for email/username/password
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

  /// Builds password strength indicator bar with visual feedback (shown on signup only)
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

                  // ==================== AUTH ERROR / SUCCESS MESSAGE ====================
                  if (_isLockedOut) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.redAccent.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'Too many failed attempts. Account locked.',
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Try again in ${_formatCooldownTime(_lockoutSecondsRemaining)}',
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ] else if (_errorMessage != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _errorMessage!,
                      style: TextStyle(
                        color:
                            _errorMessage!.toLowerCase().contains('succeeded')
                            ? kGreenMid
                            : Colors.redAccent,
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
                      onPressed: (_isLoading || _isLockedOut) ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(26),
                        ),
                        backgroundColor: _isLockedOut
                            ? Colors.grey.shade300
                            : const Color(0xFF7BE8A1),
                        foregroundColor: _isLockedOut
                            ? Colors.grey.shade500
                            : Colors.black87,
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

// --- Data Model ---------------------------------------------------------------
