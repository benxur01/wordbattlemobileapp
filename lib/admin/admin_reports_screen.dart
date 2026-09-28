import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_exception.dart';
import '../theme.dart';
import 'admin_api_client.dart';
import 'admin_models.dart';
import 'admin_widgets.dart';

/// What players have reported about each other and nobody has dealt with yet.
///
/// The panel's side of the in-app "Shikoyat qilish": a report says who, about
/// whom, why and where, and closing one is all this screen does to it. Acting
/// on the account — a ban, a rename — happens on that account's own screen, one
/// tap away from either name.
class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({
    super.key,
    required this.api,
    required this.onAuthFailure,
    required this.onOpenUser,
  });

  final AdminApiClient api;
  final void Function(ApiException error) onAuthFailure;
  final void Function(int userId) onOpenUser;

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> with AdminLoading {
  static const _pageSize = 20;

  AdminPage<AdminReportRow>? _page;
  String? _notice;

  @override
  void Function(ApiException error) get onAuthFailure => widget.onAuthFailure;

  @override
  void initState() {
    super.initState();
    unawaited(_load(0));
  }

  Future<void> _load(int page) => guard(() async {
        final loaded = await widget.api.reports(page: page, size: _pageSize);
        if (mounted) setState(() => _page = loaded);
      });

  /// Closes the report and reloads the page it was on, which it has now left:
  /// the list is a queue, so a closed report moving out from under the cursor
  /// is the point rather than a nuisance.
  Future<void> _resolve(AdminReportRow report) async {
    final confirmed = await adminConfirm(
      context,
      title: 'Shikoyatni yopish',
      message: '#${report.id}: ${report.reporterLabel} → ${report.reportedLabel} (${report.reasonLabel}).\n\n'
          'Yopilgan shikoyat navbatdan chiqadi va audit jurnaliga yoziladi. Akkauntga chora kerak '
          'bo‘lsa — bloklash yoki taxallusni o‘zgartirish — uni nomi ustiga bosib oching.',
      confirmLabel: 'Yopish',
      destructive: false,
    );
    if (!confirmed) return;
    await guard(() async {
      await widget.api.resolveReport(report.id);
      final reloaded = await widget.api.reports(page: _page?.page ?? 0, size: _pageSize);
      if (!mounted) return;
      setState(() {
        _page = reloaded;
        _notice = 'Shikoyat #${report.id} yopildi';
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    return Column(
      children: [
        AdminToolbar(title: 'Shikoyatlar', busy: loading, onRefresh: () => _load(page?.page ?? 0)),
        if (_notice != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: AdminBanner(
              message: _notice!,
              tone: AdminTone.good,
              onDismiss: () => setState(() => _notice = null),
            ),
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

  Widget _body(AdminPage<AdminReportRow>? page) {
    if (page == null) {
      if (loading) return const Center(child: CircularProgressIndicator());
      if (error != null) return AdminErrorBox(message: error!, onRetry: () => _load(0));
      return const AdminEmpty(message: "Ma'lumot yo'q");
    }
    if (page.items.isEmpty) return const AdminEmpty(message: 'Ochiq shikoyat yo‘q');

    return AdminTable(
      columns: const [
        AdminColumn('ID', 70),
        AdminColumn('Vaqt', 150),
        AdminColumn('Kimdan', 160),
        AdminColumn('Kim haqida', 160),
        AdminColumn('Sabab', 150),
        AdminColumn('Joy', 90),
        AdminColumn('Tafsilot', 300),
        AdminColumn('Amal', 120),
      ],
      rows: [
        for (final report in page.items)
          [
            adminCell('#${report.id}', mono: true, color: WBColors.textA(.5)),
            adminCell(adminDate(report.createdAt), mono: true, color: WBColors.textA(.7)),
            _account(report.reporterId, report.reporterLabel),
            _account(report.reportedId, report.reportedLabel, weight: FontWeight.w600),
            adminCell(report.reasonLabel, weight: FontWeight.w600, color: WBColors.amber),
            adminCell(report.contextLabel, color: WBColors.textA(.7)),
            _details(report.details),
            TextButton.icon(
              onPressed: loading ? null : () => _resolve(report),
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Yopish'),
            ),
          ],
      ],
    );
  }

  /// A name is a way into the account — the reported one above all, since
  /// that is where a ban or a rename is made.
  Widget _account(int? id, String label, {FontWeight weight = FontWeight.w400}) {
    final text = adminCell(label, weight: weight);
    if (id == null) return text;
    return InkWell(
      onTap: () => widget.onOpenUser(id),
      child: Tooltip(message: 'Akkauntni ochish (#$id)', child: text),
    );
  }

  /// One line in the table, the whole text on hover: a report's details are
  /// often the only record of what was said, since duel chat is never stored.
  Widget _details(String? details) {
    if (details == null) return adminCell('—', color: WBColors.textA(.3));
    return Tooltip(message: details, child: adminCell(details));
  }
}
