import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';

import '../../app/theme/app_colors.dart';
import '../../models/fantasy_football_player_model.dart';
import '../../models/match_model.dart';
import 'controllers/fantasy_controller.dart';

class FantasyPickerView extends GetView<FantasyController> {
  const FantasyPickerView({super.key});

  @override
  Widget build(BuildContext context) {
    final pageController = PageController();

    ever(controller.pageIndex, (index) {
      if (pageController.hasClients) {
        pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
        );
      }
    });

    return WillPopScope(
      onWillPop: () async {
        if (controller.pageIndex.value > 0) {
          controller.goBackToMatchList();
          return false;
        }
        return true;
      },
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
                  color: AppColors.background.withValues(alpha: 0.82)),
            ),
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () {
                            if (controller.pageIndex.value > 0) {
                              controller.goBackToMatchList();
                            } else {
                              Get.back();
                            }
                          },
                          icon: const Icon(Icons.arrow_back,
                              color: AppColors.textPrimary),
                        ),
                        const Spacer(),
                        Obx(() {
                          const titles = ['🏟️ FANTASY', '⚽ PICK YOUR SQUAD'];
                          return Text(
                            titles[controller.pageIndex.value],
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              letterSpacing: 2,
                              color: AppColors.textSecondary,
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  Expanded(
                    child: PageView(
                      controller: pageController,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _MatchListPage(controller: controller),
                        _SquadBuilderPage(controller: controller),
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

// ─── MATCH LIST ──────────────────────────────────────────────────────────────

class _MatchListPage extends StatelessWidget {
  final FantasyController controller;
  const _MatchListPage({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          const Text('Select a Match',
              style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          const Text('Pick your 11 players and score from real events',
              style:
                  TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _ScoringChip(icon: '⚽', label: 'Goal +5', color: AppColors.neonGreen),
                const SizedBox(width: 8),
                _ScoringChip(icon: '🅰️', label: 'Assist +3', color: AppColors.electricBlue),
                const SizedBox(width: 8),
                _ScoringChip(icon: '🟨', label: 'Yellow −1', color: const Color(0xFFFFC107)),
                const SizedBox(width: 8),
                _ScoringChip(icon: '🟥', label: 'Red −2', color: AppColors.error),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Obx(() {
              if (controller.isLoadingMatches.value) {
                return const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.fantasyAccent));
              }
              if (controller.matches.isEmpty) {
                return const Center(
                    child: Text('No matches available',
                        style: TextStyle(color: AppColors.textMuted)));
              }
              return ListView.separated(
                itemCount: controller.matches.length,
                separatorBuilder: (_, __) => const SizedBox(height: 14),
                itemBuilder: (_, i) => _MatchCard(
                  match: controller.matches[i],
                  onTap: () => controller.selectMatch(controller.matches[i]),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _ScoringChip extends StatelessWidget {
  final String icon;
  final String label;
  final Color color;
  const _ScoringChip(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(icon, style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      ]),
    );
  }
}

class _MatchCard extends StatefulWidget {
  final MatchModel match;
  final VoidCallback onTap;
  const _MatchCard({required this.match, required this.onTap});

  @override
  State<_MatchCard> createState() => _MatchCardState();
}

class _MatchCardState extends State<_MatchCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isFinished = widget.match.status == 'finished';
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 8,
                  offset: const Offset(0, 3))
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(
              children: [
                Row(
                  children: [
                    Text(widget.match.league,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600)),
                    const Spacer(),
                    _statusBadge(),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          _badgeWidget(widget.match.homeTeamBadge),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(widget.match.homeTeam,
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1A2138)),
                                overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                          color: const Color(0xFF1A2138),
                          borderRadius: BorderRadius.circular(8)),
                      child: Text(widget.match.matchTime,
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                    ),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Text(widget.match.awayTeam,
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1A2138)),
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right),
                          ),
                          const SizedBox(width: 10),
                          _badgeWidget(widget.match.awayTeamBadge),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(widget.match.matchDate,
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade500)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: isFinished
                            ? Colors.grey.shade400
                            : AppColors.fantasyAccent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isFinished ? 'VIEW RESULTS' : 'PICK SQUAD',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 0.5),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusBadge() {
    if (widget.match.status == 'live') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.neonGreen.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: AppColors.neonGreen)),
          const SizedBox(width: 4),
          const Text('LIVE',
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: AppColors.neonGreen)),
        ]),
      );
    }
    if (widget.match.status == 'finished') {
      return Text('Full Time',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500));
    }
    return Text(
      '${widget.match.matchDate} · ${widget.match.matchTime}',
      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
    );
  }

  Widget _badgeWidget(String path) {
    if (path.isEmpty) {
      return Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
              shape: BoxShape.circle, color: Colors.grey.shade200),
          child:
              Icon(Icons.sports_soccer, size: 18, color: Colors.grey.shade500));
    }
    return SizedBox(
        width: 32,
        height: 32,
        child: SvgPicture.asset(path, fit: BoxFit.contain));
  }
}

