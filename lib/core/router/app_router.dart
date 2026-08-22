import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
import '../../features/ai_assistant/presentation/ai_assistant_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/profile_screen.dart';



import '../../features/splash/presentation/splash_screen.dart';
import '../../features/notes/presentation/notes_screen.dart';
import '../../features/notes/presentation/note_editor_screen.dart';
import '../../features/legal/privacy_policy_screen.dart';
import '../../features/legal/terms_screen.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final GlobalKey<NavigatorState> _shellNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/splash',
  routes: [
    GoRoute(
      path: '/splash',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),

    ShellRoute(

      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) {
        return MainShell(child: child);
      },
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const DashboardScreen(),
        ),
        GoRoute(
          path: '/transactions',
          builder: (context, state) => const TransactionsScreen(),
        ),
        GoRoute(
          path: '/accounts',
          builder: (context, state) => const AccountsScreen(),
        ),
        GoRoute(
          path: '/credit-cards',
          builder: (context, state) => const CreditCardsScreen(),
        ),
        GoRoute(
          path: '/loans',
          builder: (context, state) => const LoansScreen(),
        ),
        GoRoute(
          path: '/budgets',
          builder: (context, state) => const BudgetsScreen(),
        ),
        GoRoute(
          path: '/goals',
          builder: (context, state) => const GoalsScreen(),
        ),
        GoRoute(
          path: '/goals/add',
          builder: (context, state) => const AddGoalScreen(),
        ),


        GoRoute(
          path: '/categories',
          builder: (context, state) => const CategoriesScreen(),
        ),

        GoRoute(
          path: '/investments',
          builder: (context, state) => const InvestmentsScreen(),
        ),

        GoRoute(
          path: '/recurring',
          builder: (context, state) => const CalendarScreen(),
        ),
        GoRoute(
          path: '/reports',
          builder: (context, state) => const ReportsScreen(),
        ),
        GoRoute(
          path: '/net-worth',
          builder: (context, state) => const NetWorthScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
        GoRoute(
          path: '/profile',
          builder: (context, state) => const ProfileScreen(),
        ),

        GoRoute(
          path: '/ai-assistant',
          builder: (context, state) => const AiAssistantScreen(),
        ),
        GoRoute(
          path: '/notes',
          builder: (context, state) => const NotesScreen(),
        ),
        GoRoute(
          path: '/notes/editor',
          builder: (context, state) {
            final note = state.extra as dynamic;
            return NoteEditorScreen(note: note);
          },
        ),
        GoRoute(
          path: '/privacy-policy',
          builder: (context, state) => const PrivacyPolicyScreen(),
        ),
        GoRoute(
          path: '/terms',
          builder: (context, state) => const TermsScreen(),
        ),

      ],
    ),
  ],
);
