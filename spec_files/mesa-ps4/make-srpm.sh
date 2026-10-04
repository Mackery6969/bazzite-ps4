#!/usr/bin/bash
# Rebuild Terra's Mesa source RPM (the one Bazzite ships) with the PS4 patch.
#
#   make-srpm.sh <outdir> [version-release]
#
# Run on Fedora. The release gets a ".ps4" suffix so the result sorts above
# Terra's build of the same version. Prints the path of the new SRPM.

set -euo pipefail

OUTDIR="$(realpath "${1:?usage: $0 <outdir> [version-release]}")"
VERSION="${2:-}"
HERE="$(dirname "$(realpath "$0")")"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

if ! rpm -q terra-release-mesa >/dev/null 2>&1; then
    # $releasever is expanded by dnf, not the shell
    # shellcheck disable=SC2016
    dnf -y install --nogpgcheck \
        --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' \
        terra-release-mesa >&2
fi

dnf -y --setopt=terra-mesa-source.enabled=1 download --source \
    --destdir="${WORK}" "mesa${VERSION:+-${VERSION}}" >&2

TOPDIR="${WORK}/rpmbuild"
rpm -i --define "_topdir ${TOPDIR}" "${WORK}"/mesa-*.src.rpm
SPEC="${TOPDIR}/SPECS/mesa.spec"
cp "${HERE}/ps4-mesa.patch" "${TOPDIR}/SOURCES/"

# %autosetup -p1 applies every PatchN, so declaring it after the last one is enough
last_patch="$(grep -n '^Patch[0-9]*:' "${SPEC}" | tail -n1 | cut -d: -f1)"
sed -i "${last_patch}a Patch900:       ps4-mesa.patch" "${SPEC}"
grep -q '^%autosetup.*-p1' "${SPEC}" || { echo "mesa.spec no longer uses %autosetup -p1" >&2; exit 1; }

sed -i -E 's/^(Release:[[:space:]]*[0-9.]+)%\{\?dist\}/\1.ps4%{?dist}/' "${SPEC}"
grep -q '^Release:.*\.ps4%{?dist}' "${SPEC}" || { echo "could not tag Release in mesa.spec" >&2; exit 1; }

rpmbuild -bs --define "_topdir ${TOPDIR}" "${SPEC}" >&2
mkdir -p "${OUTDIR}"
cp "${TOPDIR}"/SRPMS/mesa-*.src.rpm "${OUTDIR}/"
ls "${OUTDIR}"/mesa-*.ps4*.src.rpm
