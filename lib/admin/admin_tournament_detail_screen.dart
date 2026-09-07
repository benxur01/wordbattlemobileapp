import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_exception.dart';
import '../api/models.dart';
import '../theme.dart';
import 'admin_api_client.dart';
import 'admin_models.dart';
import 'admin_widgets.dart';

/// One tournament: its bracket format, who has been invited and how they
/// answered, the search box that invites more, and the button that seeds the
/// bracket once enough of them have accepted.
///
/// A team tournament seats a pair where a solo one seats a player, and that is
/// the whole of the difference here: the search box invites two people at a
/// time rather than one, and every seat is drawn as the two names that hold it.
class AdminTournamentDetailScreen extends StatefulWidget {
  const AdminTournamentDetailScreen({
    super.key,
    required this.api,
    required this.tournamentId,
    required this.onAuthFailure,
    required this.onBack,
  });

  final AdminApiClient api;
  final int tournamentId;
  final void Function(ApiException error) onAuthFailure;
  final VoidCallback onBack;

  @override
  State<AdminTournamentDetailScreen> createState() => _AdminTournamentDetailScreenState();
}

class _AdminTournamentDetailScreenState extends State<AdminTournamentDetailScreen> with AdminLoading {
  AdminTournamentDetail? _detail;
  String? _notice;

  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  List<UserDto> _searchResults = const [];
  final Set<int> _invitedThisSession = {};

  /// The first half of a team being put together, waiting for the tap that
  /// gives them a partner and sends the invite — the same two-tap pairing
  /// `OrganizeTournamentScreen` builds its 2v2 teams with. Null on a solo
  /// tournament, where one tap is the whole invite.
  UserDto? _pendingPartner;

