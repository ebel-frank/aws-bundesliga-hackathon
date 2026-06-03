import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';

import '../../app/theme/app_colors.dart';
import '../../models/match_model.dart';
import '../../services/auth_service.dart';
import 'controllers/arena_controller.dart';
import 'widgets/room_card_widget.dart';
import 'widgets/room_code_widget.dart';
import 'widgets/squad_avatar_widget.dart';

class ArenaLobbyView extends GetView<ArenaController> {
  const ArenaLobbyView({super.key});

  @override
  Widget build(BuildContext context) {
    final pageController = PageController();

    // Fetch matches on first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.fetchMatches();
    });

    // Listen to page index changes
    ever(controller.arenaPageIndex, (index) {
      if (pageController.hasClients) {
        pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      }
      // Refresh rooms when navigating back to room list
      if (index == 1) {
        controller.fetchAvailableRooms();
      }
    });

    return WillPopScope(
      onWillPop: () async {
        if (controller.arenaPageIndex.value > 0) {
          controller.arenaPageIndex.value--;
          return false;
        }
        Get.back();
        return true;
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          children: [
            // Shared background image
            Positioned.fill(
              child: Image.asset(
                'assets/images/arena_lobby_bg.jpg',
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(color: AppColors.background),
              ),
            ),
            Positioned.fill(
              child: Container(color: AppColors.background.withValues(alpha: 0.58)),
            ),
            // Content
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  // Top bar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () {
                            if (controller.arenaPageIndex.value > 0) {
                              controller.arenaPageIndex.value--;
                            } else {
                              Get.back();
                            }
                          },
                          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                        ),
                        const Spacer(),
                        Obx(() {
                          final titles = ['⚔️ ARENA', '🏟️ ROOMS', '🛡️ SQUAD LOBBY'];
                          return Text(
                            titles[controller.arenaPageIndex.value],
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400, letterSpacing: 2, color: AppColors.textSecondary),
                          );
                        }),
                      ],
                    ),
                  ),
                  // PageView
                  Expanded(
                    child: PageView(
                      controller: pageController,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _MatchListPage(controller: controller),
                        _RoomListPage(controller: controller),
                        _SquadLobbyPage(controller: controller),
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

// ─── PAGE 0: MATCH LIST ─────────────────────────────────────────────────────

class _MatchListPage extends StatelessWidget {
  final ArenaController controller;
  const _MatchListPage({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.isLoadingMatches.value) {
        return const Center(child: CircularProgressIndicator(color: AppColors.arenaAccent));
      }
      if (controller.availableMatches.isEmpty) {
        return const Center(child: Text('No matches available', style: TextStyle(color: AppColors.textMuted)));
      }

      // Sort: live first, then Today, Tomorrow, then others
      final sorted = List<MatchModel>.from(controller.availableMatches);
      sorted.sort((a, b) {
        const priority = {'live': 0, 'upcoming': 1, 'finished': 2};
        final statusCompare = (priority[a.status] ?? 1).compareTo(priority[b.status] ?? 1);
        if (statusCompare != 0) return statusCompare;
        const datePriority = {'Today': 0, 'Tomorrow': 1};
        final aDate = datePriority[a.matchDate] ?? 2;
        final bDate = datePriority[b.matchDate] ?? 2;
        return aDate.compareTo(bDate);
      });

      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: sorted.length + 1, // +1 for header
        itemBuilder: (_, i) {
          if (i == 0) {
            return const Padding(
              padding: EdgeInsets.only(top: 24, bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Select a Match', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                  SizedBox(height: 4),
                  Text('Choose a match to predict on', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                ],
              ),
            );
          }
          final match = sorted[i - 1];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _MatchCard(
              match: match,
              onTap: () => controller.selectMatch(match),
            ),
          );
        },
      );
    });
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
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) { setState(() => _pressed = false); widget.onTap(); },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 8, offset: const Offset(0, 3))],
          ),
          child: Stack(
            children: [
              // Background team badges (blended)
              if (widget.match.homeTeamBadge.isNotEmpty)
                Positioned(
                  left: -40,
                  top: 0,
                  bottom: 0,
                  child: Opacity(
                    opacity: 0.06,
                    child: SvgPicture.asset(
                      widget.match.homeTeamBadge,
                      fit: BoxFit.fitHeight,
                    ),
                  ),
                ),
              if (widget.match.awayTeamBadge.isNotEmpty)
                Positioned(
                  right: -40,
                  top: 0,
                  bottom: 0,
                  child: Opacity(
                    opacity: 0.06,
                    child: SvgPicture.asset(
                      widget.match.awayTeamBadge,
                      fit: BoxFit.fitHeight,
                    ),
                  ),
                ),
              // Content
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Column(
                  children: [
                    // League + date row
                    Row(
                      children: [
                        Text(widget.match.league, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
                        const Spacer(),
                        if (widget.match.status == 'live')
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: AppColors.neonGreen.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.neonGreen)),
                                const SizedBox(width: 4),
                                const Text('LIVE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.neonGreen)),
                              ],
                            ),
                          )
                        else
                          Text('${widget.match.matchDate} · ${widget.match.matchTime}', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Fixture row
                    Row(
                      children: [
                        // Home
                        Expanded(
                          child: Row(
                            children: [
                              _badge(widget.match.homeTeamBadge),
                              const SizedBox(width: 10),
                              Expanded(child: Text(widget.match.homeTeam, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A2138)), overflow: TextOverflow.ellipsis)),
                            ],
                          ),
                        ),
                        // VS pill
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(color: const Color(0xFF1A2138), borderRadius: BorderRadius.circular(8)),
                          child: Text(widget.match.matchTime, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                        ),
                        // Away
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Expanded(child: Text(widget.match.awayTeam, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A2138)), overflow: TextOverflow.ellipsis, textAlign: TextAlign.right)),
                              const SizedBox(width: 10),
                              _badge(widget.match.awayTeamBadge),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Bottom info
                    Row(
                      children: [
                        Icon(Icons.people_outline, size: 15, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Text('${widget.match.roomCount} rooms', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(color: AppColors.arenaAccent, borderRadius: BorderRadius.circular(6)),
                          child: const Text('PREDICT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(String path) {
    if (path.isEmpty) {
      return Container(width: 32, height: 32, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.grey.shade200), child: Icon(Icons.sports_soccer, size: 18, color: Colors.grey.shade500));
    }
    return SizedBox(
      width: 32,
      height: 32,
      child: SvgPicture.asset(
        path,
        width: 32,
        height: 32,
        fit: BoxFit.contain,
        placeholderBuilder: (_) => Icon(Icons.sports_soccer, size: 18, color: Colors.grey.shade500),
      ),
    );
  }
}

// ─── PAGE 1: ROOM LIST ──────────────────────────────────────────────────────

class _RoomListPage extends StatelessWidget {
  final ArenaController controller;
  const _RoomListPage({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          // Selected match header
          Obx(() {
            final match = controller.selectedMatch.value;
            if (match == null) return const SizedBox.shrink();
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.cardSurface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.cardBorder)),
              child: Row(
                children: [
                  if (match.homeTeamBadge.isNotEmpty) SvgPicture.asset(match.homeTeamBadge, width: 24, height: 24),
                  const SizedBox(width: 8),
                  Expanded(child: Text('${match.homeTeam} vs ${match.awayTeam}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
                  Text(match.matchTime, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            );
          }),
          const SizedBox(height: 20),
          const Text('Available Rooms', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          const Text('Join a room or create your own', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          // Search bar
          Container(
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.cardSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: TextField(
              onChanged: (v) => controller.roomSearchQuery.value = v,
              style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search rooms...',
                hintStyle: TextStyle(fontSize: 13, color: AppColors.textMuted.withValues(alpha: 0.6)),
                prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.textMuted),
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Create room card
          _buildCreateRoomCard(context),
          const SizedBox(height: 16),
          // Room list
          Expanded(
            child: Obx(() {
              if (controller.isLoadingRooms.value) {
                return const Center(child: CircularProgressIndicator(color: AppColors.arenaAccent));
              }
              if (controller.availableRooms.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.meeting_room_outlined, size: 48, color: AppColors.textMuted.withValues(alpha: 0.5)),
                      const SizedBox(height: 12),
                      const Text('No rooms yet. Be the first!', style: TextStyle(fontSize: 14, color: AppColors.textMuted)),
                    ],
                  ),
                );
              }
              final rooms = controller.filteredRooms;
              if (rooms.isEmpty) {
                return const Center(child: Text('No rooms match your search', style: TextStyle(fontSize: 14, color: AppColors.textMuted)));
              }
              return ListView.separated(
                itemCount: rooms.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, i) {
                  final room = rooms[i];
                  return RoomCardWidget(
                    room: room,
                    isJoined: room.members.any((m) => m.userId == AuthService.userId),
                    onTap: () => _onRoomTap(context, room),
                  );
                },
              );
            }),
          ),
          Obx(() {
            if (controller.errorMessage.value.isEmpty) return const SizedBox.shrink();
            return Padding(padding: const EdgeInsets.only(top: 8, bottom: 8), child: Text(controller.errorMessage.value, style: const TextStyle(fontSize: 12, color: AppColors.error)));
          }),
        ],
      ),
    );
  }

  Widget _buildCreateRoomCard(BuildContext context) {
    return GestureDetector(
      onTap: () => _showCreateRoomSheet(context),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.arenaAccent.withValues(alpha: 0.5)),
        ),
        child: const Row(
          children: [
            Icon(Icons.add_circle_outline, color: AppColors.arenaAccent, size: 22),
            SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Create Room', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              Text('Start your own squad', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
            ])),
            Icon(Icons.arrow_forward_ios, color: AppColors.textMuted, size: 16),
          ],
        ),
      ),
    );
  }

  void _onRoomTap(BuildContext context, dynamic room) {
    if (room.isPrivate) {
      _showPrivateRoomDialog(context, room.roomCode as String);
    } else {
      controller.joinRoom(room.roomCode as String);
    }
  }

  void _showCreateRoomSheet(BuildContext context) {
    final nameCtrl = TextEditingController();
    final maxPlayersNotifier = ValueNotifier<int>(6);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(color: AppColors.cardSurface, borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24))),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Create a Room', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                const SizedBox(height: 20),
                const Text('ROOM NAME', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textMuted, letterSpacing: 1)),
                const SizedBox(height: 6),
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'e.g., The Prediction Kings',
                    hintStyle: TextStyle(fontSize: 13, color: AppColors.textMuted.withValues(alpha: 0.5)),
                    filled: true, fillColor: AppColors.background,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.cardBorder)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.cardBorder)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.arenaAccent)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('MAX PLAYERS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textMuted, letterSpacing: 1)),
                const SizedBox(height: 6),
                ValueListenableBuilder<int>(
                  valueListenable: maxPlayersNotifier,
                  builder: (_, maxPlayers, _) => Row(
                    children: [
                      Text('$maxPlayers players', style: const TextStyle(fontSize: 14, color: AppColors.textPrimary)),
                      const Spacer(),
                      IconButton(onPressed: maxPlayers > 2 ? () => maxPlayersNotifier.value-- : null, icon: Icon(Icons.remove_circle_outline, color: maxPlayers > 2 ? AppColors.textSecondary : AppColors.textMuted)),
                      IconButton(onPressed: maxPlayers < 10 ? () => maxPlayersNotifier.value++ : null, icon: Icon(Icons.add_circle_outline, color: maxPlayers < 10 ? AppColors.arenaAccent : AppColors.textMuted)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.cardBorder)),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_outline, color: AppColors.textMuted, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Private Room', style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                        Text('Requires code to join', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                      ])),
                      Obx(() => Switch(value: controller.isPrivateToggle.value, onChanged: (v) => controller.isPrivateToggle.value = v, activeColor: AppColors.arenaAccent)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) return;
                    final exists = controller.availableRooms.any((r) => r.roomName.toLowerCase() == name.toLowerCase());
                    if (exists) {
                      controller.errorMessage.value = 'Room name already taken';
                      return;
                    }
                    Navigator.of(sheetContext).pop();
                    controller.createRoom(roomName: name, maxPlayers: maxPlayersNotifier.value, isPrivate: controller.isPrivateToggle.value);
                  },
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: AppColors.arenaAccent),
                    child: const Center(child: Text('CREATE ROOM', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1))),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showPrivateRoomDialog(BuildContext context, String roomCode) {
    final codeCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.cardSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock, size: 28, color: AppColors.arenaAccent),
              const SizedBox(height: 12),
              const Text('Enter Room Code', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              const SizedBox(height: 16),
              TextField(
                controller: codeCtrl, maxLength: 6, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary, letterSpacing: 6),
                decoration: InputDecoration(counterText: '', hintText: '------', hintStyle: TextStyle(color: AppColors.textMuted.withValues(alpha: 0.4), letterSpacing: 6), filled: true, fillColor: AppColors.background, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.cardBorder)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.arenaAccent))),
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)))),
                const SizedBox(width: 12),
                Expanded(child: GestureDetector(
                  onTap: () { if (codeCtrl.text.trim().length == 6) { Navigator.of(ctx).pop(); controller.joinRoom(roomCode, code: codeCtrl.text.trim()); } },
                  child: Container(height: 42, decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: AppColors.arenaAccent), child: const Center(child: Text('JOIN', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)))),
                )),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── PAGE 2: SQUAD LOBBY ────────────────────────────────────────────────────

