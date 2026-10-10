# Arch Linux package

This directory contains the native Arch Linux package definition. It builds the
shared Rust backend and Qt frontend, then installs the launcher, desktop entry,
icon, and license notices into standard system locations.

`PKGBUILD` targets a matching Git tag. Update `pkgver` and `pkgrel` when making
a release, then run:

```bash
makepkg -si
```

The AppImage and portable Linux archive remain separate release formats under
`client/packaging/appimage`.
