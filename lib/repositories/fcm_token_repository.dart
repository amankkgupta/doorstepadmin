import 'package:admindoorstep/app_logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FCMTokenRepository {
  static final AppLogger _logger = AppLogger();

  Future<bool> saveFCMToken({
    required String userId,
    required String fcmToken,
  }) async {
    try {
      _logger.info(
        'Saving FCM token',
        data: {'userId': userId, 'tokenLength': fcmToken.length},
      );

      await Supabase.instance.client.from('fcmtokens').upsert(
        {
          'user_id': userId,
          'fcmtoken': fcmToken,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'user_id',
      );

      _logger.info('FCM token saved successfully', data: {'userId': userId});
      return true;
    } on PostgrestException catch (e) {
      _logger.error(
        'Failed to save FCM token (PostgrestException)',
        data: {
          'userId': userId,
          'error': e.message,
          'code': e.code,
        },
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
        data: {
          'userId': userId,
          'error': e.message,
          'code': e.code,
        },
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