// ─── SQUAD BUILDER ───────────────────────────────────────────────────────────

class _SquadBuilderPage extends StatelessWidget {
  final FantasyController controller;
  const _SquadBuilderPage({required this.controller});

  static const _positionOrder = {'GK': 0, 'DEF': 1, 'MID': 2, 'FWD': 3};
  static const _positionColors = {
    'GK': Color(0xFFFF9800),
    'DEF': Color(0xFF2979FF),
    'MID': Color(0xFF00C853),
    'FWD': Color(0xFFFF2D78),
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Match header
        Obx(() {
          final match = controller.selectedMatch.value;
          if (match == null) return const SizedBox.shrink();
          return _MatchBanner(match: match);
        }),
        // Selection counter + confirm bar
        Obx(() => _SelectionBar(
              selected: controller.selectedCount,
              canConfirm: controller.canConfirm,
              onConfirm: controller.confirmTeam,
              matchStatus: controller.matchStatus.value,
            )),
        // Player list grouped by position
        Expanded(
          child: Obx(() {
            if (controller.allPlayers.isEmpty) {
              return const Center(
                  child: CircularProgressIndicator(
                      color: AppColors.fantasyAccent));
            }
            final grouped = <String, List<FantasyFootballPlayer>>{};
            for (final p in controller.allPlayers) {
              grouped.putIfAbsent(p.position, () => []).add(p);
            }
            final sections = grouped.entries.toList()
              ..sort((a, b) => (_positionOrder[a.key] ?? 9)
                  .compareTo(_positionOrder[b.key] ?? 9));

            // Flatten into items: alternating headers and player tiles
            final items = <_ListItem>[];
            for (final section in sections) {
              items.add(_HeaderItem(section.key, section.value.length));
              for (final player in section.value) {
                items.add(_PlayerItem(player));
              }
            }

            return ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: items.length,
              itemBuilder: (ctx, i) {
                final item = items[i];
                if (item is _HeaderItem) {
                  final posColor =
                      _positionColors[item.position] ?? AppColors.textMuted;
                  return _PositionHeader(
                      position: item.position,
                      count: item.count,
                      color: posColor);
                }
                if (item is _PlayerItem) {
                  final player = item.player;
                  final posColor =
                      _positionColors[player.position] ?? AppColors.textMuted;
                  return Obx(() => _PlayerTile(
                        player: player,
                        isSelected: controller.selectedPlayerIds
                            .contains(player.id),
                        isDisabled:
                            !controller.selectedPlayerIds.contains(player.id) &&
                                controller.selectedCount >= 11,
                        positionColor: posColor,
                        onTap: () => controller.togglePlayer(player.id),
                      ));
                }
                return const SizedBox.shrink();
              },
            );
          }),
        ),
      ],
    );
  }
}

// Simple sealed-class substitute for list items
abstract class _ListItem {}

class _HeaderItem extends _ListItem {
  final String position;
  final int count;
  _HeaderItem(this.position, this.count);
}

