#!/bin/bash
set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

command -v flutter >/dev/null 2>&1 || {
  printf 'Hata: Flutter PATH içinde bulunamadı.\n' >&2
  exit 1
}
command -v dpkg-deb >/dev/null 2>&1 || {
  printf 'Hata: dpkg-deb bulunamadı.\n' >&2
  exit 1
}

version="$(awk '/^version:/ {print $2; exit}' pubspec.yaml)"
version="${version%%+*}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9]+)*$ ]] || {
  printf 'Hata: pubspec.yaml sürümü geçersiz: %s\n' "$version" >&2
  exit 1
}

readonly architecture=amd64
readonly package_name=performancepars
readonly bundle_dir="$project_root/build/linux/x64/release/bundle"
readonly staging_root="$project_root/build/deb/${package_name}_${version}_${architecture}"
readonly dist_dir="$project_root/dist"
readonly output_file="$dist_dir/${package_name}_${version}_${architecture}.deb"

flutter pub get
flutter analyze
flutter build linux --release

[[ -x "$bundle_dir/performancepars" ]] || {
  printf 'Hata: Flutter Linux paketi bulunamadı: %s\n' "$bundle_dir" >&2
  exit 1
}

rm -rf -- "$staging_root"
install -d \
  "$staging_root/DEBIAN" \
  "$staging_root/opt/performancepars" \
  "$staging_root/usr/bin" \
  "$staging_root/usr/lib/performancepars" \
  "$staging_root/usr/share/applications" \
  "$staging_root/usr/share/icons/hicolor/scalable/apps" \
  "$staging_root/usr/share/polkit-1/actions"

cp -a "$bundle_dir/." "$staging_root/opt/performancepars/"
install -m 0755 packaging/performancepars-launcher \
  "$staging_root/usr/bin/performancepars"
install -m 0755 packaging/performancepars-helper \
  "$staging_root/usr/lib/performancepars/performancepars-helper"
install -m 0644 packaging/com.performancepars.PerformancePars.desktop \
  "$staging_root/usr/share/applications/com.performancepars.PerformancePars.desktop"
install -m 0644 assets/performancepars.svg \
  "$staging_root/usr/share/icons/hicolor/scalable/apps/com.performancepars.PerformancePars.svg"
install -m 0644 packaging/com.performancepars.helper.policy \
  "$staging_root/usr/share/polkit-1/actions/com.performancepars.helper.policy"
install -m 0755 packaging/postinst "$staging_root/DEBIAN/postinst"
install -m 0755 packaging/postrm "$staging_root/DEBIAN/postrm"

installed_size="$(du -sk "$staging_root" | awk '{print $1}')"
cat >"$staging_root/DEBIAN/control" <<EOF
Package: performancepars
Version: $version
Section: utils
Priority: optional
Architecture: $architecture
Maintainer: PerformancePars <techasl7585@users.noreply.github.com>
Installed-Size: $installed_size
Depends: libgtk-3-0t64, libblkid1, liblzma5, libstdc++6, coreutils, procps, util-linux, iproute2, pciutils, udisks2, smartmontools, lm-sensors, intel-gpu-tools, libcap2-bin, pkexec
Suggests: nvidia-driver, nvidia-smi, nvtop
Homepage: https://github.com/techasl7585/performancepars
Description: Pardus için gerçek zamanlı sistem performans merkezi
 CPU, RAM, disk, ağ, GPU, sıcaklık, batarya, işlem ve SMART depolama
 sağlığı bilgilerini modern bir Flutter masaüstü arayüzünde gösterir.
EOF

mkdir -p "$dist_dir"
rm -f -- "$output_file" "$output_file.sha256"
dpkg-deb --root-owner-group --build "$staging_root" "$output_file"
(
  cd "$dist_dir"
  sha256sum "$(basename "$output_file")" >"$(basename "$output_file").sha256"
)

printf '\nHazır:\n  %s\n  %s.sha256\n' "$output_file" "$output_file"
