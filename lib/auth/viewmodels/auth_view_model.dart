import 'package:admindoorstep/app_logger.dart';
import 'package:admindoorstep/repositories/fcm_token_repository.dart';
import 'package:admindoorstep/services/notification_service.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum SignInResult { success, failure }

class AdminSession {
  const AdminSession({
    required this.id,
    required this.email,
    required this.categoryId,
  });

  final String id;
  final String email;
  final dynamic categoryId;
}

class AuthViewModel extends ChangeNotifier {
  static final AppLogger _logger = AppLogger();
  final FCMTokenRepository _fcmTokenRepository = FCMTokenRepository();
  final NotificationService _notificationService = NotificationService();

  AdminSession? _user;
  String? _errorMessage;
  bool _isLoading = false;
  bool _isInitializing = true;
  bool _bootstrapped = false;

  AdminSession? get user => _user;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _isLoading;
  bool get isInitializing => _isInitializing;
  bool get isLoggedIn => _user != null;

  Future<void> bootstrap() async {
    if (_bootstrapped) {
      return;
    }

    _bootstrapped = true;
    _isInitializing = false;
    notifyListeners();
  }

  Future<SignInResult> signInWithEmail({
    required String email,
    required String password,
  }) async {
    if (_isLoading || !_isSupabaseReady) {
      return SignInResult.failure;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final normalizedEmail = email.trim().toLowerCase();
      final admin = await Supabase.instance.client
          .from('admins')
          .select()
          .eq('email', normalizedEmail)
          .maybeSingle();

      if (admin == null || (admin['password'] ?? '').toString() != password) {
        _errorMessage = 'Invalid email or password.';
        return SignInResult.failure;
      }

      await Supabase.instance.client.auth.signInWithPassword(
        email: normalizedEmail,
        password: password,
      );

      final adminId = _pickAdminId(admin);
      _user = AdminSession(
        id: adminId.isEmpty ? normalizedEmail : adminId,
        email: (admin['email'] ?? normalizedEmail).toString(),
        categoryId: admin['category_id'],
      );

      await _updateAndVerifyFCMTokenAfterSignIn(userId: _user!.id);

      return SignInResult.success;
    } on AuthException catch (error) {
      _errorMessage = error.message;
      return SignInResult.failure;
    } on PostgrestException catch (error) {
      debugPrint('Admin sign-in query failed: ${error.message}');
      _errorMessage = 'Unable to sign in right now.';
      return SignInResult.failure;
    } catch (error) {
      debugPrint('Admin sign-in failed: $error');
      _errorMessage = 'Unable to sign in right now.';
      return SignInResult.failure;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    if (_isLoading || !_isSupabaseReady) {
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    _user = null;
    try {
      await Supabase.instance.client.auth.signOut();
    } on AuthException catch (error) {
      _errorMessage = error.message;
    } catch (error) {
      debugPrint('Supabase sign-out failed: $error');
      _errorMessage = 'Unable to sign out right now.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  bool get _isSupabaseReady {
    try {
      Supabase.instance.client;
      return true;
    } catch (_) {
      return false;
    }
  }

  String _pickAdminId(Map<String, dynamic> admin) {
    final candidates = [admin['admin_id'], admin['id'], admin['user_id']];
    for (final candidate in candidates) {
      final value = (candidate ?? '').toString().trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  Future<void> _updateAndVerifyFCMTokenAfterSignIn({
    required String userId,
  }) async {
    try {
      final fcmToken = await _notificationService.getFCMToken();
      if (fcmToken == null || fcmToken.trim().isEmpty) {
        _logger.warning(
          'FCM token update skipped after sign-in',
          data: {'userId': userId, 'hasToken': false},
        );
        return;
      }

      final saved = await _fcmTokenRepository.saveFCMToken(
        userId: userId,
        fcmToken: fcmToken,
      );

      if (!saved) {
        _logger.warning(
          'FCM token verification skipped because save failed after sign-in',
          data: {'userId': userId},
        );
        return;
      }

      await _fcmTokenRepository.verifyFCMTokenStored(
        userId: userId,
        expectedFcmToken: fcmToken,
      );
    } catch (error, stackTrace) {
      _logger.error(
        'FCM token update check failed after sign-in',
        data: {'userId': userId, 'error': error.toString()},
        stackTrace: stackTrace,
      );
    }
  }
}
