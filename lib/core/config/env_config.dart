/// Runtime configuration for external services.
///
/// Values are sourced from `--dart-define` / `--dart-define-from-file` at
/// build time, so real credentials never need to be hardcoded into source
/// control. The literals below are only fallback defaults for local
/// development — override them for any build that matters by copying
/// `dart_defines.example.json` to `dart_defines.json` (gitignored) with real
/// values and running:
///
///   flutter run --dart-define-from-file=dart_defines.json
///
/// Before shipping this app to real users, rotate these values in the
/// Supabase and Resend dashboards and stop relying on the defaults here.
class EnvConfig {
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://zztvtryevtzqmlfgiiir.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_3TVjGyvtiCIUMkdZNOJMQw_PDC-slq_',
  );

  // Resend Email Service Configuration (aspyric.com Verified Domain)
  static const String resendApiKey = String.fromEnvironment(
    'RESEND_API_KEY',
    defaultValue: 're_CRjGicTc_KYnboCu5K75PzqrZBRnwjvuW',
  );

  static const String resendFromEmail = String.fromEnvironment(
    'RESEND_FROM_EMAIL',
    defaultValue: 'Aspyric <noreply@aspyric.com>',
  );
}
