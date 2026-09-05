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
class OrganizeTournamentScreen extends StatefulWidget {
  const OrganizeTournamentScreen({
    super.key,
    required this.friends,
    required this.busy,
    required this.onBack,
    required this.onSubmit,
  });

  final List<FriendDto> friends;
  final bool busy;
  final VoidCallback onBack;

  /// Fired once — with exactly [size] invitees, never more, never fewer, when
  /// [isPublic] is false; with no invitees at all when it's true, since a
  /// public tournament is joined by strangers, not invited by the organizer.
  final void Function(int size, List<UserDto> invitees, bool isPublic) onSubmit;

  @override
  State<OrganizeTournamentScreen> createState() => _OrganizeTournamentScreenState();
}

class _OrganizeTournamentScreenState extends State<OrganizeTournamentScreen> {
  static const _sizes = [4, 8, 16, 32];

  /// Null while the visibility step is showing.
  bool? _isPublic;

  /// Null while the size step is showing.
  int? _size;
  final Set<int> _selected = {};
  final TextEditingController _search = TextEditingController();
  String _query = '';

  static const _gradients = [
    wbTealGradient,
    wbPurpleGradient,
    wbBlueGradient,
    wbRoseGradient,
    wbAmber8Gradient,
    wbGreyGradient,
  ];
  static const _textColors = [
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
    final size = _size;
    Widget step;
    if (isPublic == null) {
      step = _visibilityStep();
    } else if (size == null) {
      step = _sizeStep();
    } else if (isPublic) {
      step = _publicConfirmStep(size);
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
        : _isPublic != null
            ? () => setState(() => _isPublic = null)
            : widget.onBack;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 13),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color.fromRGBO(255, 255, 255, .07)))),
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
              child: const Icon(Icons.arrow_back_ios_new, size: 14, color: Colors.white70),
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
        _visibilityRow(
          isPublic: false,
          icon: Icons.group_outlined,
          title: "Do'stlar bilan",
          subtitle: "Faqat siz taklif qilgan do'stlaringiz qatnasha oladi",
        ),
        const SizedBox(height: 10),
        _visibilityRow(
          isPublic: true,
          icon: Icons.public,
          title: 'Ommaviy',
          subtitle: "Istalgan o'yinchi o'zi qo'shilishi mumkin",
        ),
      ],
    );
  }

  Widget _visibilityRow({
    required bool isPublic,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Pressable(
      onTap: () => setState(() => _isPublic = isPublic),
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      children: [
        Text("Necha kishilik bo'lsin?", style: WBText.grotesk(size: 20, weight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(
          isPublic
              ? "O'lchamni tanlang — to'lgach turnir avtomatik boshlanadi."
              : "O'lchamni tanlang — keyingi qadamda shuncha do'stingizni taklif qilasiz.",
          style: WBText.grotesk(size: 13.5, color: WBColors.textA(.55), height: 1.4),
        ),
        const SizedBox(height: 20),
        for (final option in _sizes) ...[_sizeRow(option, isPublic), const SizedBox(height: 10)],
      ],
    );
  }

  Widget _sizeRow(int option, bool isPublic) {
    final enoughFriends = isPublic || widget.friends.length >= option;
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
                  Text('$option kishi', style: WBText.grotesk(size: 15, weight: FontWeight.w600)),
                  if (!enoughFriends)
                    Text(
                      "Kamida $option ta do'st kerak — hozir ${widget.friends.length} ta bor",
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
              Container(
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
              ),
            ],
          ),
        ),
        Expanded(
          child: !enough
              ? _notEnoughFriends(size)
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

  List<UserDto> _selectedUsers() =>
      widget.friends.where((f) => _selected.contains(f.user.id)).map((f) => f.user).toList();

  Widget _notEnoughFriends(int size) => Center(
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
                "$size kishilik turnir uchun kamida $size ta do'st kerak, hozir ${widget.friends.length} ta bor.",
                textAlign: TextAlign.center,
                style: WBText.grotesk(size: 13.5, color: WBColors.textA(.5), height: 1.4),
              ),
            ],
          ),
        ),
      );

  Widget _friendRow(FriendDto friend, int size) {
    final selected = _selected.contains(friend.user.id);
    final disabled = !selected && _selected.length >= size;
    return Pressable(
      onTap: disabled
          ? null
          : () => setState(() {
                if (selected) {
                  _selected.remove(friend.user.id);
                } else {
                  _selected.add(friend.user.id);
                }
              }),
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
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? WBColors.accent : Colors.transparent,
                  border: Border.all(color: selected ? WBColors.accent : WBColors.whiteA(.25), width: 2),
                ),
                alignment: Alignment.center,
                child: selected ? Icon(Icons.check, size: 14, color: WBColors.accentInk) : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

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
