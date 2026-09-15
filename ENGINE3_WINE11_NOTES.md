# Engine 3 — Wine 11 runtime notes

Engine 3 currently uses a pinned macOS Wine 11.0_1 runtime from the Gcenx macOS Wine builds release archive.

Archive:
`https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.0_1/wine-stable-11.0_1-osx64.tar.xz`

SHA-256:
`b50dc50ec7f41d58b115a6b685d4d1315ba3c797bd3aa0f49213f2703cb82388`

The archive is installed outside the legacy Engine 2 directory under:
`Runtimes/wine11/Wine Stable.app`

The Wine loader and wineserver are resolved from:
`Wine Stable.app/Contents/Resources/wine/bin/wine`
`Wine Stable.app/Contents/Resources/wine/bin/wineserver`

This runtime is x86_64 and therefore requires Rosetta 2 on Apple silicon.

The runtime is not enabled as the default yet. Existing Engine 2 behaviour remains the default until Wine 11 has been built, installed, prefix-created, and benchmark-validated on real hardware.
