import 'player_model.dart';

class SquadModel {
  final String roomCode;
  final String roomName; // custom name set by creator
  final String hostUserId;
  final String matchTitle;
  final String homeTeam;
  final String awayTeam;
  final String homeTeamBadge;
  final String awayTeamBadge;
  final String matchTime;
  final bool isPrivate;
  final List<PlayerModel> members;
  final int maxPlayers; // max players allowed (2-10)
  final String status; // 'waiting' | 'playing' | 'finished'
  final int totalRounds;
  final bool demoMode; // demo: 5-question limit, tighter spacing

  const SquadModel({
    required this.roomCode,
    this.roomName = '',
    required this.hostUserId,
    required this.matchTitle,
    this.homeTeam = '',
    this.awayTeam = '',
    this.homeTeamBadge = '',
    this.awayTeamBadge = '',
    this.matchTime = '',
    required this.isPrivate,
    required this.members,
    this.maxPlayers = 6,
    required this.status,
    required this.totalRounds,
    this.demoMode = false,
  });

  String get hostDisplayName =>
      members.firstWhere((m) => m.isHost, orElse: () => members.first).displayName;

  bool get isFull => members.length >= maxPlayers;

  factory SquadModel.fromJson(Map<String, dynamic> json) {
    return SquadModel(
      roomCode: json['roomCode'] as String,
      roomName: json['roomName'] as String? ?? '',
      hostUserId: json['hostUserId'] as String,
      matchTitle: json['matchTitle'] as String? ?? '',
      homeTeam: json['homeTeam'] as String? ?? '',
      awayTeam: json['awayTeam'] as String? ?? '',
      homeTeamBadge: json['homeTeamBadge'] as String? ?? '',
      awayTeamBadge: json['awayTeamBadge'] as String? ?? '',
      matchTime: json['matchTime'] as String? ?? '',
      isPrivate: json['isPrivate'] as bool? ?? false,
      members: (json['members'] as List)
          .map((m) => PlayerModel.fromJson(m as Map<String, dynamic>))
          .toList(),
      maxPlayers: json['maxPlayers'] as int? ?? 6,
      status: json['status'] as String? ?? 'waiting',
      totalRounds: json['totalRounds'] as int? ?? 5,
      demoMode: json['demoMode'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'roomCode': roomCode,
    'roomName': roomName,
    'hostUserId': hostUserId,
    'matchTitle': matchTitle,
    'homeTeam': homeTeam,
    'awayTeam': awayTeam,
    'homeTeamBadge': homeTeamBadge,
    'awayTeamBadge': awayTeamBadge,
    'matchTime': matchTime,
    'isPrivate': isPrivate,
    'members': members.map((m) => m.toJson()).toList(),
    'maxPlayers': maxPlayers,
    'status': status,
    'totalRounds': totalRounds,
    'demoMode': demoMode,
  };

  SquadModel copyWith({
    String? roomName,
    List<PlayerModel>? members,
    String? status,
    int? totalRounds,
    bool? demoMode,
  }) {
    return SquadModel(
      roomCode: roomCode,
      roomName: roomName ?? this.roomName,
      hostUserId: hostUserId,
      matchTitle: matchTitle,
      homeTeam: homeTeam,
      awayTeam: awayTeam,
      homeTeamBadge: homeTeamBadge,
      awayTeamBadge: awayTeamBadge,
      matchTime: matchTime,
      isPrivate: isPrivate,
      members: members ?? this.members,
      maxPlayers: maxPlayers,
      status: status ?? this.status,
      totalRounds: totalRounds ?? this.totalRounds,
      demoMode: demoMode ?? this.demoMode,
    );
  }
}
