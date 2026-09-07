import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_exception.dart';
import '../theme.dart';
import 'admin_api_client.dart';
import 'admin_models.dart';
import 'admin_widgets.dart';

/// The panel's front page: the handful of numbers that say what kind of day the
/// server is having.
class AdminMetricsScreen extends StatefulWidget {
  const AdminMetricsScreen({super.key, required this.api, required this.onAuthFailure});

  final AdminApiClient api;
  final void Function(ApiException error) onAuthFailure;

  @override
  State<AdminMetricsScreen> createState() => _AdminMetricsScreenState();
}

class _AdminMetricsScreenState extends State<AdminMetricsScreen> with AdminLoading {
  AdminMetrics? _metrics;

  @override
  void Function(ApiException error) get onAuthFailure => widget.onAuthFailure;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() => guard(() async {
        final loaded = await widget.api.metrics();
        if (mounted) setState(() => _metrics = loaded);
      });

  @override
  Widget build(BuildContext context) {
    final metrics = _metrics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminToolbar(title: 'Ko‘rsatkichlar', busy: loading, onRefresh: _load),
        if (error != null && metrics != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: AdminBanner(message: error!, onDismiss: () => setState(() => error = null)),
          ),
        Expanded(child: _body(metrics)),
      ],
    );
  }

  Widget _body(AdminMetrics? metrics) {
    if (metrics == null) {
      if (loading) return const Center(child: CircularProgressIndicator());
      if (error != null) return AdminErrorBox(message: error!, onRetry: _load);
      return const AdminEmpty(message: "Ma'lumot yo'q");
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _tile('Foydalanuvchilar', '${metrics.totalUsers}', 'O‘chirilganlar hisobga olinmagan', WBColors.amber),
              _tile('Bloklanganlar', '${metrics.bannedUsers}', 'Hozir kira olmaydiganlar', WBColors.red),
              _tile('Bugungi janglar', '${metrics.battlesToday}', 'Mahalliy yarim tundan beri', WBColors.green),
              _tile('Odam bilan', '${metrics.humanBattles}', 'Reytingga ta’sir qiladi', WBColors.indigo),
              _tile('Bot bilan', '${metrics.botBattles}', 'Reytingsiz janglar', WBColors.purpleText),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: WBColors.cardFill,
              border: Border.all(color: WBColors.cardBorder),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Bot ulushi', style: WBText.grotesk(size: 14, weight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  'Tugagan ${metrics.totalBattles} jangning ${metrics.botPercent}% i bot bilan o‘tgan. '
                  'Bu ulush o‘sib borsa, o‘yinchilar bir-birini topa olmayapti degani.',
                  style: WBText.grotesk(size: 13, color: WBColors.textA(.6)),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: metrics.botPercent / 100,
                    minHeight: 8,
                    backgroundColor: WBColors.whiteA(.06),
                    valueColor: AlwaysStoppedAnimation(WBColors.amber),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(String label, String value, String note, Color color) => Container(
        width: 220,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: WBColors.cardFill,
          border: Border.all(color: WBColors.cardBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(),
                style: WBText.mono(size: 10, weight: FontWeight.w600, color: color, letterSpacing: .08)),
            const SizedBox(height: 8),
            Text(value, style: WBText.grotesk(size: 30, weight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(note, style: WBText.grotesk(size: 11, color: WBColors.textA(.45))),
          ],
        ),
      );
}
