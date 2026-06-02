import 'package:admindoorstep/app_logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FCMTokenRepository {
  static final AppLogger _logger = AppLogger();

  Future<bool> saveFCMToken({
    required String userId,
    required String fcmToken,
  }) async {
    try {
      final now = DateTime.now().toIso8601String();
      _logger.info(
        'Saving FCM token',
        data: {'userId': userId, 'tokenLength': fcmToken.length},
      );

      await Supabase.instance.client.from('fcmtokens').upsert({
        'user_id': userId,
        'fcmtoken': fcmToken,
        'created_at': now,
      }, onConflict: 'user_id');

      _logger.info('FCM token saved successfully', data: {'userId': userId});
      return true;
    } on PostgrestException catch (e) {
      _logger.error(
        'Failed to save FCM token (PostgrestException)',
        data: {'userId': userId, 'error': e.message, 'code': e.code},
      );
      return false;
    } catch (e, stackTrace) {
      _logger.error(
        'Failed to save FCM token',
        data: {'userId': userId, 'error': e.toString()},
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  Future<bool> verifyFCMTokenStored({
    required String userId,
    required String expectedFcmToken,
  }) async {
    try {
      final row = await Supabase.instance.client
          .from('fcmtokens')
          .select('fcmtoken, created_at')
          .eq('user_id', userId)
          .maybeSingle();

      final storedToken = (row?['fcmtoken'] ?? '').toString();
      final isStored = storedToken == expectedFcmToken;

      if (isStored) {
        _logger.info(
          'FCM token column verified after sign-in',
          data: {
            'userId': userId,
            'isStored': true,
            'tokenLength': storedToken.length,
            'createdAt': row?['created_at'],
          },
        );
      } else {
        _logger.warning(
          'FCM token column verification failed after sign-in',
          data: {
            'userId': userId,
            'isStored': false,
            'hasRow': row != null,
            'storedTokenLength': storedToken.length,
            'expectedTokenLength': expectedFcmToken.length,
            'createdAt': row?['created_at'],
          },
        );
      }

      return isStored;
    } on PostgrestException catch (e) {
      _logger.error(
        'Failed to verify FCM token column (PostgrestException)',
        data: {'userId': userId, 'error': e.message, 'code': e.code},
      );
      return false;
    } catch (e, stackTrace) {
      _logger.error(
        'Failed to verify FCM token column',
        data: {'userId': userId, 'error': e.toString()},
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  Future<bool> deleteFCMToken({required String userId}) async {
    try {
      _logger.info('Deleting FCM token', data: {'userId': userId});

      await Supabase.instance.client
          .from('fcmtokens')
          .delete()
          .eq('user_id', userId);

      _logger.info('FCM token deleted successfully', data: {'userId': userId});
      return true;
    } on PostgrestException catch (e) {
      _logger.error(
        'Failed to delete FCM token (PostgrestException)',
        data: {'userId': userId, 'error': e.message, 'code': e.code},
      );
      return false;
    } catch (e, stackTrace) {
      _logger.error(
        'Failed to delete FCM token',
        data: {'userId': userId, 'error': e.toString()},
        stackTrace: stackTrace,
      );
      return false;
    }
  }
}
