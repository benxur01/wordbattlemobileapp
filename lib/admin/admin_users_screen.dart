import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_exception.dart';
import '../theme.dart';
import 'admin_api_client.dart';
import 'admin_models.dart';
import 'admin_user_actions.dart';
import 'admin_widgets.dart';

/// The accounts, and the three things that can be done to one.
///
/// Deleted shells and banned accounts are in this list, unlike everywhere else
/// in the app: they are what an admin comes to this screen looking for, and the
/// server returns them here on purpose.
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({
    super.key,
    required this.api,
    required this.onAuthFailure,
    required this.onOpenUser,
  });

  final AdminApiClient api;
  final void Function(ApiException error) onAuthFailure;
  final void Function(int userId) onOpenUser;

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> with AdminLoading {
  static const _pageSize = 20;

  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  AdminPage<AdminUserRow>? _page;
  String _query = '';
  String? _notice;

  @override
  void Function(ApiException error) get onAuthFailure => widget.onAuthFailure;

  @override
  void initState() {
    super.initState();
    unawaited(_load(0));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load(int page) => guard(() async {
        final loaded = await widget.api.users(query: _query, page: page, size: _pageSize);
        if (mounted) setState(() => _page = loaded);
      });

  /// Typing is not a search. Waiting out the pause means one request for a
  /// nickname rather than one per letter of it.
  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => _query = value);
      unawaited(_load(0));
    });
  }

  /// The row as the server now has it, put back where it was. Reloading the
  /// whole page instead would move rows under the cursor mid-action.
  void _replace(AdminUserRow updated) {
    final current = _page;
    if (current == null || !mounted) return;
    setState(() {
      _page = AdminPage(
        items: [for (final user in current.items) user.id == updated.id ? updated : user],
        page: current.page,
        size: current.size,
        total: current.total,
        totalPages: current.totalPages,
      );
    });
  }

  Future<void> _ban(AdminUserRow user) async {
    final reason = await askBanReason(context, user);
    if (reason == null) return;
    await guard(() async {
      final updated = await widget.api.ban(user.id, reason: reason);
      _replace(updated);
      if (mounted) setState(() => _notice = '${updated.label} bloklandi');
    });
  }

  Future<void> _unban(AdminUserRow user) async {
    if (!await askUnban(context, user)) return;
    await guard(() async {
      final updated = await widget.api.unban(user.id);
      _replace(updated);
      if (mounted) setState(() => _notice = '${updated.label} blokdan chiqarildi');
    });
  }

  Future<void> _rename(AdminUserRow user) async {
    final nickname = await askNickname(context, user);
    if (nickname == null) return;
    await guard(() async {
      final updated = await widget.api.rename(user.id, nickname);
      _replace(updated);
      if (mounted) setState(() => _notice = "Yangi taxallus: ${updated.nickname}");
    });
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    return Column(
      children: [
        AdminToolbar(
          title: 'Foydalanuvchilar',
          busy: loading,
          onRefresh: () => _load(page?.page ?? 0),
          trailing: [
            SizedBox(
              width: 280,
              child: TextField(
                controller: _search,
                style: WBText.grotesk(size: 13),
                decoration: adminInput(
                  'Taxallus, ism yoki ID',
                  prefix: Icon(Icons.search, size: 18, color: WBColors.textA(.4)),
                ),
                onChanged: _onSearchChanged,
              ),
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
        // A banner only while there is still a table worth keeping under it.
        // With nothing loaded the failure takes the whole body instead, so it
        // is never said twice at once.
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

  Widget _body(AdminPage<AdminUserRow>? page) {
    if (page == null) {
      if (loading) return const Center(child: CircularProgressIndicator());
      if (error != null) return AdminErrorBox(message: error!, onRetry: () => _load(0));
      return const AdminEmpty(message: "Ma'lumot yo'q");
    }
    if (page.items.isEmpty) {
      return AdminEmpty(message: _query.isEmpty ? "Hech qanday akkaunt yo'q" : "'$_query' bo'yicha hech nima topilmadi");
    }
    return AdminTable(
      columns: const [
        AdminColumn('ID', 70),
        AdminColumn('Taxallus', 170),
        AdminColumn('Ism', 150),
        AdminColumn('Reyting', 80),
        AdminColumn('Jang / G\'alaba', 110),
        AdminColumn('Holat', 190),
        AdminColumn('Yaratilgan', 140),
        AdminColumn('Amallar', 160),
      ],
      onRowTap: (index) => widget.onOpenUser(page.items[index].id),
      rows: [
        for (final user in page.items)
          [
            adminCell('#${user.id}', mono: true, color: WBColors.textA(.5)),
            adminCell(
              user.nickname ?? '—',
              weight: FontWeight.w600,
              color: user.banned ? WBColors.redSoft : null,
            ),
            adminCell(user.displayName ?? '—'),
            adminCell('${user.rating}', mono: true),
            adminCell('${user.battles} / ${user.wins}', mono: true),
            _state(user),
            adminCell(adminDate(user.createdAt, withTime: false), mono: true, color: WBColors.textA(.6)),
            _actions(user),
          ],
      ],
    );
  }

  /// The tags a row carries, or the word for carrying none.
  Widget _state(AdminUserRow user) {
    final tags = adminUserTags(user);
    if (tags.isEmpty) return adminCell('faol', color: WBColors.textA(.45));
    return Row(children: tags);
  }

  Widget _actions(AdminUserRow user) {
    // A deleted shell has no player behind it to ban or to rename; the row is
    // kept only so an old match still has a name to point at.
    if (user.deleted) return adminCell('—', color: WBColors.textA(.3));
    return Row(
      children: [
        _iconAction(
          icon: user.banned ? Icons.lock_open : Icons.block,
          tooltip: user.banned ? 'Blokni olish' : 'Bloklash',
          color: user.banned ? WBColors.green : WBColors.red,
          onPressed: loading ? null : () => user.banned ? _unban(user) : _ban(user),
        ),
        _iconAction(
          icon: Icons.edit_outlined,
          tooltip: "Taxallusni o'zgartirish",
          color: WBColors.amber,
          onPressed: loading ? null : () => _rename(user),
        ),
        _iconAction(
          icon: Icons.open_in_new,
          tooltip: 'Batafsil',
          color: WBColors.textA(.6),
          onPressed: () => widget.onOpenUser(user.id),
        ),
      ],
    );
  }

  Widget _iconAction({
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback? onPressed,
  }) =>
      IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        color: color,
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
        padding: EdgeInsets.zero,
      );
}
