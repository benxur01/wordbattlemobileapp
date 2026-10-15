import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../theme.dart';
import '../api/models.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/dashed_border.dart';
import '../widgets/flame_badge.dart';
import '../widgets/primary_button.dart';
import '../widgets/provisional_badge.dart';
import '../widgets/spinner_ring.dart';
import '../widgets/stroke_glyph.dart';

/// The player's own profile, entirely server-driven: stats, the 30-day rating
/// chart and which badges are unlocked.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.profile,
    required this.onHome,
    required this.onFriends,
    required this.onBoard,
    required this.friendRequestCount,
    required this.onHistory,
    required this.onBlockedUsers,
    required this.onPrivacyPolicy,
    required this.onTerms,
    this.passwordResetAvailable = false,
    this.recoveryEmailVerified = false,
    this.recoveryEmailMasked,
    this.recoveryEmailPending,
    this.recoveryEmailResendAfterSeconds = 0,
    this.onRequestRecoveryEmail,
    this.onVerifyRecoveryEmail,
    required this.onLogout,
    required this.onDeleteAccount,
    this.busy = false,
    this.previousTab,
  });

  /// Null while the request is in flight.
  final ProfileDto? profile;
  final VoidCallback onHome;
  final VoidCallback onFriends;
  final VoidCallback onBoard;
  final int friendRequestCount;

  /// Opens the finished-battles list. The numbers above it are totals; this is
  /// where they come from.
  final VoidCallback onHistory;

  /// Opens the list of players this account has blocked — the one place a
  /// block is taken back.
  final VoidCallback onBlockedUsers;

  /// Open the server's `/privacy` and `/terms` pages in the phone's browser.
  final VoidCallback onPrivacyPolicy;
  final VoidCallback onTerms;

  final bool passwordResetAvailable;
  final bool recoveryEmailVerified;
  final String? recoveryEmailMasked;
  final String? recoveryEmailPending;
  final int recoveryEmailResendAfterSeconds;
  final Future<bool> Function(String email)? onRequestRecoveryEmail;
  final Future<bool> Function(String code)? onVerifyRecoveryEmail;

  /// Signs out on this device; the account itself stays.
  final VoidCallback onLogout;

  /// Deletes the account for good. Confirmed here before it is called.
  final VoidCallback onDeleteAccount;

  /// True while a sign-out or deletion is in flight.
  final bool busy;

  /// Which tab the previous screen highlighted, so the bar can animate.
  final WBTab? previousTab;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  /// Deleting an account cannot be undone, so the button asks once more in
  /// place rather than acting on the first tap. Inline instead of a dialog:
  /// the whole UI is a scaled fixed-width canvas, and a system dialog would
  /// land outside it at a different size.
  bool _confirmingDelete = false;
  bool _editingRecoveryEmail = false;
  String _recoveryEmail = '';
  String _recoveryCode = '';
  late final TextEditingController _recoveryEmailController = TextEditingController(
    text: widget.recoveryEmailPending ?? '',
  );
  late final TextEditingController _recoveryCodeController = TextEditingController();
  Timer? _recoveryResendTimer;
  DateTime? _recoveryResendDeadline;
  int _recoveryResendSeconds = 0;

  @override
  void initState() {
    super.initState();
    _startRecoveryResendCountdown(widget.recoveryEmailResendAfterSeconds);
  }

  @override
  void dispose() {
    _recoveryResendTimer?.cancel();
    _recoveryEmailController.dispose();
    _recoveryCodeController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.recoveryEmailResendAfterSeconds != oldWidget.recoveryEmailResendAfterSeconds) {
      _startRecoveryResendCountdown(widget.recoveryEmailResendAfterSeconds);
    }
    if (widget.recoveryEmailPending != oldWidget.recoveryEmailPending && widget.recoveryEmailPending != null) {
      _recoveryEmail = widget.recoveryEmailPending!;
      _recoveryEmailController.value = TextEditingValue(
        text: _recoveryEmail,
        selection: TextSelection.collapsed(offset: _recoveryEmail.length),
      );
      _recoveryCode = '';
      _recoveryCodeController.clear();
      _editingRecoveryEmail = true;
    }
    if (widget.recoveryEmailVerified && widget.recoveryEmailPending == null) {
      _startRecoveryResendCountdown(0);
      _editingRecoveryEmail = false;
      _recoveryCode = '';
      _recoveryCodeController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final friendRequestCount = widget.friendRequestCount;
    final previousTab = widget.previousTab;
    final onHome = widget.onHome;
    final onFriends = widget.onFriends;
    final onBoard = widget.onBoard;
    final data = profile;
    if (data == null) {
      return Column(
        children: [
          Expanded(
            child: Center(
              child: SpinnerRing(
                size: 26,
                trackColor: WBColors.textA(.15),
                activeColor: WBColors.accent,
                strokeWidth: 2.5,
              ),
            ),
          ),
          BottomNav(
            active: WBTab.profile,
            previous: previousTab,
            friendRequestCount: friendRequestCount,
            onHome: onHome,
            onFriends: onFriends,
            onBoard: onBoard,
            onProfile: () {},
          ),
        ],
      );
    }

    final user = data.user;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 16),
            children: [
              Row(
                children: [
                  Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      gradient: wbPurpleGradient,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      user.initial,
                      style: WBText.grotesk(size: 24, weight: FontWeight.w700, color: WBColors.purpleText),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WBText.grotesk(size: 21, weight: FontWeight.w700),
                        ),
                        Text(
                          [
                            '${data.battles} jang',
                            if (user.city != null) user.city!,
                            '№${data.globalRank}',
                          ].where((part) => part.isNotEmpty).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WBText.grotesk(size: 12.5, color: WBColors.textA(.5)),
                        ),
                      ],
                    ),
                  ),
                  // The row's `gap:14px` applies here too — without it the meta
                  // line runs straight into the rating column.
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (user.provisional) ...[
                            ProvisionalBadge(size: 11),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            '${user.rating}',
                            style: WBText.mono(size: 24, weight: FontWeight.w700, color: WBColors.accent),
                          ),
                        ],
                      ),
                      Text(
                        '${data.weeklyDelta >= 0 ? '+' : ''}${data.weeklyDelta} hafta',
                        style: WBText.mono(
                          size: 11,
                          weight: FontWeight.w500,
                          color: data.weeklyDelta >= 0 ? WBColors.green : WBColors.redSoft,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                decoration: BoxDecoration(
                  color: WBColors.whiteA(.045),
                  border: Border.all(color: WBColors.whiteA(.09)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Reyting o'sishi", style: WBText.grotesk(size: 13.5, weight: FontWeight.w600)),
                        Text(
                          '30 KUN',
                          style: WBText.mono(
                            size: 10.5,
                            weight: FontWeight.w500,
                            color: WBColors.textA(.4),
                            letterSpacing: .12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 96,
                      width: double.infinity,
                      child: data.ratingHistory.length < 2
                          ? Center(
                              child: Text(
                                "Bir nechta jangdan keyin grafik paydo bo'ladi",
                                style: WBText.grotesk(size: 12, color: WBColors.textA(.5)),
                              ),
                            )
                          : CustomPaint(painter: _RatingChartPainter(data.ratingHistory)),
                    ),
                    const SizedBox(height: 4),
                    if (data.ratingHistory.length >= 2)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _dayLabel(data.ratingHistory.first.at),
                            style: WBText.mono(size: 10, weight: FontWeight.w500, color: WBColors.textA(.35)),
                          ),
                          Text(
                            _dayLabel(data.ratingHistory.last.at),
                            style: WBText.mono(size: 10, weight: FontWeight.w500, color: WBColors.textA(.35)),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // `grid-template-columns:1fr 1fr` with auto row height. A
              // GridView would need a fixed childAspectRatio, and any guess
              // clipped the numbers by a few pixels — these rows size to their
              // content the way the CSS grid does.
              Row(
                children: [
                  Expanded(
                    child: _StatCard(value: '${data.battles}', label: 'jang'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatCard(
                      value: '${data.winPercent}%',
                      label: 'yutuq',
                      color: WBColors.green,
                      tint: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _StatCard(value: '${data.longestChain}', label: 'eng uzun zanjir'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatCard(
                      value: '${data.streakDays}',
                      label: 'kunlik streak',
                      color: WBColors.flameText,
                      tint: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _historyRow(),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Nishonlar', style: WBText.grotesk(size: 13.5, weight: FontWeight.w600)),
                  Text(
                    '${data.badges.where((b) => b.unlocked).length} / ${data.badges.length}',
                    style: WBText.mono(size: 11.5, weight: FontWeight.w500, color: WBColors.textA(.4)),
                  ),
                ],
              ),
              const SizedBox(height: 11),
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1,
                // The server says which badges are unlocked; the mark for each
                // one stays a client-side detail keyed by its code.
                children: [for (final badge in data.badges) _badgeTile(badge)],
              ),
              const SizedBox(height: 22),
              _appearanceSection(),
              const SizedBox(height: 22),
              _privacySection(),
              const SizedBox(height: 22),
              _recoveryEmailSection(),
              const SizedBox(height: 22),
              _accountSection(),
            ],
          ),
        ),
        BottomNav(
          active: WBTab.profile,
          previous: previousTab,
          friendRequestCount: friendRequestCount,
          onHome: onHome,
          onFriends: onFriends,
          onBoard: onBoard,
          onProfile: () {},
        ),
      ],
    );
  }

  /// The way into the finished-battles list. It sits under the stat cards
  /// because those are the totals it details, and above the badges, which are
  /// about what is still ahead.
  Widget _historyRow() {
    return Pressable(
      onTap: widget.onHistory,
      hoverColor: WBColors.whiteA(.06),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: WBColors.whiteA(.045),
          border: Border.all(color: WBColors.whiteA(.09)),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Janglar tarixi', style: WBText.grotesk(size: 13.5, weight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    "oxirgi janglar va reyting o'zgarishi",
                    style: WBText.grotesk(size: 12, color: WBColors.textA(.5)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            StrokeGlyph.chevronRight(size: 9, thickness: 2, color: WBColors.textA(.4)),
          ],
        ),
      ),
    );
  }

  /// Dark, light, or whatever the phone itself is set to. The choice is the
  /// player's own and is kept on the device, so it is read from and written to
  /// [WBTheme] here rather than travelling through AppRoot the way everything
  /// the server owns does.
  Widget _appearanceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Ko'rinish", style: WBText.grotesk(size: 13.5, weight: FontWeight.w600)),
        const SizedBox(height: 11),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: WBColors.whiteA(.045),
            border: Border.all(color: WBColors.whiteA(.09)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              // Not `const`: these read the palette they are drawing, and a
              // const widget would be handed back unchanged the moment it
              // changes them.
              _ThemeOption(label: 'Tizim', mode: WBThemeMode.system),
              _ThemeOption(label: "Yorug'", mode: WBThemeMode.light),
              _ThemeOption(label: 'Tungi', mode: WBThemeMode.dark),
            ],
          ),
        ),
      ],
    );
  }

  /// The blocked-players list, and the two documents both stores insist a
  /// player can reach from inside the app. The documents are the server's own
  /// pages, which is why their rows point out of the app rather than onward.
  Widget _privacySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Maxfiylik', style: WBText.grotesk(size: 13.5, weight: FontWeight.w600)),
        const SizedBox(height: 11),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: WBColors.whiteA(.045),
            border: Border.all(color: WBColors.whiteA(.09)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              _LinkRow(label: "Bloklangan o'yinchilar", onTap: widget.onBlockedUsers),
              Container(height: 1, color: WBColors.whiteA(.07)),
              _LinkRow(label: 'Maxfiylik siyosati', onTap: widget.onPrivacyPolicy, external: true),
              Container(height: 1, color: WBColors.whiteA(.07)),
              _LinkRow(label: 'Foydalanish shartlari', onTap: widget.onTerms, external: true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _recoveryEmailSection() {
    if (!widget.passwordResetAvailable) return const SizedBox.shrink();
    final pendingEmail = widget.recoveryEmailPending;
    final hasPending = pendingEmail != null && pendingEmail.isNotEmpty;
    final showForm = !widget.recoveryEmailVerified || hasPending || _editingRecoveryEmail;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Parolni tiklash', style: WBText.grotesk(size: 13.5, weight: FontWeight.w600)),
        const SizedBox(height: 11),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: WBColors.whiteA(.045),
            border: Border.all(color: WBColors.whiteA(.09)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.recoveryEmailVerified)
                Row(
                  children: [
                    Icon(Icons.verified_rounded, size: 17, color: WBColors.green),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        'Tasdiqlangan: ${widget.recoveryEmailMasked ?? 'email'}',
                        style: WBText.grotesk(size: 12.5, weight: FontWeight.w600, color: WBColors.green),
                      ),
                    ),
                  ],
                )
              else
                Text(
                  'Parolni tiklash uchun emailni tasdiqlang.',
                  style: WBText.grotesk(size: 12.5, color: WBColors.textA(.65)),
                ),
              if (hasPending) ...[
                const SizedBox(height: 8),
                Text('Tasdiqlash kutilmoqda: $pendingEmail',
                    style: WBText.grotesk(size: 12, color: WBColors.textA(.68))),
              ],
              if (showForm) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _recoveryEmailController,
                  enabled: !widget.busy,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: hasPending ? TextInputAction.next : TextInputAction.done,
                  autocorrect: false,
                  enableSuggestions: false,
                  maxLength: 320,
                  onChanged: (value) => _recoveryEmail = value,
                  decoration: const InputDecoration(
                    labelText: 'Tiklash emaili',
                    counterText: '',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  style: WBText.grotesk(size: 14),
                ),
                if (hasPending) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _recoveryCodeController,
                    enabled: !widget.busy,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    maxLength: 8,
                    onChanged: (value) => _recoveryCode = value,
                    decoration: const InputDecoration(
                      labelText: 'Emaildagi 8 xonali kod',
                      counterText: '',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    style: WBText.mono(size: 16, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  _AccountButton(
                    label: widget.busy
                        ? 'Yuborilmoqda…'
                        : _recoveryResendSeconds > 0
                            ? 'Yangi kod ${_recoveryResendSeconds}s dan keyin'
                            : 'Kodni qayta yuborish',
                    color: WBColors.textA(.78),
                    border: WBColors.whiteA(.15),
                    onTap: widget.busy || _recoveryResendSeconds > 0 || !_validRecoveryEmail
                        ? null
                        : _sendRecoveryEmail,
                  ),
                  const SizedBox(height: 8),
                  _AccountButton(
                    label: widget.busy ? 'Tekshirilmoqda…' : 'Emailni tasdiqlash',
                    color: WBColors.accent,
                    border: WBColors.accentA(.35),
                    fill: WBColors.accentA(.08),
                    onTap: widget.busy || _recoveryCode.trim().length != 8 ? null : _verifyRecoveryEmail,
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  _AccountButton(
                    label: widget.busy ? 'Yuborilmoqda…' : 'Tasdiqlash kodini yuborish',
                    color: WBColors.accent,
                    border: WBColors.accentA(.35),
                    fill: WBColors.accentA(.08),
                    onTap: widget.busy || !_validRecoveryEmail ? null : _sendRecoveryEmail,
                  ),
                ],
              ] else ...[
                const SizedBox(height: 10),
                _AccountButton(
                  label: 'Emailni almashtirish',
                  color: WBColors.textA(.78),
                  border: WBColors.whiteA(.15),
                  onTap: widget.busy ? null : () => setState(() => _editingRecoveryEmail = true),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  bool get _validRecoveryEmail =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_recoveryEmailController.text.trim());

  void _startRecoveryResendCountdown(int seconds) {
    _recoveryResendTimer?.cancel();
    _recoveryResendSeconds = seconds.clamp(0, 60).toInt();
    if (_recoveryResendSeconds == 0) {
      _recoveryResendDeadline = null;
      return;
    }
    _recoveryResendDeadline = DateTime.now().add(Duration(seconds: _recoveryResendSeconds));
    _recoveryResendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final left = _recoveryResendDeadline!.difference(DateTime.now()).inSeconds;
      setState(() => _recoveryResendSeconds = left.clamp(0, 60).toInt());
      if (_recoveryResendSeconds == 0) timer.cancel();
    });
  }

  Future<void> _sendRecoveryEmail() async {
    final request = widget.onRequestRecoveryEmail;
    if (request == null || widget.busy || !_validRecoveryEmail) return;
    final sent = await request(_recoveryEmailController.text.trim());
    if (mounted && sent) {
      setState(() {
        _recoveryEmail = _recoveryEmailController.text.trim();
        _recoveryCode = '';
        _recoveryCodeController.clear();
        _editingRecoveryEmail = true;
      });
    }
  }

  Future<void> _verifyRecoveryEmail() async {
    final verify = widget.onVerifyRecoveryEmail;
    if (verify == null || widget.busy || _recoveryCode.trim().length != 8) return;
    final verified = await verify(_recoveryCode.trim());
    if (mounted && verified) {
      setState(() {
        _recoveryCode = '';
        _recoveryCodeController.clear();
        _editingRecoveryEmail = false;
      });
    }
  }

  /// Signing out and deleting the account. The store this ships through
  /// requires the deletion path to be reachable from inside the app, and a
  /// player who wants off a shared phone needs the sign-out either way.
  Widget _accountSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Akkaunt', style: WBText.grotesk(size: 13.5, weight: FontWeight.w600)),
        const SizedBox(height: 11),
        _AccountButton(
          label: 'Chiqish',
          color: WBColors.textA(.75),
          border: WBColors.whiteA(.12),
          onTap: widget.busy ? null : widget.onLogout,
        ),
        const SizedBox(height: 9),
        if (!_confirmingDelete)
          _AccountButton(
            label: "Akkauntni o'chirish",
            color: WBColors.redSoft,
            border: WBColors.redA(.28),
            onTap: widget.busy ? null : () => setState(() => _confirmingDelete = true),
          )
        else
          Container(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
            decoration: BoxDecoration(
              color: WBColors.redA(.08),
              border: Border.all(color: WBColors.redA(.3)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "Akkaunt butunlay o'chiriladi: taxallus, do'stlar, reyting tarixi va "
                  "o'rganilgan so'zlar qaytarilmaydi. Tugagan janglar raqiblaringiz "
                  "tarixida nomsiz bo'lib qoladi.",
                  style: WBText.grotesk(size: 12, height: 1.45, color: WBColors.textA(.72)),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _AccountButton(
                        label: 'Bekor qilish',
                        color: WBColors.textA(.75),
                        border: WBColors.whiteA(.12),
                        onTap: widget.busy ? null : () => setState(() => _confirmingDelete = false),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: _AccountButton(
                        label: widget.busy ? "O'chirilmoqda…" : "Ha, o'chirish",
                        color: WBColors.redSoft,
                        border: WBColors.redA(.45),
                        fill: WBColors.redA(.14),
                        onTap: widget.busy ? null : widget.onDeleteAccount,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  static String _dayLabel(DateTime at) {
    const months = [
      'yanvar',
      'fevral',
      'mart',
      'aprel',
      'may',
      'iyun',
      'iyul',
      'avgust',
      'sentabr',
      'oktabr',
      'noyabr',
      'dekabr',
    ];
    return '${at.day} ${months[at.month - 1]}';
  }

  /// Each earned badge has its own mark — a diamond, a flame, a ring and a
  /// rounded square — not four identical dots. Locked ones are a dashed tile.
  Widget _badgeTile(BadgeDto badge) {
    if (!badge.unlocked) return _Badge(label: badge.label, locked: true);

    return switch (badge.code) {
      'first_battle' || 'rating_1500' => _Badge(
        label: badge.label,
        color: WBColors.accent,
        bg: WBColors.accentA(.13),
        border: WBColors.accentA(.34),
        mark: Transform.rotate(
          angle: math.pi / 4,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(color: WBColors.accent, borderRadius: BorderRadius.circular(4)),
          ),
        ),
      ),
      'streak_7' || 'streak_30' => _Badge(
        label: badge.label,
        color: WBColors.flameText,
        bg: WBColors.flameTop.withValues(alpha: .11),
        border: WBColors.flameTop.withValues(alpha: .3),
        mark: FlameIcon(width: 14, height: 19, animate: false),
      ),
      'wins_50' || 'friend_top' => _Badge(
        label: badge.label,
        color: WBColors.green,
        bg: WBColors.greenA(.1),
        border: WBColors.greenA(.28),
        mark: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: WBColors.green, width: 3),
          ),
        ),
      ),
      _ => _Badge(
        label: badge.label,
        color: WBColors.indigoText,
        bg: WBColors.indigoA(.1),
        border: WBColors.indigoA(.28),
        mark: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(color: WBColors.indigo, borderRadius: BorderRadius.circular(5)),
        ),
      ),
    };
  }
}

