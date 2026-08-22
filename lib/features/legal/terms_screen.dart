import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/theme/app_colors.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Terms & Conditions', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header('Terms & Conditions'),
            _para('Last updated: August 2026\n\nBy using Personal Finance OS, you agree to these terms. Please read them carefully.'),
            _section('1. Acceptance of Terms'),
            _para('By downloading, installing, or using Personal Finance OS ("the App"), you agree to be bound by these Terms and our Privacy Policy.'),
            _section('2. Use of the App'),
            _para('The App is provided for personal financial tracking purposes only. You agree to:\n• Provide accurate information when creating an account\n• Keep your login credentials confidential\n• Not use the App for any illegal or unauthorised purpose\n• Not attempt to reverse-engineer or tamper with the App'),
            _section('3. Financial Disclaimer'),
            _para('Personal Finance OS is a personal finance TRACKING tool. It does NOT provide:\n• Financial advice\n• Investment recommendations\n• Tax or legal counsel\n\nAlways consult a qualified financial advisor for financial decisions.'),
            _section('4. Data Responsibility'),
            _para('You are responsible for the accuracy of data you enter into the App. We are not liable for financial decisions made based on data entered or computed by the App.'),
            _section('5. Availability'),
            _para('We strive to keep the App operational but do not guarantee uninterrupted service. We reserve the right to modify, suspend, or discontinue features at any time.'),
            _section('6. Intellectual Property'),
            _para('All content, design, and code within the App are the intellectual property of Personal Finance OS. You may not copy, modify, or distribute any part of the App without written permission.'),
            _section('7. Limitation of Liability'),
            _para('To the maximum extent permitted by law, Personal Finance OS shall not be liable for any indirect, incidental, special, or consequential damages arising from your use of the App.'),
            _section('8. Governing Law'),
            _para('These Terms are governed by the laws of India. Any disputes shall be subject to the exclusive jurisdiction of courts in India.'),
            _section('9. Changes to Terms'),
            _para('We reserve the right to update these Terms at any time. Continued use of the App after changes constitutes acceptance of the updated Terms.'),
            _section('10. Contact'),
            _para('For queries: support@personalfinanceos.app'),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _header(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
  );

  Widget _section(String text) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primary)),
  );

  Widget _para(String text) => Text(text, style: const TextStyle(color: AppColors.textSecondary, height: 1.6, fontSize: 14));
}
