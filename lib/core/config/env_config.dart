/// Runtime configuration for external services.
///
/// Only the Supabase URL and the *publishable* anon key live here — both are
/// safe to ship inside a client binary, so they keep working defaults and the
/// APK needs no `--dart-define` for a normal build. Override per-build with
/// `--dart-define-from-file=dart_defines.json` (gitignored) when pointing at a
/// different project.
///
/// Transactional email (the OTP) is sent by the `send-otp` Supabase Edge
/// Function, which holds the Resend API key as a server secret — no email
/// credential is compiled into the app.
class EnvConfig {
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://zztvtryevtzqmlfgiiir.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_3TVjGyvtiCIUMkdZNOJMQw_PDC-slq_',
  );
}
