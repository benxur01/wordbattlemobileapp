/// The pieces every screen in the panel is built from, plus the one rule they
/// all follow about failures.
///
/// The game's colours and typefaces, laid out for a browser rather than a
/// phone: dense rows, real tables, nothing animated. An admin reading a
/// complaint wants to see many rows at once and to be told plainly when
/// something did not load.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api/api_exception.dart';
import '../theme.dart';
import 'admin_api_client.dart';
import 'admin_models.dart';

// ---------------------------------------------------------------- failures

/// What every admin screen does with a call that failed.
///
/// Two failures leave the screen entirely and are handed up to `AdminRoot`: a
/// `401`, which means the token is gone, and a `403`, which means this account
/// may not be here. Everything else — a timeout, a `409 nickname_taken`, a
/// `500` — is shown on the screen that asked for it, because the screen is
/// still usable and the admin needs to know what happened.
///
/// The plain `catch` at the end is the important one. It is there for a body
/// this client could not parse, which is the ordinary cost of a rolling deploy:
/// without it a `FormatException` escapes the `try`, matches no clause, and
/// leaves a spinner that never resolves and says nothing.
mixin AdminLoading<T extends StatefulWidget> on State<T> {
  bool loading = false;
  String? error;

  /// Where a 401 or a 403 goes. Supplied by the widget, which gets it from the
  /// panel's root.
  void Function(ApiException error) get onAuthFailure;

  Future<void> guard(Future<void> Function() body) async {
    if (!mounted) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await body();
    } on ApiException catch (e) {
      if (e.isUnauthorized || e.isRoleRefusal) {
        onAuthFailure(e);
        return;
      }
      if (mounted) setState(() => error = e.message);
    } catch (e) {
      if (mounted) setState(() => error = "Javobni o'qib bo'lmadi: $e");
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }
}

// ------------------------------------------------------------ small parts

/// A date as a browser wants to read it: `2026-08-11 16:32`, local time.
/// Null — a field the server omitted, or one this client could not parse — is
/// an em dash rather than a guess.
String adminDate(DateTime? at, {bool withTime = true}) {
  if (at == null) return '—';
  final local = at.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  final day = '${local.year}-${two(local.month)}-${two(local.day)}';
  return withTime ? '$day ${two(local.hour)}:${two(local.minute)}' : day;
}

class AdminBanner extends StatelessWidget {
  const AdminBanner({super.key, required this.message, this.onDismiss, this.tone = AdminTone.bad});

  final String message;
  final VoidCallback? onDismiss;
  final AdminTone tone;

  @override
  Widget build(BuildContext context) {
    final color = tone == AdminTone.good ? WBColors.green : WBColors.red;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        border: Border.all(color: color.withValues(alpha: .4)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(message, style: WBText.grotesk(size: 13, color: tone == AdminTone.good ? WBColors.green : WBColors.redSoft)),
          ),
          if (onDismiss != null)
            IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close, size: 16),
              color: WBColors.textA(.6),
              splashRadius: 16,
              tooltip: 'Yopish',
            ),
        ],
      ),
    );
  }
}

enum AdminTone { good, bad }

/// A failed load, said out loud, with the way back. Never a bare spinner and
/// never silence.
class AdminErrorBox extends StatelessWidget {
  const AdminErrorBox({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: WBColors.red, size: 28),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: WBText.grotesk(size: 14, color: WBColors.redSoft),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onRetry, child: const Text('Qayta urinish')),
            ],
          ],
        ),
      ),
    );
  }
}

class AdminEmpty extends StatelessWidget {
  const AdminEmpty({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(message, style: WBText.grotesk(size: 14, color: WBColors.textA(.5))),
        ),
      );
}

/// The state a row is in, in one word: banned, deleted, admin.
class AdminTag extends StatelessWidget {
  const AdminTag({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .15),
          border: Border.all(color: color.withValues(alpha: .5)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label, style: WBText.mono(size: 10, weight: FontWeight.w600, color: color)),
      );
}

