#!/usr/bin/env bash
# `rice-sddm setup`: the command it hands to sudo/pkexec, per distro (OS_RELEASE points at a fixture, so this runs
# off Linux), and nothing at all when SDDM is already there. No package is installed: the stub only records the call.
# shellcheck disable=SC2015,SC2016  # ok/bad are if-then-else after a test and both exit; the literals are the point
set -Euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sddm="$root/bin/rice-sddm"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
n=0
ok() { n=$((n + 1)); printf 'ok %d - %s\n' "$n" "$1"; }
bad() { printf 'not ok %d - %s\n' "$n" "$1"; exit 1; }

mkdir -p "$t/bin"
# sudo and pkexec: record the command, install nothing (setup then stops at "SDDM is not on PATH")
for s in sudo pkexec; do
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >"$SUDO_RAN"\n' >"$t/bin/$s"
  chmod +x "$t/bin/$s"
done
run() {  # run ID ID_LIKE -> the recorded command ("" when nothing was run)
  printf 'ID=%s\nID_LIKE="%s"\n' "$1" "${2:-}" >"$t/os-release"
  rm -f "$t/ran"
  SUDO_RAN="$t/ran" OS_RELEASE="$t/os-release" PATH="$t/bin:$PATH" "$sddm" setup >"$t/out" 2>&1 || true
  cat "$t/ran" 2>/dev/null
}

[ "$(run arch)" = 'bash -c pacman -S --needed --noconfirm sddm qt6-svg qt6-declarative' ] \
  && ok "Arch fetches SDDM and the theme's Qt modules without asking" || bad "Arch: $(run arch)"
[ "$(run artix arch)" = 'bash -c pacman -S --needed --noconfirm sddm sddm-$(rice-sys init) qt6-svg qt6-declarative' ] \
  && ok "Artix gets its init's SDDM package" || bad "Artix: $(run artix arch)"
[ "$(run fedora)" = 'bash -c dnf install -y sddm' ] && ok "Fedora: dnf install -y sddm" || bad "Fedora: $(run fedora)"
[ "$(run debian)" = 'bash -c apt-get install -y sddm' ] && ok "Debian: apt-get install -y sddm" || bad "Debian: $(run debian)"
[ "$(run opensuse-tumbleweed)" = 'bash -c zypper install -y sddm' ] \
  && ok "openSUSE: zypper install -y sddm" || bad "openSUSE: $(run opensuse-tumbleweed)"

# NixOS: the line for configuration.nix, no command, and the failure is not silent
printf 'ID=nixos\n' >"$t/os-release"; rm -f "$t/ran"
if SUDO_RAN="$t/ran" OS_RELEASE="$t/os-release" PATH="$t/bin:$PATH" "$sddm" setup >"$t/out" 2>&1; then
  bad "NixOS: setup said it worked"
fi
grep -q 'configuration.nix' "$t/out" && [ ! -e "$t/ran" ] \
  && ok "NixOS: points at configuration.nix, runs nothing" || bad "NixOS: $(cat "$t/out")"

# SDDM already installed: no package command, the theme path (which stops: there is no repo in this test)
: >"$t/bin/sddm"; chmod +x "$t/bin/sddm"; rm -f "$t/ran"
SUDO_RAN="$t/ran" OS_RELEASE="$t/os-release" PATH="$t/bin:$PATH" "$sddm" setup >"$t/out" 2>&1 || true
[ ! -e "$t/ran" ] && grep -q "folder was not found" "$t/out" \
  && ok "SDDM already there: no package is fetched" || bad "SDDM present: $(cat "$t/out")"
