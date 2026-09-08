import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_exception.dart';
import '../api/models.dart';
import '../theme.dart';
import 'admin_api_client.dart';
import 'admin_audit_screen.dart';
import 'admin_google_button.dart';
import 'admin_login_screen.dart';
import 'admin_matches_screen.dart';
import 'admin_metrics_screen.dart';
import 'admin_tournament_detail_screen.dart';
import 'admin_tournaments_screen.dart';
import 'admin_user_detail_screen.dart';
import 'admin_users_screen.dart';
import 'admin_widgets.dart';

/// Where the panel is, at any moment.
enum AdminStage {
  /// Checking a token left over from last time. Nothing is drawn but a spinner.
  restoring,

  /// The stored token could not be checked at all — the server is unreachable.
  /// Distinct from a refused token on purpose: the token is kept and the
  /// admin retries, exactly as the game's `Session.restore` treats it. A
  /// network that is down says nothing about whether a token is good.
  unreachable,

  login,

  /// Signed in, and not an admin.
  denied,

  panel,
}

enum AdminTab { metrics, users, tournaments, matches, audit }

/// The panel's root: it owns the session, the client every screen calls
/// through, and the single place a `401` or a `403` decides what happens next.
///
/// Deliberately nothing to do with `app_root.dart`. That one is the duel state
/// machine and the most load-bearing file in the project; this is a separate
/// entry point (`lib/main_admin.dart`) that never imports it, so no admin
/// screen can ever be reached from — or bundled into — the phone app.
class AdminRoot extends StatefulWidget {
  const AdminRoot({super.key, this.api});

  /// Injected by tests. The panel makes its own otherwise.
  final AdminApiClient? api;

  @override
  State<AdminRoot> createState() => _AdminRootState();
}

class _AdminRootState extends State<AdminRoot> {
  /// A key of its own, not the game's `wb_token`. The two are different
  /// sessions even when they are the same person, and signing out of one has no
  /// business ending the other. Held in the same secure storage the game's
  /// token is — an admin token is worth strictly more than a player's.
  static const _tokenKey = 'wb_admin_token';
  static const _storage = FlutterSecureStorage();

  late final AdminApiClient _api = widget.api ?? AdminApiClient();

  AdminStage _stage = AdminStage.restoring;
  AdminTab _tab = AdminTab.metrics;
  UserDto? _me;
  int? _openUserId;
  int? _openTournamentId;
  String? _notice;
  String? _bootError;

  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  // ------------------------------------------------------------- session

  Future<void> _restore() async {
    final token = await _storage.read(key: _tokenKey);
    if (token == null || token.isEmpty) {
      if (mounted) setState(() => _stage = AdminStage.login);
      return;
    }
    _api.token = token;
    await _verify();
  }

