import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Shows a post-delete confirmation SnackBar with a ~5-second "Undo"
/// affordance. [onUndo] should fully reverse the delete (un-tombstone the row
/// locally and drop the queued cloud delete) — see
/// `FinanceNotifier.undoDelete` / `NotesNotifier.undoDelete`.
void showUndoDeleteSnackBar(
  BuildContext context, {
  required String message,
  required VoidCallback onUndo,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 5),
      action: SnackBarAction(
        label: 'Undo',
        textColor: AppColors.accent,
        onPressed: onUndo,
      ),
    ),
  );
}
