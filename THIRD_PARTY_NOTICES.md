# Third-party notices

This file is an overview, not a replacement for the complete license texts and copyright notices distributed with each component.

## Qt 6.8.3

The Windows build dynamically links to Qt 6.8.3 libraries. Qt is not relicensed under PrismChat's AGPL license. The Qt open-source distribution is provided under module-specific terms, primarily LGPL-3.0 and GPL-3.0, and also contains third-party components under their own licenses.

A copy of the Qt GPL/LGPL license bundle is in `LICENSES/Qt-GPL-LGPL-3.0.txt`. Windows packages also include the SPDX documents from the exact Qt installation under `licenses/qt-sbom`; these describe Qt WebEngine/Chromium, FFmpeg, and other bundled third-party code.

PrismChat uses replaceable Qt DLLs/shared libraries. Recipients may replace those libraries and may reverse engineer the application when necessary to debug such changes, as required by LGPL-3.0. A distributor of PrismChat binaries must also keep the complete corresponding source for the exact Qt build under its control and either distribute it with the binaries or provide a valid written offer. A link to Qt's server by itself is not enough for that obligation.

Upstream source archives for Qt 6.8.3 are published at:
https://download.qt.io/archive/qt/6.8/6.8.3/submodules/

## Element Call Embedded 0.26.0

PrismChat embeds `@element-hq/element-call-embedded` 0.26.0. Upstream marks the code as `AGPL-3.0-only OR LicenseRef-Element-Commercial`. PrismChat uses the AGPL-3.0-only option; no commercial Element license is claimed.

Upstream repository:
https://github.com/element-hq/element-call

Pinned package:
https://registry.npmjs.org/@element-hq/element-call-embedded/-/element-call-embedded-0.26.0.tgz

SHA-512:
`e9262723c164d1ec4792796627cd19c381010b7aa549103679d20e0f7136edd2aac82ad270e70327255f5b9d0b52d183aa485aacadba27549d501c68e14a9abf`

The full AGPL-3.0 text is in `LICENSES/Element-Call-AGPL-3.0.txt`. The package fetcher preserves the upstream `LICENSE`, `NOTICE`, and `package.json` files when they are present. A binary release distributor must also make the complete corresponding source for this exact Element Call version available under the AGPL.

## Fonts

PrismChat includes Noto Emoji and Noto Sans CJK assets under the SIL Open Font License. Their license files are stored beside the fonts in `client/qml/assets` and copied into release packages.

## Other dependencies

Rust and native dependencies retain their own licenses. Their names and versions are pinned by `client/Cargo.lock`. Redistributors should retain all license and notice files produced by the release packaging process and audit dependency changes before publishing a binary release.
