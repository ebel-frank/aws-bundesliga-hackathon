import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';

import '../../app/theme/app_colors.dart';
import '../../models/fantasy_entry_model.dart';
import '../../models/fantasy_football_player_model.dart';
import '../../models/fantasy_match_event_model.dart';
import 'controllers/fantasy_controller.dart';

/// Shows the user's squad in action — live points update as events fire.
/// Two tabs: My Team (selected 11 + event feed) and Leaderboard.
class FantasyLiveView extends GetView<FantasyController> {
  const FantasyLiveView({super.key});

  @override
  Widget build(BuildContext context) {
    // Kick off simulation when this screen mounts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.startSimulationIfLive();
    });

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/images/arena_lobby_bg.jpg',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Container(color: AppColors.background),
              ),
            ),
            Positioned.fill(
              child: Container(
                  color: AppColors.background.withValues(alpha: 0.88)),
            ),
            SafeArea(
              child: Column(
                children: [
                  _TopBar(controller: controller),
                  _MatchStatusBanner(controller: controller),
                  const SizedBox(height: 4),
                  // Tab bar
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      color: AppColors.cardSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: TabBar(
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicator: BoxDecoration(
                        color: AppColors.fantasyAccent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      labelStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5),
                      unselectedLabelStyle: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w500),
                      labelColor: Colors.white,
                      unselectedLabelColor: AppColors.textSecondary,
                      tabs: const [
                        Tab(text: 'MY TEAM'),
                        Tab(text: 'LEADERBOARD'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _MyTeamTab(controller: controller),
                        _LeaderboardTab(controller: controller),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── TOP BAR ─────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final FantasyController controller;
  const _TopBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Get.back(),
            icon: const Icon(Icons.arrow_back,
                color: AppColors.textPrimary),
          ),
          const Spacer(),
          const Text('🏆 FANTASY',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 2,
                  color: AppColors.textSecondary)),
          const Spacer(),
          // Edit team button — only when upcoming
          Obx(() {
            if (controller.matchStatus.value != 'upcoming') {
              return const SizedBox(width: 48);
            }
            return TextButton(
              onPressed: controller.editTeam,
              child: const Text('EDIT',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.fantasyAccent)),
            );
          }),
        ],
      ),
    );
  }
}

// ─── MATCH STATUS BANNER ──────────────────────────────────────────────────────

class _MatchStatusBanner extends StatelessWidget {
  final FantasyController controller;
  const _MatchStatusBanner({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final match = controller.selectedMatch.value;
      final status = controller.matchStatus.value;

      return Container(
        margin: const EdgeInsets.fromLTRB(20, 8, 20, 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: status == 'live'
                ? AppColors.neonGreen.withValues(alpha: 0.5)
                : status == 'finished'
                    ? AppColors.fantasyAccent.withValues(alpha: 0.5)
                    : AppColors.cardBorder,
          ),
        ),
        child: Row(
          children: [
            // Teams
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    match != null
                        ? '${match.homeTeam} vs ${match.awayTeam}'
                        : '',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary),
                  ),
                  if (match != null)
                    Text(match.league,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textMuted)),
                ],
              ),
            ),
            // Status chip
            _StatusChip(status: status),
          ],
        ),
      );
    });
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    IconData icon;
    switch (status) {
      case 'live':
        color = AppColors.neonGreen;
        label = 'LIVE';
        icon = Icons.circle;
        break;
      case 'finished':
        color = AppColors.fantasyAccent;
        label = 'FULL TIME';
        icon = Icons.sports_score;
        break;
      default:
        color = AppColors.textMuted;
        label = 'UPCOMING';
        icon = Icons.schedule;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 10, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.bold, color: color)),
      ]),
    );
  }
}

// ─── MY TEAM TAB ─────────────────────────────────────────────────────────────

class _MyTeamTab extends StatelessWidget {
  final FantasyController controller;
  const _MyTeamTab({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final status = controller.matchStatus.value;
      final players = controller.mySelectedPlayers;
      final events = controller.matchEvents.reversed.toList();
      final total = controller.myTotalPoints;

      if (players.isEmpty) {
        return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.people_outline,
                size: 48, color: AppColors.textMuted.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            const Text('No team selected',
                style: TextStyle(color: AppColors.textMuted)),
          ]),
        );
      }

      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          // Total score card
          _TotalScoreCard(total: total, status: status),
          const SizedBox(height: 16),
          // Upcoming waiting message
          if (status == 'upcoming') ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.cardSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.fantasyAccent.withValues(alpha: 0.35)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lock_clock,
                      color: AppColors.fantasyAccent, size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Your squad is set. Points will update once the match kicks off.',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          // Live event feed
          if (events.isNotEmpty) ...[
            const Text('RECENT EVENTS',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textMuted,
                    letterSpacing: 2)),
            const SizedBox(height: 8),
            ...events.take(6).map((e) => _EventFeedTile(event: e)),
            const SizedBox(height: 16),
          ],
          // Player list
          const Text('YOUR SQUAD',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textMuted,
                  letterSpacing: 2)),
          const SizedBox(height: 8),
          ...players.map((p) => _LivePlayerTile(player: p)),
        ],
      );
    });
  }
}

