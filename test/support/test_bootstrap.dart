import 'package:google_fonts/google_fonts.dart';

/// Shared, network-free test setup.
///
/// `app_theme.dart` builds its text theme with `GoogleFonts.interTextTheme(...)`,
/// which — the first time a `MaterialApp` builds — tries to pull the Inter font
/// files from `fonts.gstatic.com`. There is no bundled Inter asset, so on a
/// headless / sandboxed runner (notably `integration_test/*`) that request hangs
/// or fails and the test dies before the first frame. Turning runtime fetching
/// off makes google_fonts fall back to the platform default font instead.
///
/// Call from a test `main()` immediately after the binding is initialised and
/// before the first `pumpWidget`.
void bootstrapTestEnv() {
  GoogleFonts.config.allowRuntimeFetching = false;
}
