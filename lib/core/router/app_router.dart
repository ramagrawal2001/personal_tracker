import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/biometric_gate.dart';
import '../../features/auth/presentation/auth_repository.dart';
import '../../features/navigation/main_shell.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/accounts/presentation/accounts_screen.dart';
import '../../features/transactions/presentation/transactions_screen.dart';
import '../../features/credit_cards/presentation/credit_cards_screen.dart';
import '../../features/loans/presentation/loans_screen.dart';
import '../../features/budgets/presentation/budgets_screen.dart';
import '../../features/goals/presentation/goals_screen.dart';
import '../../features/goals/presentation/add_goal_screen.dart';

import '../../features/categories/presentation/categories_screen.dart';

import '../../features/investments/presentation/investments_screen.dart';

import '../../features/recurring/presentation/calendar_screen.dart';

import '../../features/reports/presentation/reports_screen.dart';
import '../../features/net_worth/presentation/net_worth_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/profile_screen.dart';



import '../../features/splash/presentation/splash_screen.dart';
import '../../features/notes/presentation/notes_screen.dart';
import '../../features/notes/presentation/note_editor_screen.dart';
import '../../features/legal/privacy_policy_screen.dart';
import '../../features/legal/terms_screen.dart';
import '../../features/reports/presentation/analytics_screen.dart';
import '../../features/admin/presentation/admin_screen.dart';
import '../../features/auth/presentation/forgot_password_screen.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final GlobalKey<NavigatorState> _shellNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

bool _isAdmin(AuthState authState) {
  final user = authState.user;
  if (user == null) return false;
  return user.userMetadata?['app_role'] == 'admin' || user.appMetadata['app_role'] == 'admin';
}

/// Routes reachable without a session.
const _publicPaths = <String>{
  '/splash', '/login', '/forgot-password', '/privacy-policy', '/terms',
};

/// Bridges [authNotifierProvider] changes to go_router so `redirect` re-runs
/// the moment auth state flips (sign-in, sign-out, token-refresh failure).
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Ref ref) {
    ref.listen(authNotifierProvider, (_, __) => notifyListeners());
  }
}

/// Built via a provider (rather than as a bare top-level constant) so the
/// guard below can read live auth state through [ref] on every navigation
/// attempt, instead of only hiding the entry point in the UI.
final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefresh(ref);
  ref.onDispose(refresh.dispose);
  return GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/splash',
  refreshListenable: refresh,
  redirect: (context, state) {
    final auth = ref.read(authNotifierProvider);
    final loc = state.matchedLocation;
    final isPublic = _publicPaths.contains(loc);

    // Hold on /splash until the session-restore probe has finished.
    if (!auth.isRestored) return loc == '/splash' ? null : '/splash';

    // No valid token → only public routes are reachable.
    if (!auth.isAuthenticated) return isPublic ? null : '/login';

    // Authenticated: keep the user out of the pre-auth screens.
    if (loc == '/splash' || loc == '/login') return '/';
    if (loc == '/admin' && !_isAdmin(auth)) return '/';
    return null;
  },
  routes: [
    // ── Public / full-page routes (no shell) ─────────────────────────────
    GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
    GoRoute(path: '/login',  builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/forgot-password', builder: (_, __) => const ForgotPasswordScreen()),
    GoRoute(path: '/privacy-policy',  builder: (_, __) => const PrivacyPolicyScreen()),
    GoRoute(path: '/terms',           builder: (_, __) => const TermsScreen()),
    GoRoute(path: '/admin',           builder: (_, __) => const AdminScreen()),

    // ── Shell routes (all authenticated routes with Finance/Notes switcher) ─
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) => BiometricGate(
        child: MainShell(child: child),
      ),
      routes: [
        // Finance
        GoRoute(path: '/',             builder: (_, __) => const DashboardScreen()),
        GoRoute(path: '/transactions', builder: (_, __) => const TransactionsScreen()),
        GoRoute(path: '/accounts',     builder: (_, __) => const AccountsScreen()),
        GoRoute(path: '/credit-cards', builder: (_, __) => const CreditCardsScreen()),
        GoRoute(path: '/loans',        builder: (_, __) => const LoansScreen()),
        GoRoute(path: '/budgets',      builder: (_, __) => const BudgetsScreen()),
        GoRoute(path: '/goals',        builder: (_, __) => const GoalsScreen()),
        GoRoute(path: '/goals/add',    builder: (_, __) => const AddGoalScreen()),
        GoRoute(path: '/categories',   builder: (_, __) => const CategoriesScreen()),
        GoRoute(path: '/investments',  builder: (_, __) => const InvestmentsScreen()),
        GoRoute(path: '/recurring',    builder: (_, __) => const CalendarScreen()),
        GoRoute(path: '/net-worth',    builder: (_, __) => const NetWorthScreen()),
        GoRoute(path: '/reports',      builder: (_, __) => const ReportsScreen()),
        GoRoute(path: '/analytics',    builder: (_, __) => const AnalyticsScreen()),
        GoRoute(path: '/settings',     builder: (_, __) => const SettingsScreen()),
        GoRoute(path: '/profile',      builder: (_, __) => const ProfileScreen()),
        // Notes module
        GoRoute(path: '/notes',        builder: (_, __) => const NotesScreen()),
        GoRoute(
          path: '/notes/editor',
          builder: (_, state) {
            final note = state.extra as dynamic;
            return NoteEditorScreen(note: note);
          },
        ),
      ],
    ),
  ],
  );
});
