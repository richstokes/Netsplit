# Netsplit development

- Treat the installed app's preferences, sandbox container, and Keychain entries as user data. Do not use them for test fixtures or reset them during reviews.
- Run tests and local probes with the Debug configuration (`richstokes.irc.debug`). Use injected disposable `UserDefaults` suites and test credential stores. A volatile override of `UserDefaults.standard` does not isolate subsequent writes.
- Before launching a test build, verify both the built app's `CFBundleIdentifier` and the generated `.xctestrun` file's `TestHostBundleIdentifier` are `richstokes.irc.debug`. Xcode can retain the previous identifier on the first incremental build after a bundle-ID change; rebuild or clean if they disagree.
- Release archives retain `richstokes.irc` for App Store compatibility. Do not launch them with test fixture data.
