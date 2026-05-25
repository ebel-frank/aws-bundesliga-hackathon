import 'dart:ui';

class GameModeModel {
  final String id;
  final String title;
  final String subtitle;
  final String description;
  final String iconAsset;
  final Color accentColor;
  final Color glowColor;
  final List<String> featureTags;

  const GameModeModel({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.iconAsset,
    required this.accentColor,
    required this.glowColor,
    required this.featureTags,
  });
}
