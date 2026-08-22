import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/models/user_profile_model.dart';

class UserProfileNotifier extends StateNotifier<UserProfileModel?> {
  UserProfileNotifier() : super(null);

  Future<void> loadProfile(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('profile_name_$userId') ?? '';
    final mobile = prefs.getString('profile_mobile_$userId');
    final dobStr = prefs.getString('profile_dob_$userId');
    final avatar = prefs.getString('profile_avatar_$userId');
    state = UserProfileModel(
      userId: userId,
      displayName: name,
      mobile: mobile,
      dateOfBirth: dobStr != null ? DateTime.tryParse(dobStr) : null,
      avatarBase64: avatar,
    );
  }

  Future<void> saveProfile(UserProfileModel profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile_name_${profile.userId}', profile.displayName);
    if (profile.mobile != null) await prefs.setString('profile_mobile_${profile.userId}', profile.mobile!);
    if (profile.dateOfBirth != null) await prefs.setString('profile_dob_${profile.userId}', profile.dateOfBirth!.toIso8601String());
    if (profile.avatarBase64 != null) await prefs.setString('profile_avatar_${profile.userId}', profile.avatarBase64!);
    state = profile;
  }

  void clear() => state = null;
}

final userProfileProvider = StateNotifierProvider<UserProfileNotifier, UserProfileModel?>(
  (ref) => UserProfileNotifier(),
);
