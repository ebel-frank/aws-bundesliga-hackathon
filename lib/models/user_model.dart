class UserModel {
  final String id;
  final String username;
  final String? avatarUrl;
  final int xp;
  final int level;

  const UserModel({
    required this.id,
    required this.username,
    this.avatarUrl,
    this.xp = 0,
    this.level = 1,
  });
}
