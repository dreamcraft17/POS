class AuthUserModel {
  final int id;
  final String username;
  final String? displayName;

  const AuthUserModel({
    required this.id,
    required this.username,
    this.displayName,
  });

  factory AuthUserModel.fromJson(Map<String, dynamic> j) => AuthUserModel(
        id: (j['id'] as num?)?.toInt() ?? 0,
        username: '${j['username'] ?? ''}',
        displayName: j['display_name']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'display_name': displayName,
      };
}