class _TotalScoreCard extends StatelessWidget {
  final int total;
  final String status;
  const _TotalScoreCard({required this.total, required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.fantasyAccent.withValues(alpha: 0.25),
            AppColors.fantasyAccent.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: AppColors.fantasyAccent.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('YOUR TOTAL',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textMuted,
                    letterSpacing: 2)),
            const SizedBox(height: 4),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('$total',
                  style: const TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                      height: 1.0)),
              const Padding(
                padding: EdgeInsets.only(bottom: 6, left: 4),
                child: Text('pts',
                    style: TextStyle(
                        fontSize: 16, color: AppColors.textSecondary)),
              ),
            ]),
          ]),
          const Spacer(),
          if (status == 'live')
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.neonGreen.withValues(alpha: 0.15),
              ),
              child: const Icon(Icons.trending_up,
                  color: AppColors.neonGreen, size: 24),
            )
          else if (status == 'finished')
            const Text('🏆',
                style: TextStyle(fontSize: 36))
          else
            const Text('⏳', style: TextStyle(fontSize: 36)),
        ],
      ),
    );
  }
}

class _EventFeedTile extends StatelessWidget {
  final FantasyMatchEvent event;
  const _EventFeedTile({required this.event});

  @override
  Widget build(BuildContext context) {
    final isPositive = event.isPositive;
    final accentColor =
        isPositive ? AppColors.neonGreen : AppColors.error;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accentColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Text(event.icon, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.playerName,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                Text('${event.label} · ${event.minute}\'',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
          ),
          Text(event.pointsLabel,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: accentColor)),
        ],
      ),
    );
  }
}

class _LivePlayerTile extends StatelessWidget {
  final FantasyFootballPlayer player;
  const _LivePlayerTile({required this.player});

  static const _positionColors = {
    'GK': Color(0xFFFF9800),
    'DEF': Color(0xFF2979FF),
    'MID': Color(0xFF00C853),
    'FWD': Color(0xFFFF2D78),
  };

  @override
  Widget build(BuildContext context) {
    final posColor =
        _positionColors[player.position] ?? AppColors.textMuted;
    final hasEvents = player.events.isNotEmpty;
    final pts = player.points;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasEvents
              ? (pts > 0
                  ? AppColors.neonGreen.withValues(alpha: 0.4)
                  : AppColors.error.withValues(alpha: 0.4))
              : AppColors.cardBorder,
        ),
      ),
      child: Row(
        children: [
          // Position badge
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: posColor.withValues(alpha: 0.15),
              border:
                  Border.all(color: posColor.withValues(alpha: 0.4)),
            ),
            child: Center(
              child: Text(player.position,
                  style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      color: posColor)),
            ),
          ),
          const SizedBox(width: 10),
          // Team badge
          if (player.teamBadge.isNotEmpty)
            SizedBox(
              width: 18,
              height: 18,
              child: SvgPicture.asset(player.teamBadge,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      const SizedBox(width: 18)),
            )
          else
            const SizedBox(width: 18),
          const SizedBox(width: 8),
          // Name
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(player.name,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                // Event badges
                if (hasEvents)
                  Wrap(
                    spacing: 4,
                    children: player.events
                        .map((e) => Text(e.icon,
                            style: const TextStyle(fontSize: 12)))
                        .toList(),
                  )
                else
                  const Text('No points yet',
                      style: TextStyle(
                          fontSize: 10, color: AppColors.textMuted)),
              ],
            ),
          ),
          // Points
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: pts > 0
                  ? AppColors.neonGreen.withValues(alpha: 0.12)
                  : pts < 0
                      ? AppColors.error.withValues(alpha: 0.12)
                      : AppColors.cardBorder.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              pts > 0 ? '+$pts' : '$pts',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: pts > 0
                    ? AppColors.neonGreen
                    : pts < 0
                        ? AppColors.error
                        : AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── LEADERBOARD TAB ─────────────────────────────────────────────────────────