  /// Signing in and being allowed in are two questions. This asks the second
  /// one, and the server is the only thing that can answer it: `/admin/metrics`
  /// is refused with `403` for every token but an admin's.
  Future<void> _verify() async {
    try {
      // Held before the role is asked about, so a refusal can still name the
      // account it refused — an admin with two Google accounts needs to see
      // which one they used, and "Bu akkaunt admin emas" tells them nothing.
      final who = await _api.me();
      if (mounted) setState(() => _me = who);
      await _api.metrics();
      if (!mounted) return;
      setState(() {
        _stage = AdminStage.panel;
        _bootError = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        await _signOut(notice: 'Sessiya tugadi — qaytadan kiring');
        return;
      }
      if (e.isRoleRefusal) {
        setState(() => _stage = AdminStage.denied);
        return;
      }
      // A server that is down or a call that timed out. The token is not the
      // problem, so it is kept and the admin is offered a retry.
      setState(() {
        _stage = AdminStage.unreachable;
        _bootError = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = AdminStage.unreachable;
        _bootError = "Javobni o'qib bo'lmadi: $e";
      });
    }
  }

  Future<void> _login(String idToken) async {
    setState(() {
      _stage = AdminStage.restoring;
      _notice = null;
    });
    try {
      final result = await _api.loginWithGoogle(idToken);
      await _storage.write(key: _tokenKey, value: result.token);
      _api.token = result.token;
      if (!mounted) return;
      setState(() => _me = result.user);
      await _verify();
    } on ApiException catch (e) {
      _loginFailed(e);
    } catch (e) {
      _loginFailed(ApiException('bad_response', "Javobni o'qib bo'lmadi: $e"));
    }
  }

  /// Every way a sign-in can fail ends here, on the screen that started it —
  /// including `403 account_banned`, which is about the account rather than the
  /// admin role and so is a message rather than the permission screen. See
  /// [adminLoginMessage].
  void _loginFailed(ApiException e) {
    if (!mounted) return;
    setState(() {
      _stage = AdminStage.login;
      _notice = adminLoginMessage(e);
    });
  }

  Future<void> _signOut({String? notice}) async {
    await _storage.delete(key: _tokenKey);
    _api.token = null;
    await adminGoogleSignOut();
    if (!mounted) return;
    setState(() {
      _me = null;
      _openUserId = null;
      _tab = AdminTab.metrics;
      _notice = notice;
      _stage = AdminStage.login;
    });
  }

  /// The only two failures a screen hands up here, and the only two that mean
  /// the panel itself has to change. Everything else stays on the screen that
  /// caused it.
  void _onAuthFailure(ApiException e) {
    if (!mounted) return;
    if (e.isUnauthorized) {
      unawaited(_signOut(notice: 'Sessiya tugadi — qaytadan kiring'));
      return;
    }
    if (e.isRoleRefusal) setState(() => _stage = AdminStage.denied);
  }

  // ------------------------------------------------------------ navigation

  void _openUser(int userId) => setState(() {
        _tab = AdminTab.users;
        _openUserId = userId;
      });

  void _openTournament(int tournamentId) => setState(() {
        _tab = AdminTab.tournaments;
        _openTournamentId = tournamentId;
      });

  void _selectTab(AdminTab tab) => setState(() {
        _tab = tab;
        if (tab != AdminTab.users) _openUserId = null;
        if (tab != AdminTab.tournaments) _openTournamentId = null;
      });

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WBColors.bg,
      body: SafeArea(child: _stageBody()),
    );
  }

  Widget _stageBody() => switch (_stage) {
        AdminStage.restoring => const Center(child: CircularProgressIndicator()),
        AdminStage.unreachable => AdminErrorBox(
            message: _bootError ?? "Serverga ulanib bo'lmadi",
            onRetry: () {
              setState(() => _stage = AdminStage.restoring);
              unawaited(_verify());
            },
          ),
        AdminStage.login => AdminLoginScreen(
            notice: _notice,
            onIdToken: (idToken) => unawaited(_login(idToken)),
            onError: _loginFailed,
          ),
        AdminStage.denied => AdminDeniedScreen(
            who: _me?.label ?? 'Bu',
            onSignOut: () => unawaited(_signOut()),
          ),
        AdminStage.panel => _panel(),
      };

  Widget _panel() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        return Row(
          children: [
            _sidebar(wide),
            VerticalDivider(width: 1, color: WBColors.cardBorder),
            Expanded(child: _content()),
          ],
        );
      },
    );
  }

  Widget _content() => switch (_tab) {
        AdminTab.metrics => AdminMetricsScreen(api: _api, onAuthFailure: _onAuthFailure),
        AdminTab.users => _openUserId == null
            ? AdminUsersScreen(api: _api, onAuthFailure: _onAuthFailure, onOpenUser: _openUser)
            : AdminUserDetailScreen(
                api: _api,
                userId: _openUserId!,
                onAuthFailure: _onAuthFailure,
                onBack: () => setState(() => _openUserId = null),
              ),
        AdminTab.tournaments => _openTournamentId == null
            ? AdminTournamentsScreen(api: _api, onAuthFailure: _onAuthFailure, onOpenTournament: _openTournament)
            : AdminTournamentDetailScreen(
                api: _api,
                tournamentId: _openTournamentId!,
                onAuthFailure: _onAuthFailure,
                onBack: () => setState(() => _openTournamentId = null),
              ),
        AdminTab.matches => AdminMatchesScreen(api: _api, onAuthFailure: _onAuthFailure, onOpenUser: _openUser),
        AdminTab.audit => AdminAuditScreen(api: _api, onAuthFailure: _onAuthFailure, onOpenUser: _openUser),
      };

  Widget _sidebar(bool wide) {
    return Container(
      width: wide ? 220 : 64,
      color: WBColors.bgPanel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: wide ? 16 : 8, vertical: 18),
            child: wide
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('WORD BATTLE',
                          style: WBText.grotesk(size: 14, weight: FontWeight.w700, letterSpacing: .08)),
                      Text('ADMIN',
                          style: WBText.mono(size: 10, weight: FontWeight.w600, color: WBColors.amber, letterSpacing: .3)),
                    ],
                  )
                : Icon(Icons.shield_outlined, color: WBColors.amber, size: 22),
          ),
          _navItem(AdminTab.metrics, Icons.insights_outlined, 'Ko‘rsatkichlar', wide),
          _navItem(AdminTab.users, Icons.people_outline, 'Foydalanuvchilar', wide),
          _navItem(AdminTab.tournaments, Icons.emoji_events_outlined, 'Turnirlar', wide),
          _navItem(AdminTab.matches, Icons.sports_esports_outlined, 'Janglar', wide),
          _navItem(AdminTab.audit, Icons.receipt_long_outlined, 'Audit jurnali', wide),
          const Spacer(),
          Divider(height: 1, color: WBColors.cardBorder),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: wide ? 16 : 8, vertical: 12),
            child: wide
                ? Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_me?.label ?? '—',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: WBText.grotesk(size: 13, weight: FontWeight.w600)),
                            Text('#${_me?.id ?? '—'}',
                                style: WBText.mono(size: 10, color: WBColors.textA(.4))),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => unawaited(_signOut()),
                        icon: const Icon(Icons.logout, size: 18),
                        color: WBColors.textA(.6),
                        tooltip: 'Chiqish',
                      ),
                    ],
                  )
                : IconButton(
                    onPressed: () => unawaited(_signOut()),
                    icon: const Icon(Icons.logout, size: 18),
                    color: WBColors.textA(.6),
                    tooltip: 'Chiqish',
                  ),
          ),
        ],
      ),
    );
  }

  Widget _navItem(AdminTab tab, IconData icon, String label, bool wide) {
    final selected = _tab == tab;
    final content = Container(
      height: 44,
      padding: EdgeInsets.symmetric(horizontal: wide ? 16 : 0),
      decoration: BoxDecoration(
        color: selected ? WBColors.amberA(.12) : Colors.transparent,
        border: Border(left: BorderSide(color: selected ? WBColors.amber : Colors.transparent, width: 3)),
      ),
      child: Row(
        mainAxisAlignment: wide ? MainAxisAlignment.start : MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: selected ? WBColors.amber : WBColors.textA(.6)),
          if (wide) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WBText.grotesk(
                  size: 13,
                  weight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? WBColors.text : WBColors.textA(.7),
                ),
              ),
            ),
          ],
        ],
      ),
    );
    return InkWell(
      onTap: () => _selectTab(tab),
      hoverColor: WBColors.whiteA(.04),
      child: wide ? content : Tooltip(message: label, child: content),
    );
  }
}