/// One segment of the appearance picker.
class _ThemeOption extends StatelessWidget {
  const _ThemeOption({required this.label, required this.mode});

  final String label;
  final WBThemeMode mode;

  @override
  Widget build(BuildContext context) {
    final active = WBTheme.mode == mode;
    return Expanded(
      child: Pressable(
        onTap: active ? null : () => WBTheme.select(mode),
        pressScale: .96,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 38,
          decoration: BoxDecoration(
            color: active ? WBColors.accentA(.16) : Colors.transparent,
            border: Border.all(color: active ? WBColors.accentA(.34) : Colors.transparent),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: WBText.grotesk(
              size: 13,
              weight: active ? FontWeight.w600 : FontWeight.w500,
              color: active ? WBColors.accent : WBColors.textA(.55),
            ),
          ),
        ),
      ),
    );
  }
}

/// One line of the privacy section: a label, and where the tap goes — a
/// chevron for a screen inside the app, an arrow out for a page the phone's
/// browser opens.
class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.label, required this.onTap, this.external = false});

  final String label;
  final VoidCallback onTap;
  final bool external;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      hoverColor: WBColors.whiteA(.06),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(child: Text(label, style: WBText.grotesk(size: 13.5, weight: FontWeight.w600))),
            const SizedBox(width: 10),
            if (external)
              Icon(Icons.open_in_new, size: 15, color: WBColors.textA(.4))
            else
              StrokeGlyph.chevronRight(size: 9, thickness: 2, color: WBColors.textA(.4)),
          ],
        ),
      ),
    );
  }
}

