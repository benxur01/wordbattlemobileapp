import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_exception.dart';
import '../theme.dart';
import 'admin_api_client.dart';
import 'admin_models.dart';
import 'admin_widgets.dart';

/// Who did what to whom, and when.
///
/// The server writes a row here in the same transaction as the change it
/// describes, so this list is the whole record of what the panel has ever done —
/// which is also why nothing in it can be edited from here.
class AdminAuditScreen extends StatefulWidget {
  const AdminAuditScreen({
    super.key,
    required this.api,
    required this.onAuthFailure,
    required this.onOpenUser,
  });

  final AdminApiClient api;
  final void Function(ApiException error) onAuthFailure;
  final void Function(int userId) onOpenUser;

  @override
  State<AdminAuditScreen> createState() => _AdminAuditScreenState();
}

class _AdminAuditScreenState extends State<AdminAuditScreen> with AdminLoading {
  static const _pageSize = 50;

  AdminPage<AdminAuditEntry>? _page;

  @override
  void Function(ApiException error) get onAuthFailure => widget.onAuthFailure;

  @override
  void initState() {
    super.initState();
    unawaited(_load(0));
  }

  Future<void> _load(int page) => guard(() async {
        final loaded = await widget.api.auditLog(page: page, size: _pageSize);
        if (mounted) setState(() => _page = loaded);
      });

  Color _actionColor(String action) => switch (action) {
        'user_ban' => WBColors.red,
        'user_unban' => WBColors.green,
        _ => WBColors.amber,
      };

  @override
  Widget build(BuildContext context) {
    final page = _page;
    return Column(
      children: [
        AdminToolbar(title: 'Audit jurnali', busy: loading, onRefresh: () => _load(page?.page ?? 0)),
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

  Widget _body(AdminPage<AdminAuditEntry>? page) {
    if (page == null) {
      if (loading) return const Center(child: CircularProgressIndicator());
      if (error != null) return AdminErrorBox(message: error!, onRetry: () => _load(0));
      return const AdminEmpty(message: "Ma'lumot yo'q");
    }
    if (page.items.isEmpty) {
      return const AdminEmpty(message: 'Jurnal bo‘sh — panelda hali hech nima o‘zgartirilmagan');
    }

    return AdminTable(
      columns: const [
        AdminColumn('ID', 70),
        AdminColumn('Vaqt', 150),
        AdminColumn('Admin', 170),
        AdminColumn('Amal', 150),
        AdminColumn('Kimga', 170),
        AdminColumn('Tafsilot', 240),
      ],
      rows: [
        for (final entry in page.items)
          [
            adminCell('#${entry.id}', mono: true, color: WBColors.textA(.5)),
            adminCell(adminDate(entry.createdAt), mono: true, color: WBColors.textA(.7)),
            _account(entry.adminUserId, entry.adminLabel),
            adminCell(entry.actionLabel, weight: FontWeight.w600, color: _actionColor(entry.action)),
            _account(entry.targetUserId, entry.targetLabel),
            adminCell(entry.detail ?? '—', color: WBColors.textA(entry.detail == null ? .3 : .85)),
          ],
      ],
    );
  }

  Widget _account(int? id, String label) {
    final text = adminCell(label);
    if (id == null) return text;
    return InkWell(
      onTap: () => widget.onOpenUser(id),
      child: Tooltip(message: 'Akkauntni ochish (#$id)', child: text),
    );
  }
}
