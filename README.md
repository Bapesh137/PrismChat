# PrismChat

PrismChat is a Matrix client. The desktop client source is in
[`client/`](client/).

## Download and run

Open the repository's **Releases** page and download the newest
`PrismChat-*-AppImage.tar.zst` file. Extract it and open the `PrismChat-*.AppImage`
file. The application starts both its Rust backend and Qt interface itself; no
`cargo run`, CMake command, or terminal is required.

On Windows, download `PrismChat-*-windows-x86_64.zip`, extract the whole
folder, and open `Start-PrismChat.exe`.

On either platform, PrismChat can create a desktop launcher from
**Settings → Appearance → Desktop shortcut**.

The `*-portable.tar.zst` asset is a fallback. Extract it and open `PrismChat`
inside the resulting directory.

The source archive offered by GitHub's **Code → Download ZIP** button contains
source code, not an installed application. End users should download a release
asset instead.

## Creating a release

Push a version tag such as `v0.1.0`. The GitHub Actions workflow builds the
backend and frontend, creates portable archives and an AppImage, generates
SHA-256 checksums, and attaches them to the matching GitHub Release.
