/// Modu does not use the upstream application's update channel.
/// Re-enable this entry point only after a Modu-owned release endpoint exists.
Future<void> checkUpdate(bool manualCheck) => Future<void>.value();