class _SquadLobbyPage extends StatelessWidget {
  final ArenaController controller;
  const _SquadLobbyPage({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          const SizedBox(height: 24),
          Obx(() => _buildMatchStatus()),
          const SizedBox(height: 24),
          // Room code — only for private rooms
          Obx(() {
            final isPrivate = controller.squad.value?.isPrivate ?? false;
            if (!isPrivate) return const SizedBox.shrink();
            return Column(children: [
              RoomCodeWidget(code: controller.squad.value?.roomCode ?? '------'),
              const SizedBox(height: 8),
              const Text('Share this code with your squad', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 24),
            ]);
          }),
          // Players header
          Obx(() => Align(alignment: Alignment.centerLeft, child: Text('PLAYERS (${controller.squad.value?.members.length ?? 0}/6)', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textMuted, letterSpacing: 2)))),
          const SizedBox(height: 12),
          Obx(() {
            final members = controller.squad.value?.members ?? [];
            return GridView.count(crossAxisCount: 3, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 0.75, children: List.generate(6, (i) => SquadAvatarWidget(player: i < members.length ? members[i] : null)));
          }),
          const Spacer(),
          Obx(() {
            final isHost = (controller.squad.value?.members.isNotEmpty ?? false) && controller.squad.value!.members.first.isHost;
            final isLive = controller.isMatchLive.value;
            if (isHost && isLive) return _buildStartButton();
            if (!isLive) return _buildCountdownWaiting();
            return _buildWaitingForHost();
          }),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildMatchStatus() {
    if (controller.isMatchLive.value) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(color: AppColors.neonGreen.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.neonGreen.withValues(alpha: 0.4))),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.neonGreen)),
          const SizedBox(width: 8),
          const Text('MATCH IS LIVE', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.neonGreen, letterSpacing: 1)),
        ]),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: AppColors.cardSurface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.arenaAccent.withValues(alpha: 0.3))),
      child: Column(children: [
        const Text('MATCH STARTS IN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textMuted, letterSpacing: 2)),
        const SizedBox(height: 8),
        Text('${controller.matchCountdownSeconds.value}s', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: AppColors.arenaAccent)),
        const SizedBox(height: 4),
        const Text('Get ready to predict!', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ]),
    );
  }

  Widget _buildStartButton() {
    final members = controller.squad.value?.members ?? [];
    final enabled = members.length >= 2;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!enabled)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text(
              'Need at least 2 players to start',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
          ),
        GestureDetector(
          onTap: enabled ? () => controller.startGame() : null,
          child: Opacity(
            opacity: enabled ? 1.0 : 0.4,
            child: Container(
              height: 52,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: AppColors.arenaAccent),
              child: const Center(child: Text('⚡ START GAME', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1))),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCountdownWaiting() {
    return const Column(children: [
      Text('Waiting for match to start...', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
      SizedBox(height: 8),
      LinearProgressIndicator(color: AppColors.arenaAccent, backgroundColor: AppColors.cardBorder),
    ]);
  }

  Widget _buildWaitingForHost() {
    return const Column(children: [
      Text('Match is live! Waiting for host...', style: TextStyle(fontSize: 14, color: AppColors.textSecondary), textAlign: TextAlign.center),
      SizedBox(height: 8),
      LinearProgressIndicator(color: AppColors.neonGreen, backgroundColor: AppColors.cardBorder),
    ]);
  }
}
