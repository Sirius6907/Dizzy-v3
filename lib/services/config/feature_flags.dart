/// Compile-time feature flags (v1.1.9 Task 18).
/// Flip to `true` to re-enable a gated feature. Zero runtime cost.
library;

/// Arabic-dubbed anime section (pages + service + extractor wiring).
/// OFF by default: saves APK size pressure + removes a dead-code network
/// surface. Reversible — set true, rebuild, done.
const bool kEnableArabic = false;
