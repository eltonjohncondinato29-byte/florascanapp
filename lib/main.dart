import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'src/app_root.dart';
part 'src/auth_page.dart';
part 'src/leaf_scan_report.dart';
part 'src/home_page.dart';

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

// ========== GLOBAL UTILITY FUNCTIONS ==========
/// Reads a boolean value from secure storage by key
Future<bool> _readSecureBool(String key) async {
  return await appSecureStorage.read(key: key) == 'true';
}

/// Writes a boolean value to secure storage by key
Future<void> _writeSecureBool(String key, bool value) async {
  await appSecureStorage.write(key: key, value: value.toString());
}

/// Reads an integer value from secure storage by key
Future<int> _readSecureInt(String key) async {
  final value = await appSecureStorage.read(key: key);
  return int.tryParse(value ?? '') ?? 0;
}

/// Writes an integer value to secure storage by key
Future<void> _writeSecureInt(String key, int value) async {
  await appSecureStorage.write(key: key, value: value.toString());
}

/// Main application entry point - initializes Supabase and runs the app
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

// --- Theme Colors ------------------------------------------------------------
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