/// A flat, bordered row button — the account actions are deliberately quieter
/// than the accent-coloured calls to action everywhere else in the app.
class _AccountButton extends StatelessWidget {
  const _AccountButton({
    required this.label,
    required this.color,
    required this.border,
    required this.onTap,
    this.fill,
  });

  final String label;
  final Color color;
  final Color border;
  final Color? fill;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? .5 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: fill ?? WBColors.whiteA(.04),
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(15),
          ),
          alignment: Alignment.center,
          child: Text(label, style: WBText.grotesk(size: 13, weight: FontWeight.w600, color: color)),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.value, required this.label, this.color, this.tint = false});
  final String value;
  final String label;
  final Color? color;
  final bool tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: tint ? (color ?? WBColors.text).withValues(alpha: .08) : WBColors.whiteA(.045),
        border: Border.all(
          color: tint ? (color ?? WBColors.text).withValues(alpha: .24) : WBColors.whiteA(.09),
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: WBText.mono(size: 24, weight: FontWeight.w700, color: color ?? WBColors.text),
          ),
          const SizedBox(height: 3),
          Text(label, style: WBText.grotesk(size: 12, color: WBColors.textA(.5))),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    this.color,
    this.bg,
    this.border,
    this.mark,
    this.locked = false,
  });

  final String label;

  /// Null for a locked badge, which takes the palette's own muted foreground
  /// and hairline rather than a colour of its own.
  final Color? color;
  final Color? bg;
  final Color? border;
  final Widget? mark;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? WBColors.textA(.28);
    final bg = this.bg ?? WBColors.whiteA(.03);
    final border = this.border ?? WBColors.whiteA(.12);
    final content = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        mark ??
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: WBColors.textA(.2), width: 2),
              ),
            ),
        const SizedBox(height: 5),
        Text(
          label,
          style: WBText.grotesk(size: 9, weight: FontWeight.w500, color: color),
        ),
      ],
    );

    if (locked) {
      return CustomPaint(
        painter: DashedBorderPainter(color: border, radius: 17),
        child: Container(
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(17)),
          alignment: Alignment.center,
          child: content,
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: border),
      ),
      alignment: Alignment.center,
      child: content,
    );
  }
}