class _PlayerItem extends _ListItem {
  final FantasyFootballPlayer player;
  _PlayerItem(this.player);
}

class _MatchBanner extends StatelessWidget {
  final MatchModel match;
  const _MatchBanner({required this.match});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppColors.fantasyAccent.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        if (match.homeTeamBadge.isNotEmpty)
          SvgPicture.asset(match.homeTeamBadge,
              width: 22,
              height: 22,
              errorBuilder: (_, __, ___) => const SizedBox(width: 22)),
        const SizedBox(width: 8),
        Expanded(
          child: Text('${match.homeTeam} vs ${match.awayTeam}',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
        ),
        if (match.status == 'live')
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.neonGreen.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text('LIVE',
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: AppColors.neonGreen)),
          ),
      ]),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  final int selected;
  final bool canConfirm;
  final VoidCallback onConfirm;
  final String matchStatus;
  const _SelectionBar({
    required this.selected,
    required this.canConfirm,
    required this.onConfirm,
    required this.matchStatus,
  });

  @override
  Widget build(BuildContext context) {
    final isLocked =
        matchStatus == 'live' || matchStatus == 'finished';
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$selected / 11 selected',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: canConfirm
                          ? AppColors.neonGreen
                          : AppColors.textPrimary,
                    )),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: selected / 11,
                    backgroundColor: AppColors.cardBorder,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      canConfirm
                          ? AppColors.neonGreen
                          : AppColors.fantasyAccent,
                    ),
                    minHeight: 4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          if (!isLocked)
            GestureDetector(
              onTap: canConfirm ? onConfirm : null,
              child: AnimatedOpacity(
                opacity: canConfirm ? 1.0 : 0.35,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.fantasyAccent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('CONFIRM',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5)),
                ),
              ),
            )
          else
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.cardBorder,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lock, size: 13, color: AppColors.textMuted),
                  SizedBox(width: 4),
                  Text('LOCKED',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textMuted)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PositionHeader extends StatelessWidget {
  final String position;
  final int count;
  final Color color;
  const _PositionHeader(
      {required this.position, required this.count, required this.color});

  static const _positionFull = {
    'GK': 'Goalkeepers',
    'DEF': 'Defenders',
    'MID': 'Midfielders',
    'FWD': 'Forwards',
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(position,
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.bold, color: color)),
        ),
        const SizedBox(width: 8),
        Text(_positionFull[position] ?? position,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary)),
        const Spacer(),
        Text('$count players',
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
      ]),
    );
  }
}

class _PlayerTile extends StatelessWidget {
  final FantasyFootballPlayer player;
  final bool isSelected;
  final bool isDisabled;
  final Color positionColor;
  final VoidCallback onTap;
  const _PlayerTile({
    required this.player,
    required this.isSelected,
    required this.isDisabled,
    required this.positionColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isDisabled && !isSelected ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.fantasyAccent.withValues(alpha: 0.12)
              : AppColors.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppColors.fantasyAccent.withValues(alpha: 0.7)
                : AppColors.cardBorder,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Opacity(
          opacity: isDisabled && !isSelected ? 0.38 : 1.0,
          child: Row(
            children: [
              // Position badge
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: positionColor.withValues(alpha: 0.15),
                  border: Border.all(
                      color: positionColor.withValues(alpha: 0.4)),
                ),
                child: Center(
                  child: Text(player.position,
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: positionColor)),
                ),
              ),
              const SizedBox(width: 12),
              if (player.teamBadge.isNotEmpty)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: SvgPicture.asset(player.teamBadge,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox(width: 20)),
                )
              else
                const SizedBox(width: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(player.name,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                    Text(player.team,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textMuted)),
                  ],
                ),
              ),
              // Check circle
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected
                      ? AppColors.fantasyAccent
                      : Colors.transparent,
                  border: Border.all(
                    color: isSelected
                        ? AppColors.fantasyAccent
                        : AppColors.textMuted,
                    width: 1.5,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
