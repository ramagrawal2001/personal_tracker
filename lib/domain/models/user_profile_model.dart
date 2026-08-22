class UserProfileModel {
  final String userId;
  final String displayName;
  final String? mobile;
  final DateTime? dateOfBirth;
  final String? avatarBase64; // base64 encoded image or null

  const UserProfileModel({
    required this.userId,
    this.displayName = '',
    this.mobile,
    this.dateOfBirth,
    this.avatarBase64,
  });

  String get initials {
    if (displayName.trim().isEmpty) return '?';
    final parts = displayName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return displayName[0].toUpperCase();
  }

  UserProfileModel copyWith({
    String? displayName,
    String? mobile,
    DateTime? dateOfBirth,
    String? avatarBase64,
  }) {
    return UserProfileModel(
      userId: userId,
      displayName: displayName ?? this.displayName,
      mobile: mobile ?? this.mobile,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      avatarBase64: avatarBase64 ?? this.avatarBase64,
    );
  }
}
