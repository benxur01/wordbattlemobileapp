import 'package:flutter/material.dart';

import '../api/models.dart';
import '../theme.dart';
import '../widgets/primary_button.dart';

/// The friends screen's "Turnir tashkil qilish": choose whether strangers may
/// join themselves or only invited friends may, pick a bracket size, then —
/// for a friends-only tournament — pick exactly that many friends to invite.
/// A public tournament has no invitees at all; anyone self-joins later from
/// the browse screen. Everything past this screen — the invite itself, and
/// who may be invited — is enforced by the server; this only collects the
/// choices and hands them back.
///
/// A friends-only tournament also picks a format: the ordinary 1v1 bracket, or
/// a 2v2 one whose every seat is a pair of friends invited together. There is
/// no public 2v2 — a stranger arriving alone has nobody to play alongside, so
/// `TournamentService#join` refuses a team bracket and the format step is
/// skipped entirely on the public path.
class OrganizeTournamentScreen extends StatefulWidget {
  const OrganizeTournamentScreen({
    super.key,
    required this.friends,
    required this.busy,
    required this.onBack,
    required this.onSubmit,
    required this.onSubmitTeams,
  });

  final List<FriendDto> friends;
  final bool busy;
  final VoidCallback onBack;

  /// Fired once — with exactly [size] invitees, never more, never fewer, when
  /// [isPublic] is false; with no invitees at all when it's true, since a
  /// public tournament is joined by strangers, not invited by the organizer.
  final void Function(int size, List<UserDto> invitees, bool isPublic) onSubmit;

  /// The 2v2 equivalent: fired once with exactly [size] pairs, each one a team
  /// invited together. Always friends-only, so there is no visibility to hand
  /// back with it.
  final void Function(int size, List<(UserDto, UserDto)> teams) onSubmitTeams;

  @override
  State<OrganizeTournamentScreen> createState() => _OrganizeTournamentScreenState();
}

class _OrganizeTournamentScreenState extends State<OrganizeTournamentScreen> {
  static const _sizes = [4, 8, 16, 32];

  /// Null while the visibility step is showing.
  bool? _isPublic;

  /// Null while the format step is showing — never asked at all on the public
  /// path, which is 1v1 by definition.
  bool? _isTeam;

  /// Null while the size step is showing.
  int? _size;
  final Set<int> _selected = {};

  /// The 2v2 path's teams, in the order they were built.
  final List<(UserDto, UserDto)> _teams = [];

  /// The friend tapped first for the team being built right now, waiting for
  /// the tap that gives them a partner.
  UserDto? _pending;

  final TextEditingController _search = TextEditingController();
  String _query = '';

