/// Shared test setup.
///
/// Historically `app_theme.dart` fetched Inter from `fonts.gstatic.com` via
/// `google_fonts` on first `MaterialApp` build, which hung/failed on a
/// headless or offline runner (notably `integration_test/*`). Inter is now
/// bundled locally (`assets/fonts/Inter-Variable.ttf`, declared in
/// `pubspec.yaml`), so theme resolution never touches the network and this
/// is a no-op — kept so every test `main()` that already calls it doesn't
/// need to change.
///
/// Call from a test `main()` immediately after the binding is initialised and
/// before the first `pumpWidget`.
void bootstrapTestEnv() {}