class _LeaderboardTab extends StatelessWidget {
  final FantasyController controller;
  const _LeaderboardTab({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final entries = controller.leaderboard;
      final myEntry = controller.myEntry.value;
      final myTotal = controller.myTotalPoints;
      final status = controller.matchStatus.value;

      // Merge myEntry into the sorted list
      final allEntries = <_RankedEntry>[];

      // Start with the existing leaderboard
      for (int i = 0; i < entries.length; i++) {
        allEntries.add(_RankedEntry(entry: entries[i], rank: i + 1));
      }

      // Insert the user's entry if they have one (find or append)
      if (myEntry != null) {
        final existingIdx =
            allEntries.indexWhere((e) => e.entry.userId == 'me');
        final updatedMe = myEntry.copyWith(totalPoints: myTotal);
        if (existingIdx >= 0) {
          allEntries[existingIdx] =
              _RankedEntry(entry: updatedMe, rank: existingIdx + 1);
        } else {
          allEntries.add(
              _RankedEntry(entry: updatedMe, rank: allEntries.length + 1));
        }
        // Re-sort by total points
        allEntries
            .sort((a, b) => b.entry.totalPoints.compareTo(a.entry.totalPoints));
        for (int i = 0; i < allEntries.length; i++) {
          allEntries[i] = _RankedEntry(entry: allEntries[i].entry, rank: i + 1);
        }
      }

      if (allEntries.isEmpty) {
        return const Center(
          child: Text('No entries yet',
              style: TextStyle(color: AppColors.textMuted)),
        );
      }

      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          // Podium — top 3 (if match has started)
          if (status != 'upcoming' && allEntries.length >= 3) ...[
            _Podium(entries: allEntries.take(3).toList()),
            const SizedBox(height: 20),
          ],
          const Text('ALL ENTRIES',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textMuted,
                  letterSpacing: 2)),
          const SizedBox(height: 10),
          ...allEntries.map((ranked) => _LeaderboardRow(
                ranked: ranked,
                isMe: ranked.entry.userId == 'me',
              )),
        ],
      );
    });
  }
}

class _RankedEntry {
  final FantasyEntry entry;
  final int rank;
  const _RankedEntry({required this.entry, required this.rank});
}

class _Podium extends StatelessWidget {
  final List<_RankedEntry> entries;
  const _Podium({required this.entries});

  @override
  Widget build(BuildContext context) {
    if (entries.length < 3) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _PodiumSlot(ranked: entries[1], height: 72),
        const SizedBox(width: 10),
        _PodiumSlot(ranked: entries[0], height: 100),
        const SizedBox(width: 10),
        _PodiumSlot(ranked: entries[2], height: 52),
      ],
    );
  }
}

class _PodiumSlot extends StatelessWidget {
  final _RankedEntry ranked;
  final double height;
  const _PodiumSlot({required this.ranked, required this.height});

  @override
  Widget build(BuildContext context) {
    final isFirst = ranked.rank == 1;
    final medalColor = ranked.rank == 1
        ? const Color(0xFFFFD700)
        : ranked.rank == 2
            ? const Color(0xFFC0C0C0)
            : const Color(0xFFCD7F32);
    final entry = ranked.entry;

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (isFirst) const Text('👑', style: TextStyle(fontSize: 20)),
        if (isFirst) const SizedBox(height: 2),
        Container(
          width: isFirst ? 48 : 40,
          height: isFirst ? 48 : 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: entry.avatarColor,
            border: Border.all(color: medalColor, width: 2.5),
          ),
          child: Center(
            child: Text(entry.initials,
                style: TextStyle(
                    fontSize: isFirst ? 15 : 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
          ),
        ),
        const SizedBox(height: 4),
        Text(entry.displayName,
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
        Text('${entry.totalPoints} pts',
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: AppColors.fantasyAccent)),
        const SizedBox(height: 4),
        Container(
          width: 64,
          height: height,
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(6),
              topRight: Radius.circular(6),
            ),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                medalColor,
                medalColor.withValues(alpha: 0.5),
              ],
            ),
          ),
          child: Center(
            child: Text('#${ranked.rank}',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
          ),
        ),
      ],
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  final _RankedEntry ranked;
  final bool isMe;
  const _LeaderboardRow({required this.ranked, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final entry = ranked.entry;
    final rank = ranked.rank;
    final medalColor = rank == 1
        ? const Color(0xFFFFD700)
        : rank == 2
            ? const Color(0xFFC0C0C0)
            : rank == 3
                ? const Color(0xFFCD7F32)
                : AppColors.cardBorder;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isMe
            ? AppColors.fantasyAccent.withValues(alpha: 0.1)
            : AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isMe
              ? AppColors.fantasyAccent.withValues(alpha: 0.6)
              : AppColors.cardBorder,
          width: isMe ? 1.5 : 1.0,
        ),
      ),
      child: Row(
        children: [
          // Rank badge
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: rank <= 3
                  ? medalColor.withValues(alpha: 0.2)
                  : AppColors.cardBorder.withValues(alpha: 0.3),
              border: rank <= 3
                  ? Border.all(color: medalColor, width: 1.5)
                  : null,
            ),
            child: Center(
              child: Text('$rank',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: rank <= 3 ? medalColor : AppColors.textMuted)),
            ),
          ),
          const SizedBox(width: 12),
          // Avatar
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: entry.avatarColor,
            ),
            child: Center(
              child: Text(entry.initials,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
            ),
          ),
          const SizedBox(width: 12),
          // Name + "You" tag
          Expanded(
            child: Row(
              children: [
                Text(entry.displayName,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary)),
                if (isMe) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.fantasyAccent
                          .withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('YOU',
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: AppColors.fantasyAccent)),
                  ),
                ],
              ],
            ),
          ),
          // Points
          Text('${entry.totalPoints}',
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary)),
          const SizedBox(width: 2),
          const Text('pts',
              style:
                  TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}