/// The tags a user row carries, in the order that matters most first.
List<Widget> adminUserTags(AdminUserRow user) => [
      if (user.banned) const AdminTag(label: 'BLOK', color: WBColors.red),
      if (user.deleted) const AdminTag(label: "O'CHIRILGAN", color: WBColors.grey),
      if (user.admin) const AdminTag(label: 'ADMIN', color: WBColors.amber),
    ];

InputDecoration adminInput(String hint, {Widget? prefix}) => InputDecoration(
      hintText: hint,
      hintStyle: WBText.grotesk(size: 13, color: WBColors.textA(.35)),
      prefixIcon: prefix,
      isDense: true,
      filled: true,
      fillColor: WBColors.cardFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: WBColors.cardBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: WBColors.amberA(.6)),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: WBColors.red),
      ),
    );

// ----------------------------------------------------------------- tables

class AdminColumn {
  const AdminColumn(this.label, this.width);

  final String label;
  final double width;
}

/// A dense table that scrolls both ways: sideways as one piece, so the header
/// never parts company with its rows, and down through the rows alone, so the
/// header stays put while a hundred accounts go by.
///
/// Expects to be given a bounded height — inside an [Expanded], as every screen
/// here places it.
class AdminTable extends StatelessWidget {
  const AdminTable({
    super.key,
    required this.columns,
    required this.rows,
    this.onRowTap,
    this.rowHeight = 44,
  });

  final List<AdminColumn> columns;

  /// One list of cells per row, in the order of [columns].
  final List<List<Widget>> rows;

  final void Function(int index)? onRowTap;
  final double rowHeight;

  @override
  Widget build(BuildContext context) {
    final natural = columns.fold<double>(0, (sum, c) => sum + c.width);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.max(natural, constraints.maxWidth);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            child: Column(
              children: [
                _header(),
                Expanded(
                  child: ListView.builder(
                    itemCount: rows.length,
                    itemExtent: rowHeight,
                    itemBuilder: (context, index) => _row(index),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _header() => Container(
        height: 36,
        decoration: const BoxDecoration(
          color: WBColors.bgPanel,
          border: Border(bottom: BorderSide(color: WBColors.cardBorder)),
        ),
        child: _cells([
          for (final column in columns)
            Text(
              column.label.toUpperCase(),
              style: WBText.mono(size: 10, weight: FontWeight.w600, color: WBColors.textA(.5), letterSpacing: .08),
              overflow: TextOverflow.ellipsis,
            ),
        ]),
      );

  Widget _row(int index) {
    final content = Container(
      decoration: BoxDecoration(
        color: index.isEven ? Colors.transparent : WBColors.whiteA(.02),
        border: const Border(bottom: BorderSide(color: Color.fromRGBO(255, 255, 255, .05))),
      ),
      child: _cells(rows[index]),
    );
    if (onRowTap == null) return content;
    return InkWell(
      onTap: () => onRowTap!(index),
      hoverColor: WBColors.amberA(.05),
      child: content,
    );
  }

  /// Fixed widths, except the last column, which takes whatever the window has
  /// left over — otherwise a wide browser leaves the table hugging one edge.
  Widget _cells(List<Widget> cells) => Row(
        children: [
          for (var i = 0; i < columns.length; i++)
            if (i == columns.length - 1)
              Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: _align(cells[i])))
            else
              SizedBox(
                width: columns[i].width,
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: _align(cells[i])),
              ),
        ],
      );

  Widget _align(Widget cell) => Align(alignment: Alignment.centerLeft, child: cell);
}

/// The plain text a table cell is usually made of.
Widget adminCell(String text, {bool mono = false, Color? color, FontWeight weight = FontWeight.w400}) => Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: mono
          ? WBText.mono(size: 12, weight: weight, color: color ?? WBColors.textA(.85))
          : WBText.grotesk(size: 13, weight: weight, color: color ?? WBColors.textA(.85)),
    );

/// Page N of M, with the two buttons that move it. Disabled rather than hidden
/// at either end, so the controls do not jump around under the cursor.
class AdminPager extends StatelessWidget {
  const AdminPager({super.key, required this.page, required this.onPage, this.busy = false});