/// The 30-day rating line. Points are spread evenly across the width and
/// scaled to the min/max of the range, so a flat stretch stays readable instead
/// of collapsing onto the baseline.
class _RatingChartPainter extends CustomPainter {
  _RatingChartPainter(this.points);

  final List<RatingPoint> points;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final ratings = points.map((p) => p.rating).toList();
    final lowest = ratings.reduce((a, b) => a < b ? a : b);
    final highest = ratings.reduce((a, b) => a > b ? a : b);
    // A completely flat line would divide by zero; give it a nominal range.
    final span = (highest - lowest) == 0 ? 40.0 : (highest - lowest).toDouble();
    final top = 8.0;
    final bottom = size.height - 8;

    final scaled = <Offset>[];
    for (var i = 0; i < points.length; i++) {
      final x = size.width * (i / (points.length - 1));
      final normalised = (points[i].rating - lowest) / span;
      scaled.add(Offset(x, bottom - normalised * (bottom - top)));
    }

    final fillPath = Path()..moveTo(scaled.first.dx, scaled.first.dy);
    for (final p in scaled.skip(1)) {
      fillPath.lineTo(p.dx, p.dy);
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [WBColors.accentA(.34), WBColors.accentA(0)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    final linePath = Path()..moveTo(scaled.first.dx, scaled.first.dy);
    for (final p in scaled.skip(1)) {
      linePath.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color = WBColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    canvas.drawCircle(scaled.last, 4.5, Paint()..color = WBColors.accent);
  }

  @override
  bool shouldRepaint(covariant _RatingChartPainter oldDelegate) => oldDelegate.points != points;
}
