# Continuation — 2026-09-14

## Native build dependency repair

The initial native CI stopped before compiling the application: Xcode 16.4 on the macOS 15 arm64 runner did not provide `archive.h`. The link dependency is the macOS system libarchive; adding an architecture-specific Homebrew binary would undermine the universal app distribution.

The CLibArchive shim now prefers installed public headers and has a narrow public-ABI declaration fallback for SDKs without them. It uses opaque archive handles and system `mode_t`, `ssize_t`, `size_t`, and fixed-width size values. It does not reproduce library structures or introduce a private framework. The existing `-larchive` link path is unchanged.

Reference public API: https://www.libarchive.org/man/archive_read.3.html and https://github.com/apple-oss-distributions/libarchive .

The continuation preserves the newer FileService, FileViews, and volume-eject fixes already on main. Native build/test outcomes are recorded separately from source changes; the presence of the fix does not by itself claim a successful macOS build.
