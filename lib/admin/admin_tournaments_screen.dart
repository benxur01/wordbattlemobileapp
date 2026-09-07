import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_exception.dart';
import '../theme.dart';
import 'admin_api_client.dart';
import 'admin_models.dart';
import 'admin_widgets.dart';

/// Every tournament that has ever been created, and the button that makes a
/// new one. Opening a row is what leads to inviting players and starting it —
/// see `AdminTournamentDetailScreen`.
class AdminTournamentsScreen extends StatefulWidget {
  const AdminTournamentsScreen({
    super.key,
    required this.api,
    required this.onAuthFailure,
    required this.onOpenTournament,
  });

  final AdminApiClient api;
  final void Function(ApiException error) onAuthFailure;
  final void Function(int tournamentId) onOpenTournament;

  @override
  State<AdminTournamentsScreen> createState() => _AdminTournamentsScreenState();
}

class _AdminTournamentsScreenState extends State<AdminTournamentsScreen> with AdminLoading {
  static const _pageSize = 20;

  AdminPage<AdminTournamentRow>? _page;

  @override
  void Function(ApiException error) get onAuthFailure => widget.onAuthFailure;

  @override
  void initState() {
    super.initState();
    unawaited(_load(0));
  }

  Future<void> _load(int page) => guard(() async {
        final loaded = await widget.api.tournaments(page: page, size: _pageSize);
        if (mounted) setState(() => _page = loaded);
      });

  Future<void> _create() async {
    final result = await _askCreate(context);
    if (result == null) return;
    await guard(() async {
      final created = await widget.api.createTournament(result.name, result.size, result.format);
      await _load(0);
      if (mounted) widget.onOpenTournament(created.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    return Column(
      children: [
        AdminToolbar(
          title: 'Turnirlar',
          busy: loading,
          onRefresh: () => _load(page?.page ?? 0),
          trailing: [
            FilledButton.icon(
              onPressed: loading ? null : _create,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Yangi turnir'),
              style: FilledButton.styleFrom(backgroundColor: WBColors.amber, foregroundColor: WBColors.amberInk),
            ),
          ],
        ),
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

  Widget _body(AdminPage<AdminTournamentRow>? page) {
    if (page == null) {
      if (loading) return const Center(child: CircularProgressIndicator());
      if (error != null) return AdminErrorBox(message: error!, onRetry: () => _load(0));
      return const AdminEmpty(message: "Ma'lumot yo'q");
    }
    if (page.items.isEmpty) {
      return const AdminEmpty(message: "Hali birorta turnir yaratilmagan");
    }
    return AdminTable(
      columns: const [
        AdminColumn('ID', 60),
        AdminColumn('Nomi', 220),
        AdminColumn('Format', 100),
        AdminColumn("O'lcham", 80),
        AdminColumn('Holat', 110),
        AdminColumn('Yaratilgan', 140),
        AdminColumn('Boshlangan', 140),
      ],
      onRowTap: (index) => widget.onOpenTournament(page.items[index].id),
      rows: [
        for (final tournament in page.items)
          [
            adminCell('#${tournament.id}', mono: true, color: WBColors.textA(.5)),
            adminCell(tournament.name, weight: FontWeight.w600),
            adminCell(
              tournament.isTeam ? '2v2' : '1v1',
              mono: true,
              color: tournament.isTeam ? WBColors.purpleText : WBColors.textA(.6),
            ),
            adminCell('${tournament.size}', mono: true),
            adminCell(
              tournament.statusLabel,
              color: switch (tournament.status) {
                'in_progress' => WBColors.green,
                'completed' => WBColors.textA(.6),
                'cancelled' => WBColors.red,
                _ => WBColors.amber,
              },
            ),
            adminCell(adminDate(tournament.createdAt), mono: true, color: WBColors.textA(.6)),
            adminCell(adminDate(tournament.startedAt), mono: true, color: WBColors.textA(.6)),
          ],
      ],
    );
  }
}

/// Name, format and size. The format toggle is the panel's version of the
/// `OrganizeTournamentScreen` step a player picks between 1v1 and 2v2 in, and
/// decides what the size below it counts: players in a solo bracket, pairs in a
/// team one.
Future<({String name, int size, String format})?> _askCreate(BuildContext context) {
  final controller = TextEditingController();
  int size = 8;
  String format = 'solo';
  return showDialog<({String name, int size, String format})>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final name = controller.text.trim();
        final isTeam = format == 'team';
        return AlertDialog(
          backgroundColor: WBColors.bgPanel,
          title: Text('Yangi turnir', style: WBText.grotesk(size: 16, weight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                style: WBText.grotesk(size: 14),
                decoration: adminInput('Turnir nomi'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              Text('Format', style: WBText.grotesk(size: 12.5, color: WBColors.textA(.6))),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final option in const [(value: 'solo', label: 'Yakka · 1v1'), (value: 'team', label: 'Jamoaviy · 2v2')])
                    ChoiceChip(
                      label: Text(option.label),
                      selected: format == option.value,
                      onSelected: (_) => setState(() => format = option.value),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                isTeam ? 'Jamoalar soni' : 'Ishtirokchilar soni',
                style: WBText.grotesk(size: 12.5, color: WBColors.textA(.6)),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final option in const [4, 8, 16, 32])
                    ChoiceChip(
                      label: Text('$option'),
                      selected: size == option,
                      onSelected: (_) => setState(() => size = option),
                    ),
                ],
              ),
              if (isTeam) ...[
                const SizedBox(height: 8),
                Text(
                  "$size jamoa — ya'ni ${size * 2} o'yinchi, har bir o'rinda ikkitadan",
                  style: WBText.grotesk(size: 12, color: WBColors.textA(.45)),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Bekor qilish')),
            FilledButton(
              onPressed: name.isEmpty
                  ? null
                  : () => Navigator.of(context).pop((name: name, size: size, format: format)),
              style: FilledButton.styleFrom(backgroundColor: WBColors.amber, foregroundColor: WBColors.amberInk),
              child: const Text('Yaratish'),
            ),
          ],
        );
      },
    ),
  );
}
