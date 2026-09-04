import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../domain/models/models.dart';

class UpcomingPaymentsWidget extends StatelessWidget {
  final List<RecurringPaymentModel> upcomingPayments;
  final VoidCallback? onViewAll;

  const UpcomingPaymentsWidget({
    super.key,
    required this.upcomingPayments,
    this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Upcoming Obligations',
          actionLabel: onViewAll != null ? 'Calendar' : null,
          onAction: onViewAll,
          actionSemanticLabel: 'View all upcoming payments',
        ),
        if (upcomingPayments.isEmpty)
          AppCard(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text(
                'No upcoming payments due',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: upcomingPayments.length > 4 ? 4 : upcomingPayments.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final payment = upcomingPayments[index];
              return AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                semanticLabel: 'Payment: ${payment.title}, amount ${CurrencyFormatter.format(payment.amount)}, due ${DateFormatter.formatRelative(payment.nextDueDate)}',
                child: Row(
                  children: [
                    Semantics(
                      excludeSemantics: true,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: AppDecorations.iconBadge(AppColors.accent),
                        child: Icon(LucideIcons.calendar, color: AppColors.accent, size: 18),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            payment.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary, fontSize: 14),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Due ${DateFormatter.formatRelative(payment.nextDueDate)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      CurrencyFormatter.format(payment.amount),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontSize: 14),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}