  static List<Gradient> get _gradients => [
        wbTealGradient,
        wbPurpleGradient,
        wbBlueGradient,
        wbRoseGradient,
        wbAmber8Gradient,
        wbGreyGradient,
      ];
  static List<Color> get _textColors => [
        WBColors.tealText,
        WBColors.purpleText,
        WBColors.blueText,
        WBColors.roseText,
        WBColors.amber8Text,
        WBColors.greyText,
      ];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPublic = _isPublic;
    final isTeam = _isTeam;
    final size = _size;
    Widget step;
    if (isPublic == null) {
      step = _visibilityStep();
    } else if (!isPublic && isTeam == null) {
      step = _formatStep();
    } else if (size == null) {
      step = _sizeStep();
    } else if (isPublic) {
      step = _publicConfirmStep(size);
    } else if (isTeam == true) {
      step = _teamStep(size);
    } else {
      step = _friendStep(size);
    }
    return Column(
      children: [
        _header(),
        Expanded(child: step),
      ],
    );
  }

  Widget _header() {
    final onStepBack = _size != null
        ? () => setState(() => _size = null)
        : _isTeam != null
            ? () => setState(() => _isTeam = null)
            : _isPublic != null
                ? () => setState(() => _isPublic = null)
                : widget.onBack;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 13),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: WBColors.whiteA(.07)))),
      child: Row(
        children: [
          Pressable(
            onTap: onStepBack,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: WBColors.whiteA(.05),
                border: Border.all(color: WBColors.whiteA(.1)),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.arrow_back_ios_new, size: 14, color: WBColors.textA(.7)),
            ),
          ),
          Expanded(
            child: Text(
              'Turnir tashkil qilish',
              textAlign: TextAlign.center,
              style: WBText.grotesk(size: 15, weight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 38),
        ],
      ),
    );
  }

  Widget _visibilityStep() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      children: [
        Text('Turnir qanday bo\'lsin?', style: WBText.grotesk(size: 20, weight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(
          "Do'stlaringizni o'zingiz taklif qilasizmi, yoki istalgan o'yinchi o'zi qo'shilsinmi?",
          style: WBText.grotesk(size: 13.5, color: WBColors.textA(.55), height: 1.4),
        ),
        const SizedBox(height: 20),
        _choiceRow(
          onTap: () => setState(() => _isPublic = false),
          icon: Icons.group_outlined,
          title: "Do'stlar bilan",
          subtitle: "Faqat siz taklif qilgan do'stlaringiz qatnasha oladi",
        ),
        const SizedBox(height: 10),
        _choiceRow(
          onTap: () => setState(() => _isPublic = true),
          icon: Icons.public,
          title: 'Ommaviy',
          subtitle: "Istalgan o'yinchi o'zi qo'shilishi mumkin",
        ),
      ],
    );
  }

  Widget _formatStep() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      children: [
        Text('Qanday format?', style: WBText.grotesk(size: 20, weight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(
          "Har bir o'yinchi o'zi uchun kurashadimi, yoki juftlikda o'ynaydimi?",
          style: WBText.grotesk(size: 13.5, color: WBColors.textA(.55), height: 1.4),
        ),
        const SizedBox(height: 20),
        _choiceRow(
          onTap: () => setState(() => _isTeam = false),
          icon: Icons.person_outline,
          title: 'Yakka · 1v1',
          subtitle: "Har bir o'yinchi yolg'iz o'ynaydi",
        ),
        const SizedBox(height: 10),
        _choiceRow(
          onTap: () => setState(() => _isTeam = true),
          icon: Icons.groups_outlined,
          title: 'Jamoaviy · 2v2',
          subtitle: "Har bir o'rinni ikki do'stingiz birga egallaydi",
        ),
      ],
    );
  }

  Widget _choiceRow({
    required VoidCallback onTap,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Pressable(
      onTap: onTap,
      pressScale: .98,
      borderRadius: BorderRadius.circular(17),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: WBColors.whiteA(.045),
          border: Border.all(color: WBColors.whiteA(.09)),
          borderRadius: BorderRadius.circular(17),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(gradient: wbAccentGradient, borderRadius: BorderRadius.circular(13)),
              alignment: Alignment.center,
              child: Icon(icon, size: 20, color: WBColors.accentInk),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: WBText.grotesk(size: 15, weight: FontWeight.w600)),
                  Text(subtitle, style: WBText.grotesk(size: 11.5, color: WBColors.textA(.45))),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: WBColors.textA(.4)),
          ],
        ),
      ),
    );
  }

  Widget _sizeStep() {
    final isPublic = _isPublic ?? false;
    final isTeam = _isTeam ?? false;
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      children: [
        Text(
          isTeam ? "Nechta jamoa bo'lsin?" : "Necha kishilik bo'lsin?",
          style: WBText.grotesk(size: 20, weight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          isPublic
              ? "O'lchamni tanlang — to'lgach turnir avtomatik boshlanadi."
              : isTeam
                  ? "O'lchamni tanlang — keyingi qadamda shuncha juft do'stingizni taklif qilasiz."
                  : "O'lchamni tanlang — keyingi qadamda shuncha do'stingizni taklif qilasiz.",
          style: WBText.grotesk(size: 13.5, color: WBColors.textA(.55), height: 1.4),
        ),
        const SizedBox(height: 20),
        for (final option in _sizes) ...[_sizeRow(option, isPublic, isTeam), const SizedBox(height: 10)],
      ],
    );
  }

  Widget _sizeRow(int option, bool isPublic, bool isTeam) {
    final needed = isTeam ? option * 2 : option;
    final enoughFriends = isPublic || widget.friends.length >= needed;
    return Pressable(
      onTap: () => setState(() => _size = option),
      pressScale: .98,
      borderRadius: BorderRadius.circular(17),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: WBColors.whiteA(.045),
          border: Border.all(color: WBColors.whiteA(.09)),
          borderRadius: BorderRadius.circular(17),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(gradient: wbAccentGradient, borderRadius: BorderRadius.circular(13)),
              alignment: Alignment.center,
              child: Text('1/$option', style: WBText.mono(size: 11, weight: FontWeight.w700, color: WBColors.accentInk)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isTeam ? '$option jamoa' : '$option kishi',
                    style: WBText.grotesk(size: 15, weight: FontWeight.w600),
                  ),
                  if (!enoughFriends)
                    Text(
                      "Kamida $needed ta do'st kerak — hozir ${widget.friends.length} ta bor",
                      style: WBText.grotesk(size: 11.5, color: WBColors.textA(.45)),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: WBColors.textA(.4)),
          ],
        ),
      ),
    );
  }

  /// The public-tournament path's last step — no friends to pick, just a
  /// confirmation, since anyone self-joins later from the browse screen.
  Widget _publicConfirmStep(int size) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
            children: [
              Text('Ommaviy turnir', style: WBText.grotesk(size: 20, weight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                "$size kishilik turnir yaratiladi. Kimni taklif qilish shart emas — istalgan o'yinchi o'zi qo'shilishi mumkin bo'ladi.",
                style: WBText.grotesk(size: 13.5, color: WBColors.textA(.55), height: 1.4),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 22),
          child: Pressable(
            onTap: widget.busy ? null : () => widget.onSubmit(size, const [], true),
            pressScale: .98,
            child: Container(
              width: double.infinity,
              height: 58,
              decoration: BoxDecoration(gradient: wbAccentGradient, borderRadius: BorderRadius.circular(19)),
              alignment: Alignment.center,
              child: Text(
                widget.busy ? 'Yaratilmoqda…' : 'Turnir yaratish',
                style: WBText.grotesk(size: 16, weight: FontWeight.w600, color: WBColors.accentInk),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _friendStep(int size) {
    final query = _query.trim().toLowerCase();
    final filtered =
        query.isEmpty ? widget.friends : widget.friends.where((f) => f.user.label.toLowerCase().contains(query)).toList();
    final enough = widget.friends.length >= size;
    final ready = _selected.length == size;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_selected.length}/$size tanlandi',
                style: WBText.mono(size: 12, weight: FontWeight.w600, color: WBColors.accent, letterSpacing: .05),
              ),
              const SizedBox(height: 10),
              _searchField(),
            ],
          ),
        ),
        Expanded(
          child: !enough
              ? _notEnoughFriends("$size kishilik turnir uchun kamida $size ta do'st kerak")
              : filtered.isEmpty
                  ? Center(child: Text('Hech kim topilmadi', style: WBText.grotesk(size: 13.5, color: WBColors.textA(.45))))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
                      children: [for (final friend in filtered) ...[_friendRow(friend, size), const SizedBox(height: 9)]],
                    ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 22),
          child: Pressable(
            onTap: widget.busy || !ready ? null : () => widget.onSubmit(size, _selectedUsers(), false),
            pressScale: .98,
            child: Container(
              width: double.infinity,
              height: 58,
              decoration: BoxDecoration(
                gradient: ready ? wbAccentGradient : null,
                color: ready ? null : WBColors.whiteA(.06),
                borderRadius: BorderRadius.circular(19),
              ),
              alignment: Alignment.center,
              child: Text(
                widget.busy ? 'Yuborilmoqda…' : 'Taklif yuborish',
                style: WBText.grotesk(size: 16, weight: FontWeight.w600, color: ready ? WBColors.accentInk : WBColors.textA(.4)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The 2v2 picker. One tap names the first half of a team and leaves them
  /// waiting in the line above the list; the next tap gives them a partner and
  /// closes that team, which then shows as a numbered row of its own at the
  /// top — so every pair is spelled out before "Taklif yuborish" can be
  /// pressed, and a wrong pair is undone as a whole rather than one member at
  /// a time.
  Widget _teamStep(int size) {
    final query = _query.trim().toLowerCase();
    final filtered =
        query.isEmpty ? widget.friends : widget.friends.where((f) => f.user.label.toLowerCase().contains(query)).toList();
    final needed = size * 2;
    final enough = widget.friends.length >= needed;
    final ready = _teams.length == size;
    final pending = _pending;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_teams.length}/$size jamoa tanlandi',
                style: WBText.mono(size: 12, weight: FontWeight.w600, color: WBColors.accent, letterSpacing: .05),
              ),
              const SizedBox(height: 6),
              Text(
                pending == null
                    ? "Har bir jamoa uchun ikki do'stingizni ketma-ket tanlang"
                    : "${pending.label} kim bilan o'ynaydi?",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WBText.grotesk(size: 12, color: WBColors.textA(.5)),
              ),
              const SizedBox(height: 10),
              _searchField(),
            ],
          ),
        ),
        Expanded(
          child: !enough
              ? _notEnoughFriends("$size jamoali turnir uchun kamida $needed ta do'st kerak")
              : ListView(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
                  children: [
                    for (var i = 0; i < _teams.length; i++) ...[_teamRow(i + 1, _teams[i]), const SizedBox(height: 9)],
                    if (filtered.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: Center(
                          child: Text('Hech kim topilmadi', style: WBText.grotesk(size: 13.5, color: WBColors.textA(.45))),
                        ),
                      )
                    else
                      for (final friend in filtered) ...[_teamFriendRow(friend, size), const SizedBox(height: 9)],
                  ],
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 22),
          child: Pressable(
            onTap: widget.busy || !ready ? null : () => widget.onSubmitTeams(size, List.of(_teams)),
            pressScale: .98,
            child: Container(
              width: double.infinity,
              height: 58,
              decoration: BoxDecoration(
                gradient: ready ? wbAccentGradient : null,
                color: ready ? null : WBColors.whiteA(.06),
                borderRadius: BorderRadius.circular(19),
              ),
              alignment: Alignment.center,
              child: Text(
                widget.busy ? 'Yuborilmoqda…' : 'Taklif yuborish',
                style: WBText.grotesk(size: 16, weight: FontWeight.w600, color: ready ? WBColors.accentInk : WBColors.textA(.4)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Which team this friend is already on, numbered from 1 as the rows above
  /// the list are — null while they are still free to be picked.
  int? _teamIndexOf(int userId) {
    for (var i = 0; i < _teams.length; i++) {
      if (_teams[i].$1.id == userId || _teams[i].$2.id == userId) return i + 1;
    }
    return null;
  }

  Widget _teamRow(int index, (UserDto, UserDto) team) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: WBColors.accentA(.1),
        border: Border.all(color: WBColors.accentA(.32)),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(gradient: wbAccentGradient, borderRadius: BorderRadius.circular(11)),
            alignment: Alignment.center,
            child: Text('$index', style: WBText.mono(size: 12, weight: FontWeight.w700, color: WBColors.accentInk)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${team.$1.label} + ${team.$2.label}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WBText.grotesk(size: 14, weight: FontWeight.w600),
                ),
                Text('jamoa', style: WBText.mono(size: 10.5, weight: FontWeight.w500, color: WBColors.textA(.45))),
              ],
            ),
          ),
          Pressable(
            onTap: () => setState(() => _teams.removeAt(index - 1)),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: WBColors.whiteA(.06), borderRadius: BorderRadius.circular(10)),
              alignment: Alignment.center,
              child: Icon(Icons.close, size: 15, color: WBColors.textA(.55)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _teamFriendRow(FriendDto friend, int size) {
    final teamIndex = _teamIndexOf(friend.user.id);
    final waiting = _pending;
    final isPending = waiting?.id == friend.user.id;
    final full = waiting == null && _teams.length >= size;
    return _pickerRow(
      friend: friend,
      selected: isPending,
      disabled: teamIndex != null || full,
      onTap: () => setState(() {
        if (isPending) {
          _pending = null;
        } else if (waiting == null) {
          _pending = friend.user;
        } else {
          _teams.add((waiting, friend.user));
          _pending = null;
        }
      }),
      trailing: teamIndex != null
          ? _pickTag('$teamIndex-jamoa', WBColors.textA(.5))
          : isPending
              ? _pickTag('juftini tanlang', WBColors.accent)
              : _checkCircle(false),
    );
  }

  List<UserDto> _selectedUsers() =>
      widget.friends.where((f) => _selected.contains(f.user.id)).map((f) => f.user).toList();

  Widget _pickTag(String label, Color color) =>
      Text(label, style: WBText.mono(size: 10.5, weight: FontWeight.w600, color: color, letterSpacing: .04));

  Widget _searchField() => Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: WBColors.whiteA(.05),
          border: Border.all(color: WBColors.whiteA(.11)),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          children: [
            Icon(Icons.search, size: 17, color: WBColors.textA(.4)),
            const SizedBox(width: 9),
            Expanded(
              child: TextField(
                controller: _search,
                onChanged: (value) => setState(() => _query = value),
                style: WBText.grotesk(size: 14),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: "do'stlaringiz orasidan qidiring",
                  hintStyle: WBText.grotesk(size: 14, color: WBColors.textA(.4)),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _notEnoughFriends(String requirement) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.group_off_outlined, size: 40, color: WBColors.textA(.3)),
              const SizedBox(height: 14),
              Text("Yetarli do'stingiz yo'q", style: WBText.grotesk(size: 16, weight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(
                "$requirement, hozir ${widget.friends.length} ta bor.",
                textAlign: TextAlign.center,
                style: WBText.grotesk(size: 13.5, color: WBColors.textA(.5), height: 1.4),
              ),
            ],
          ),
        ),
      );

  Widget _friendRow(FriendDto friend, int size) {
    final selected = _selected.contains(friend.user.id);
    return _pickerRow(
      friend: friend,
      selected: selected,
      disabled: !selected && _selected.length >= size,
      onTap: () => setState(() {
        if (selected) {
          _selected.remove(friend.user.id);
        } else {
          _selected.add(friend.user.id);
        }
      }),
      trailing: _checkCircle(selected),
    );
  }

  /// One tappable friend, shared by both pickers — only what its trailing
  /// mark says about the tap differs between them.
  Widget _pickerRow({
    required FriendDto friend,
    required bool selected,
    required bool disabled,
    required VoidCallback onTap,
    required Widget trailing,
  }) {
    return Pressable(
      onTap: disabled ? null : onTap,
      borderRadius: BorderRadius.circular(17),
      child: Opacity(
        opacity: disabled ? .45 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? WBColors.accentA(.12) : WBColors.whiteA(.045),
            border: Border.all(color: selected ? WBColors.accentA(.4) : WBColors.whiteA(.09)),
            borderRadius: BorderRadius.circular(17),
          ),
          child: Row(
            children: [
              _avatar(friend.user),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      friend.user.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WBText.grotesk(size: 15, weight: FontWeight.w600),
                    ),
                    Text(
                      friend.status,
                      style: WBText.mono(
                          size: 11.5, weight: FontWeight.w500, color: friend.online ? WBColors.green : WBColors.textA(.5)),
                    ),
                  ],
                ),
              ),
              trailing,
            ],
          ),
        ),
      ),
    );
  }

  Widget _checkCircle(bool selected) => Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? WBColors.accent : Colors.transparent,
          border: Border.all(color: selected ? WBColors.accent : WBColors.whiteA(.25), width: 2),
        ),
        alignment: Alignment.center,
        child: selected ? Icon(Icons.check, size: 14, color: WBColors.accentInk) : null,
      );

  Widget _avatar(UserDto user) {
    final gradient = _gradients[user.id.abs() % _gradients.length];
    final color = _textColors[user.id.abs() % _textColors.length];
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(14)),
      alignment: Alignment.center,
      child: Text(user.initial, style: WBText.grotesk(size: 16, weight: FontWeight.w700, color: color)),
    );
  }
}
