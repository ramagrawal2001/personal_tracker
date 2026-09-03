import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../theme/app_colors.dart';

class AppScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final bool showBackButton;
  final PreferredSizeWidget? bottom;
  final Widget? titleWidget;
  final EdgeInsetsGeometry? bodyPadding;
  final bool scrollable;

  const AppScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.showBackButton = false,
    this.bottom,
    this.titleWidget,
    this.bodyPadding,
    this.scrollable = false,
  });

  static Widget addAction({required VoidCallback onPressed}) => IconButton(
        icon: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(LucideIcons.plus, color: AppColors.primary, size: 20),
        ),
        onPressed: onPressed,
      );

  @override
  Widget build(BuildContext context) {
    final isRoot = GoRouterState.of(context).uri.path == '/';
    final hasBack = showBackButton || (context.canPop() && !isRoot);

    Widget content = body;
    if (bodyPadding != null) {
      content = Padding(padding: bodyPadding!, child: body);
    }
    if (scrollable) {
      content = SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: bodyPadding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: body,
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      // This per-screen Scaffold is the single owner of keyboard avoidance —
      // the navigation shell above it deliberately does not resize, so this one
      // must, to keep form fields scrollable above the on-screen keyboard.
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        primary: false,
        toolbarHeight: 50,
        titleSpacing: hasBack ? 0 : 16,
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: hasBack
            ? IconButton(
                icon: Icon(LucideIcons.arrowLeft, color: AppColors.textPrimary),
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                },
              )
            : null,
        title: titleWidget ??
            Text(
              title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                letterSpacing: -0.2,
              ),
            ),
        actions: [
          ...?actions,
          const SizedBox(width: 8),
        ],
        bottom: bottom,
      ),
      body: scrollable ? content : (bodyPadding != null ? content : body),
      floatingActionButton: floatingActionButton,
    );
  }
}
