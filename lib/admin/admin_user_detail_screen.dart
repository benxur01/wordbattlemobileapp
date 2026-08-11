import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_exception.dart';
import '../theme.dart';
import 'admin_api_client.dart';
import 'admin_models.dart';
import 'admin_user_actions.dart';
import 'admin_widgets.dart';

/// One account in full: who it is, how it has played, and whether it still has
/// its owner.
///
/// Reachable for a deleted shell too, because an admin looking into a complaint
/// about an account that has since been erased still has to be able to read the
/// row an old match points at.
class AdminUserDetailScreen extends StatefulWidget {
  const AdminUserDetailScreen({
    super.key,
    required this.api,
    required this.userId,
    required this.onAuthFailure,
    required this.onBack,
  });

  final AdminApiClient api;
  final int userId;
  final void Function(ApiException error) onAuthFailure;
  final VoidCallback onBack;

  @override
  State<AdminUserDetailScreen> createState() => _AdminUserDetailScreenState();
}

class _AdminUserDetailScreenState extends State<AdminUserDetailScreen> with AdminLoading {
  AdminUserDetail? _detail;
  String? _notice;

  @override
  void Function(ApiException error) get onAuthFailure => widget.onAuthFailure;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(AdminUserDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) unawaited(_load());
  }

  Future<void> _load() => guard(() async {
        final loaded = await widget.api.user(widget.userId);
        if (mounted) setState(() => _detail = loaded);
      });

  /// The action endpoints answer with the row alone, so the statistics around
  /// it are kept rather than blanked while a reload runs.
  void _replace(AdminUserRow updated) {
    final current = _detail;
    if (current == null || !mounted) return;
    setState(() {
      _detail = AdminUserDetail(
        user: updated,
        globalRank: current.globalRank,
        winPercent: current.winPercent,
        longestChain: current.longestChain,
        wordsLearned: current.wordsLearned,
        streakDays: current.streakDays,
        lastPlayedOn: current.lastPlayedOn,
      );
    });
  }

  Future<void> _ban(AdminUserRow user) async {
    final reason = await askBanReason(context, user);
    if (reason == null) return;
    await guard(() async {
      _replace(await widget.api.ban(user.id, reason: reason));
      if (mounted) setState(() => _notice = 'Akkaunt bloklandi');
    });
  }

  Future<void> _unban(AdminUserRow user) async {
    if (!await askUnban(context, user)) return;
    await guard(() async {
      _replace(await widget.api.unban(user.id));
      if (mounted) setState(() => _notice = 'Blok olindi');
    });
  }

  Future<void> _rename(AdminUserRow user) async {
    final nickname = await askNickname(context, user);
    if (nickname == null) return;
    await guard(() async {
      final updated = await widget.api.rename(user.id, nickname);
      _replace(updated);
      if (mounted) setState(() => _notice = 'Yangi taxallus: ${updated.nickname}');
    });
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminToolbar(
          title: 'Akkaunt #${widget.userId}',
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

  Widget _body(AdminUserDetail? detail) {
    if (detail == null) {
      if (loading) return const Center(child: CircularProgressIndicator());
      if (error != null) return AdminErrorBox(message: error!, onRetry: _load);
      return const AdminEmpty(message: 'Foydalanuvchi topilmadi');
    }

    final user = detail.user;
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
              Text(user.label, style: WBText.grotesk(size: 22, weight: FontWeight.w700)),
              ...adminUserTags(user),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            user.city == null ? 'Shahar ko‘rsatilmagan' : user.city!,
            style: WBText.grotesk(size: 13, color: WBColors.textA(.5)),
          ),
          const SizedBox(height: 16),
          if (!user.deleted) _actions(user),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _stat('Reyting', '${user.rating}'),
              _stat('Global o‘rin', detail.globalRank == 0 ? '—' : '#${detail.globalRank}'),
              _stat('Janglar', '${user.battles}'),
              _stat('G‘alabalar', '${user.wins}'),
              _stat('G‘alaba %', '${detail.winPercent}%'),
              _stat('Eng uzun zanjir', '${detail.longestChain}'),
              _stat('O‘rganilgan so‘zlar', '${detail.wordsLearned}'),
              _stat('Streak', '${detail.streakDays} kun'),
            ],
          ),
          const SizedBox(height: 20),
          Text('Vaqtlar', style: WBText.grotesk(size: 14, weight: FontWeight.w600, color: WBColors.textA(.7))),
          const SizedBox(height: 8),
          _line('Taxallus', user.nickname ?? '—'),
          _line('Google ismi', user.displayName ?? '—'),
          _line('Yaratilgan', adminDate(user.createdAt)),
          _line('Oxirgi faollik', adminDate(user.lastSeenAt)),
          _line('Oxirgi o‘yin kuni', adminDate(detail.lastPlayedOn, withTime: false)),
          _line('Bloklangan', user.banned ? adminDate(user.bannedAt) : '—'),
        ],
      ),
    );
  }

  Widget _actions(AdminUserRow user) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (user.banned)
            FilledButton.icon(
              onPressed: loading ? null : () => _unban(user),
              icon: const Icon(Icons.lock_open, size: 16),
              label: const Text('Blokni olish'),
              style: FilledButton.styleFrom(backgroundColor: WBColors.green, foregroundColor: WBColors.greenInk),
            )
          else
            FilledButton.icon(
              onPressed: loading ? null : () => _ban(user),
              icon: const Icon(Icons.block, size: 16),
              label: const Text('Bloklash'),
              style: FilledButton.styleFrom(backgroundColor: WBColors.red, foregroundColor: WBColors.text),
            ),
          OutlinedButton.icon(
            onPressed: loading ? null : () => _rename(user),
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text("Taxallusni o'zgartirish"),
          ),
        ],
      );

  Widget _stat(String label, String value) => Container(
        width: 160,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: WBColors.cardFill,
          border: Border.all(color: WBColors.cardBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(),
                style: WBText.mono(size: 10, weight: FontWeight.w600, color: WBColors.textA(.45), letterSpacing: .08)),
            const SizedBox(height: 4),
            Text(value, style: WBText.grotesk(size: 20, weight: FontWeight.w700)),
          ],
        ),
      );

  Widget _line(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 160,
              child: Text(label, style: WBText.grotesk(size: 13, color: WBColors.textA(.5))),
            ),
            Expanded(child: Text(value, style: WBText.mono(size: 13, color: WBColors.textA(.9)))),
          ],
        ),
      );
}
