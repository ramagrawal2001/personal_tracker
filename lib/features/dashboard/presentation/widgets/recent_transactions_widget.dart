import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../domain/models/models.dart';

class RecentTransactionsWidget extends StatelessWidget {
  final List<TransactionModel> transactions;
  final VoidCallback? onViewAll;

  const RecentTransactionsWidget({
    super.key,
    required this.transactions,
    this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Recent Transactions',
          actionLabel: onViewAll != null ? 'See All' : null,
          onAction: onViewAll,
        ),
        if (transactions.isEmpty)
          const AppCard(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text(
                'No transactions recorded yet',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: transactions.length > 5 ? 5 : transactions.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final tx = transactions[index];
              final isIncome = tx.type == TransactionType.income || tx.type == TransactionType.refund;
              final isTransfer = tx.type == TransactionType.transfer ||
                  tx.type == TransactionType.creditCardPayment ||
                  tx.type == TransactionType.loanPayment;

              final Color color = isIncome
                  ? AppColors.income
                  : isTransfer
                      ? AppColors.transfer
                      : AppColors.expense;

              final IconData icon = isIncome
                  ? LucideIcons.arrowDownLeft
                  : isTransfer
                      ? LucideIcons.arrowRightLeft
                      : LucideIcons.arrowUpRight;

              return AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: AppDecorations.iconBadge(color),
                      child: Icon(icon, color: color, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tx.merchant ?? tx.description ?? tx.type.displayName,
                            style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary, fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            DateFormatter.formatRelative(tx.date),
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${isIncome ? '+' : '-'}${CurrencyFormatter.format(tx.amount)}',
                      style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 14),
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