  @override
  void Function(ApiException error) get onAuthFailure => widget.onAuthFailure;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(AdminTournamentDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tournamentId != widget.tournamentId) unawaited(_load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() => guard(() async {
        final loaded = await widget.api.tournament(widget.tournamentId);
        if (mounted) setState(() => _detail = loaded);
      });

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() => _searchResults = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final results = await widget.api.searchUsers(value.trim());
        if (mounted) setState(() => _searchResults = results);
      } on ApiException catch (e) {
        if (!mounted) return;
        setState(() => _searchResults = const []);
        if (e.isUnauthorized || e.isRoleRefusal) widget.onAuthFailure(e);
      }
    });
  }

  Future<void> _invite(UserDto user) async {
    setState(() => _invitedThisSession.add(user.id));
    await guard(() async {
      await widget.api.inviteToTournament(widget.tournamentId, user.id);
      await _load();
      if (mounted) setState(() => _notice = '${user.label} taklif qilindi');
    });
  }

  /// One tap names the first half of a seat; the next one closes the pair and
  /// invites both. Tapping the waiting player again lets them go.
  Future<void> _pick(UserDto user) async {
    final waiting = _pendingPartner;
    if (waiting == null || waiting.id == user.id) {
      setState(() => _pendingPartner = waiting == null ? user : null);
      return;
    }
    setState(() {
      _pendingPartner = null;
      _invitedThisSession.addAll([waiting.id, user.id]);
    });
    await guard(() async {
      await widget.api.inviteTeamToTournament(widget.tournamentId, waiting.id, user.id);
      await _load();
      if (mounted) setState(() => _notice = '${waiting.label} + ${user.label} taklif qilindi');
    });
  }

  Future<void> _start() async {
    final confirmed = await adminConfirm(
      context,
      title: 'Turnirni boshlash',
      message: "Bracket hozir qabul qilgan o'yinchilar reytingi bo'yicha tuziladi va buni ortga qaytarib bo'lmaydi. "
          'Davom etilsinmi?',
      confirmLabel: 'Boshlash',
      destructive: false,
    );
    if (!confirmed) return;
    await guard(() async {
      await widget.api.startTournament(widget.tournamentId);
      await _load();
      if (mounted) setState(() => _notice = 'Turnir boshlandi');
    });
  }

  Future<void> _cancel() async {
    final confirmed = await adminConfirm(
      context,
      title: 'Turnirni bekor qilish',
      message: "Turnir butunlay bekor qilinadi va buni ortga qaytarib bo'lmaydi. Barcha qatnashchilarga xabar beriladi. "
          'Davom etilsinmi?',
      confirmLabel: 'Bekor qilish',
      destructive: true,
    );
    if (!confirmed) return;
    await guard(() async {
      await widget.api.cancelTournament(widget.tournamentId);
      await _load();
      if (mounted) setState(() => _notice = 'Turnir bekor qilindi');
    });
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminToolbar(
          title: detail == null ? 'Turnir #${widget.tournamentId}' : detail.tournament.name,
          busy: loading,
          onRefresh: _load,
          trailing: [
            TextButton.icon(
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text("Ro'yxatga qaytish"),
            ),
          ],
        ),
        if (_notice != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: AdminBanner(
              message: _notice!,
              tone: AdminTone.good,
              onDismiss: () => setState(() => _notice = null),
            ),
          ),
        if (error != null && detail != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: AdminBanner(message: error!, onDismiss: () => setState(() => error = null)),
          ),
        Expanded(child: _body(detail)),
      ],
    );
  }

  Widget _body(AdminTournamentDetail? detail) {
    if (detail == null) {
      if (loading) return const Center(child: CircularProgressIndicator());
      if (error != null) return AdminErrorBox(message: error!, onRetry: _load);
      return const AdminEmpty(message: 'Turnir topilmadi');
    }

    final tournament = detail.tournament;
    final isTeam = tournament.isTeam;
    final accepted = detail.participants.where((p) => p.fullyAccepted).length;
    final isOpen = tournament.status == 'open';
    final cancellable = tournament.status == 'open' || tournament.status == 'in_progress';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(
                isTeam
                    ? "${tournament.size} jamoa · ${tournament.size * 2} o'yinchi · yagona eliminatsiya"
                    : "${tournament.size} o'yinchi · yagona eliminatsiya",
                style: WBText.grotesk(size: 14, color: WBColors.textA(.6)),
              ),
              AdminTag(
                label: isTeam ? 'JAMOAVIY · 2V2' : 'YAKKA · 1V1',
                color: isTeam ? WBColors.purpleText : WBColors.textA(.6),
              ),
              AdminTag(
                label: tournament.statusLabel.toUpperCase(),
                color: switch (tournament.status) {
                  'in_progress' => WBColors.green,
                  'completed' => WBColors.textA(.6),
                  'cancelled' => WBColors.red,
                  _ => WBColors.amber,
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (cancellable) ...[
            OutlinedButton.icon(
              onPressed: loading ? null : _cancel,
              icon: const Icon(Icons.cancel_outlined, size: 18),
              label: const Text('Bekor qilish'),
              style: OutlinedButton.styleFrom(foregroundColor: WBColors.red, side: BorderSide(color: WBColors.red)),
            ),
            const SizedBox(height: 16),
          ],
          if (isOpen) ...[
            Text(
              isTeam
                  ? '$accepted / ${tournament.size} jamoa to\'liq qabul qildi'
                  : '$accepted / ${tournament.size} qabul qildi',
              style: WBText.grotesk(size: 13, color: WBColors.textA(.7)),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: !loading && accepted == tournament.size ? _start : null,
              icon: const Icon(Icons.play_arrow, size: 18),
              label: const Text('Turnirni boshlash'),
              style: FilledButton.styleFrom(backgroundColor: WBColors.green, foregroundColor: WBColors.greenInk),
            ),
            const SizedBox(height: 20),
            Text(
              isTeam ? 'Jamoa tuzish va taklif qilish' : "O'yinchi qidirish va taklif qilish",
              style: WBText.grotesk(size: 14, weight: FontWeight.w600),
            ),
            if (isTeam) ...[
              const SizedBox(height: 4),
              Text(
                _pendingPartner == null
                    ? "Har bir o'rin uchun ikki o'yinchini ketma-ket tanlang"
                    : "${_pendingPartner!.label} kim bilan o'ynaydi?",
                style: WBText.grotesk(size: 12.5, color: WBColors.textA(.55)),
              ),
            ],
            const SizedBox(height: 8),
            SizedBox(
              width: 340,
              child: TextField(
                controller: _search,
                style: WBText.grotesk(size: 13),
                decoration: adminInput('Taxallus bo\'yicha qidirish', prefix: Icon(Icons.search, size: 18, color: WBColors.textA(.4))),
                onChanged: _onSearchChanged,
              ),
            ),
            if (_searchResults.isNotEmpty) ...[
              const SizedBox(height: 8),
              ..._searchResults.map((user) => _searchRow(user, isTeam)),
            ],
            const SizedBox(height: 20),
          ],
          Text(isTeam ? 'Jamoalar' : 'Qatnashchilar', style: WBText.grotesk(size: 14, weight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (detail.participants.isEmpty)
            Text(
              isTeam ? "Hali birorta jamoa taklif qilinmagan" : "Hali hech kim taklif qilinmagan",
              style: WBText.grotesk(size: 13, color: WBColors.textA(.5)),
            )
          else
            _participantsTable(detail.participants, isTeam),
          if (!isOpen) ...[
            const SizedBox(height: 24),
            Text('Bracket', style: WBText.grotesk(size: 14, weight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (detail.matches.isEmpty)
              Text("Ma'lumot yo'q", style: WBText.grotesk(size: 13, color: WBColors.textA(.5)))
            else
              _bracketTable(detail.matches, isTeam),
          ],
        ],
      ),
    );
  }

  Widget _searchRow(UserDto user, bool isTeam) {
    final invited = _invitedThisSession.contains(user.id);
    final pending = _pendingPartner?.id == user.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(width: 220, child: Text(user.label, style: WBText.grotesk(size: 13, weight: FontWeight.w500))),
          SizedBox(width: 80, child: Text('${user.rating}', style: WBText.mono(size: 12, color: WBColors.textA(.6)))),
          const SizedBox(width: 12),
          if (invited)
            Text('Yuborildi', style: WBText.grotesk(size: 12.5, color: WBColors.textA(.5)))
          else if (!isTeam)
            OutlinedButton(onPressed: loading ? null : () => _invite(user), child: const Text('Taklif qilish'))
          else
            OutlinedButton(
              onPressed: loading ? null : () => _pick(user),
              child: Text(pending
                  ? 'Bekor qilish'
                  : _pendingPartner == null
                      ? 'Tanlash'
                      : 'Juftlashtirish'),
            ),
        ],
      ),
    );
  }

  Widget _participantsTable(List<AdminTournamentParticipantRow> participants, bool isTeam) {
    return AdminTable(
      columns: [
        const AdminColumn('Urug\'', 60),
        const AdminColumn('ID', 70),
        AdminColumn(isTeam ? 'Jamoa' : 'Foydalanuvchi', 220),
        const AdminColumn('Holat', 160),
      ],
      rowHeight: isTeam ? 56 : 40,
      rows: [
        for (final p in participants)
          [
            adminCell(p.seed == null ? '—' : '#${p.seed}', mono: true, color: WBColors.textA(.6)),
            _pairCell('#${p.userId}', p.partnerUserId == null ? null : '#${p.partnerUserId}',
                mono: true, color: WBColors.textA(.5)),
            _pairCell(p.label, p.partnerLabel, weight: FontWeight.w600),
            _stackedCell(
              adminCell(p.statusLabel, color: _answerColor(p.status)),
              p.partnerStatusLabel == null
                  ? null
                  : adminCell(p.partnerStatusLabel!, color: _answerColor(p.partnerStatus!)),
            ),
          ],
      ],
    );
  }

  static Color _answerColor(String status) => switch (status) {
        'accepted' => WBColors.green,
        'declined' => WBColors.red,
        _ => WBColors.textA(.6),
      };

  Widget _bracketTable(List<AdminTournamentMatchRow> matches, bool isTeam) {
    return AdminTable(
      columns: [
        const AdminColumn('Bosqich', 90),
        const AdminColumn('#', 40),
        AdminColumn(isTeam ? '1-jamoa' : '1-o\'yinchi', 180),
        AdminColumn(isTeam ? '2-jamoa' : '2-o\'yinchi', 180),
        const AdminColumn('G\'olib', 180),
        const AdminColumn('Holat', 100),
      ],
      rowHeight: isTeam ? 56 : 40,
      rows: [
        for (final match in matches)
          [
            adminCell('${match.round}-bosqich', mono: true, color: WBColors.textA(.6)),
            adminCell('${match.slot + 1}', mono: true, color: WBColors.textA(.5)),
            _pairCell(match.playerOneLabel, match.playerOnePartnerLabel),
            _pairCell(match.playerTwoLabel, match.playerTwoPartnerLabel),
            _pairCell(
              match.winnerLabel ?? '—',
              match.winnerPartnerLabel,
              weight: FontWeight.w600,
              color: match.winnerLabel == null ? null : WBColors.green,
            ),
            adminCell(
              match.statusLabel,
              color: switch (match.status) {
                'live' => WBColors.green,
                'done' => WBColors.textA(.6),
                _ => WBColors.amber,
              },
            ),
          ],
      ],
    );
  }

  /// A team's two members on their own lines — the same "name over + name" the
  /// player-facing bracket stacks a 2v2 seat into. Falls back to the plain
  /// one-line cell wherever there is no second member, which is everywhere in a
  /// solo tournament.
  Widget _pairCell(String primary, String? partner,
      {bool mono = false, Color? color, FontWeight weight = FontWeight.w400}) {
    final top = adminCell(primary, mono: mono, color: color, weight: weight);
    if (partner == null) return top;
    return _stackedCell(top, adminCell('+ $partner', mono: mono, color: color, weight: weight));
  }

  Widget _stackedCell(Widget top, Widget? bottom) {
    if (bottom == null) return top;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [top, const SizedBox(height: 2), bottom],
    );
  }
}
