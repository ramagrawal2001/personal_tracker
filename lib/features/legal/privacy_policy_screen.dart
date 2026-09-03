import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/theme/app_colors.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Privacy Policy', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header('Aspyric — Privacy Policy'),
            _para('Last updated: August 2026'),
            const SizedBox(height: 16),
            _section('1. Data We Collect'),
            _para('We collect only what is necessary to provide the service:\n• Email address (for authentication via Supabase Auth)\n• Financial data you voluntarily enter (accounts, transactions, credit cards, loans)\n• Notes you create within the app\n• Profile information you choose to provide (name, mobile, date of birth)'),
            _section('2. How Your Data Is Stored'),
            _para('All your financial data is stored locally on your device. Your authentication credentials are handled securely by Supabase with industry-standard encryption. We do NOT store your financial details on any server without your explicit consent.'),
            _section('3. Data We Never Collect'),
            _para('We do NOT collect:\n• Biometric data (Face ID / Fingerprint — processed entirely by your device OS)\n• Bank account credentials or OTPs\n• SMS or call logs\n• Device contacts\n• Location data'),
            _section('4. Data Sharing'),
            _para('We do NOT sell, rent, or share your personal data with third parties. Aggregated, anonymised analytics (e.g. total user counts) may be used internally to improve the application.'),
            _section('5. Security'),
            _para('We implement AES-256 encryption for local data exports. Authentication tokens are stored in secure device storage. We recommend enabling Biometric Lock for added protection.'),
            _section('6. Your Rights'),
            _para('You have the right to:\n• Access all your data at any time (Export Vault)\n• Delete your account and all associated data\n• Update or correct your profile information'),
            _section('7. Children'),
            _para('This application is not intended for children under the age of 13. We do not knowingly collect personal information from children.'),
            _section('8. Contact'),
            _para('For privacy-related queries, contact us at: privacy@aspyric.app'),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _header(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
  );

  Widget _section(String text) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Text(text, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primary)),
  );

  Widget _para(String text) => Text(text, style: TextStyle(color: AppColors.textSecondary, height: 1.6, fontSize: 14));
}
