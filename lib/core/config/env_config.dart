/// Runtime configuration for external services.
///
/// Values are sourced from `--dart-define` / `--dart-define-from-file` at
/// build time, so real credentials never need to be hardcoded into source
/// control. Copy `dart_defines.example.json` to `dart_defines.json`
/// (gitignored) with real values and run:
///
///   flutter run --dart-define-from-file=dart_defines.json
///
/// The Supabase URL and the *publishable* anon key are safe to ship inside a
/// client binary, so they keep dev-friendly defaults below. Secrets that must
/// NOT live in version control (the Resend API key) have no literal default —
/// an empty value simply disables that integration until a dart-define is
/// supplied. `EmailOtpService.sendOtp` already degrades gracefully (returns
/// `false`) when [resendApiKey] is empty.
class EnvConfig {
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://zztvtryevtzqmlfgiiir.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_3TVjGyvtiCIUMkdZNOJMQw_PDC-slq_',
  );

  // Resend Email Service (aspyric.com verified domain).
  // NO default: this is a real secret and must be provided via --dart-define.
  static const String resendApiKey = String.fromEnvironment('RESEND_API_KEY');

  static const String resendFromEmail = String.fromEnvironment(
    'RESEND_FROM_EMAIL',
    defaultValue: 'Aspyric <noreply@aspyric.com>',
  );

  /// Whether outbound transactional email (OTP) is configured for this build.
  static bool get isEmailConfigured => resendApiKey.isNotEmpty;
}
