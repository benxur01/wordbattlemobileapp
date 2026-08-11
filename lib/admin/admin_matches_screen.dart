import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_exception.dart';
import '../theme.dart';
import 'admin_api_client.dart';
import 'admin_models.dart';
import 'admin_widgets.dart';

/// Every duel on the server, newest first, bound to no account — which is the
/// whole difference between this and the history a player sees.
class AdminMatchesScreen extends StatefulWidget {
  const AdminMatchesScreen({
    super.key,
    required this.api,
    required this.onAuthFailure,
    required this.onOpenUser,
  });

  final AdminApiClient api;
  final void Function(ApiException error) onAuthFailure;
  final void Function(int userId) onOpenUser;

  @override
  State<AdminMatchesScreen> createState() => _AdminMatchesScreenState();
}

class _AdminMatchesScreenState extends State<AdminMatchesScreen> with AdminLoading {
  static const _pageSize = 20;

  AdminPage<AdminMatchRow>? _page;

  @override
  void Function(ApiException error) get onAuthFailure => widget.onAuthFailure;

  @override
  void initState() {
    super.initState();
    unawaited(_load(0));
  }

  Future<void> _load(int page) => guard(() async {
        final loaded = await widget.api.matches(page: page, size: _pageSize);
        if (mounted) setState(() => _page = loaded);
      });

  /// The four ways a duel can end, as `MatchEntity.EndReason` names them.
  String _reason(String code) => switch (code) {
        'timeout' => 'Vaqt tugadi',
        'no_moves' => 'Yurish qolmadi',
        'forfeit' => 'Taslim / uzilish',
        'words_limit' => 'So‘z limiti',
        _ => code,
      };

  @override
  Widget build(BuildContext context) {
    final page = _page;
    return Column(
      children: [
        AdminToolbar(title: 'Janglar', busy: loading, onRefresh: () => _load(page?.page ?? 0)),
        if (error != null && page != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: AdminBanner(message: error!, onDismiss: () => setState(() => error = null)),
          ),
        Expanded(child: _body(page)),
        AdminPager(page: page, busy: loading, onPage: _load),
      ],
    );
  }

  Widget _body(AdminPage<AdminMatchRow>? page) {
    if (page == null) {
      if (loading) return const Center(child: CircularProgressIndicator());
      if (error != null) return AdminErrorBox(message: error!, onRetry: () => _load(0));
      return const AdminEmpty(message: "Ma'lumot yo'q");
    }
    if (page.items.isEmpty) return const AdminEmpty(message: 'Hali hech qanday jang yo‘q');

    return AdminTable(
      columns: const [
        AdminColumn('ID', 70),
        AdminColumn('1-o‘yinchi', 170),
        AdminColumn('2-o‘yinchi', 170),
        AdminColumn('G‘olib', 150),
        AdminColumn('Tugash sababi', 150),
        AdminColumn('Zanjir', 80),
        AdminColumn('Boshlandi', 150),
        AdminColumn('Tugadi', 150),
      ],
      rows: [
        for (final match in page.items)
          [
            adminCell('#${match.id}', mono: true, color: WBColors.textA(.5)),
            _player(match.playerOneId, match.playerOneLabel, winner: match.winnerId == match.playerOneId),
            match.botOpponent
                ? adminCell('BOT', mono: true, color: WBColors.purpleText)
                : _player(match.playerTwoId, match.playerTwoLabel, winner: match.winnerId == match.playerTwoId),
            adminCell(
              match.winnerId == null ? '—' : '#${match.winnerId}',
              mono: true,
              color: match.winnerId == null ? WBColors.textA(.4) : WBColors.green,
            ),
            adminCell(_reason(match.endReason)),
            adminCell('${match.chainLength}', mono: true),
            adminCell(adminDate(match.startedAt), mono: true, color: WBColors.textA(.6)),
            adminCell(adminDate(match.finishedAt), mono: true, color: WBColors.textA(.6)),
          ],
      ],
    );
  }

  /// A player's name is a way into their account, since a duel is usually what
  /// an admin is looking at when they need one.
  Widget _player(int? id, String label, {required bool winner}) {
    final text = adminCell(
      label,
      weight: winner ? FontWeight.w700 : FontWeight.w400,
      color: winner ? WBColors.green : null,
    );
    if (id == null) return text;
    return InkWell(
      onTap: () => widget.onOpenUser(id),
      child: Tooltip(message: 'Akkauntni ochish (#$id)', child: text),
    );
  }
}