  final AdminPage<Object?>? page;
  final void Function(int page) onPage;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final current = page;
    if (current == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Text(
            'Jami: ${current.total}',
            style: WBText.mono(size: 12, color: WBColors.textA(.6)),
          ),
          const Spacer(),
          IconButton(
            onPressed: busy || !current.hasPrevious ? null : () => onPage(current.page - 1),
            icon: const Icon(Icons.chevron_left),
            color: WBColors.text,
            tooltip: 'Oldingi',
          ),
          Text(
            '${current.page + 1} / ${math.max(current.totalPages, 1)}',
            style: WBText.mono(size: 12, color: WBColors.textA(.8)),
          ),
          IconButton(
            onPressed: busy || !current.hasNext ? null : () => onPage(current.page + 1),
            icon: const Icon(Icons.chevron_right),
            color: WBColors.text,
            tooltip: 'Keyingi',
          ),
        ],
      ),
    );
  }
}

/// The bar above every table: a title, whatever the screen needs, and refresh.
class AdminToolbar extends StatelessWidget {
  const AdminToolbar({super.key, required this.title, this.trailing = const [], this.onRefresh, this.busy = false});

  final String title;
  final List<Widget> trailing;
  final VoidCallback? onRefresh;
  final bool busy;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Row(
          children: [
            Text(title, style: WBText.grotesk(size: 18, weight: FontWeight.w700)),
            const SizedBox(width: 16),
            ...trailing,
            const Spacer(),
            if (busy)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            if (onRefresh != null)
              IconButton(
                onPressed: busy ? null : onRefresh,
                icon: const Icon(Icons.refresh),
                color: WBColors.text,
                tooltip: 'Yangilash',
              ),
          ],
        ),
      );
}

// ---------------------------------------------------------------- dialogs

/// Yes/no, with the destructive answer named rather than called "OK". Returns
/// false when the dialog is dismissed, so a stray tap outside it can never be
/// read as consent.
Future<bool> adminConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = true,
}) async {
  final answer = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: WBColors.bgPanel,
      title: Text(title, style: WBText.grotesk(size: 16, weight: FontWeight.w700)),
      content: Text(message, style: WBText.grotesk(size: 14, color: WBColors.textA(.8))),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Bekor qilish')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: destructive ? WBColors.red : WBColors.amber,
            foregroundColor: destructive ? WBColors.text : WBColors.amberInk,
          ),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return answer ?? false;
}

/// A confirmation that also collects one line of text — the ban reason, the new
/// nickname. Returns null when dismissed, which is not the same as an empty
/// string: the reason is optional and "" is a real answer to it.
Future<String?> adminPrompt(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String hint = '',
  String initial = '',
  bool required = false,
  bool destructive = false,
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          final value = controller.text.trim();
          final canConfirm = !required || value.isNotEmpty;
          return AlertDialog(
            backgroundColor: WBColors.bgPanel,
            title: Text(title, style: WBText.grotesk(size: 16, weight: FontWeight.w700)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message, style: WBText.grotesk(size: 14, color: WBColors.textA(.8))),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  style: WBText.grotesk(size: 14),
                  decoration: adminInput(hint),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: canConfirm ? (text) => Navigator.of(context).pop(text.trim()) : null,
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Bekor qilish')),
              FilledButton(
                onPressed: canConfirm ? () => Navigator.of(context).pop(controller.text.trim()) : null,
                style: FilledButton.styleFrom(
                  backgroundColor: destructive ? WBColors.red : WBColors.amber,
                  foregroundColor: destructive ? WBColors.text : WBColors.amberInk,
                ),
                child: Text(confirmLabel),
              ),
            ],
          );
        },
      );
    },
  );
}
