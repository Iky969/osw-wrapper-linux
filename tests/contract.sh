#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Iky969
#
# Tes kontrak modul os/*.sh.
# Modul di-source (bukan dieksekusi) dengan stub helper dispatcher, lalu
# diperiksa fungsi wajib/opsionalnya dan aturan arsitekturnya.
#
# Pemakaian:
#   bash tests/contract.sh              # semua modul di os/
#   bash tests/contract.sh os/void.sh   # modul tertentu
#
# Exit: 0 kalau semua modul memenuhi kontrak, 1 kalau ada pelanggaran.

set -uo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"

# Wajib ada di setiap modul (dipanggil dispatcher tanpa fallback).
REQUIRED_FUNCS=(
    pkg_install
    pkg_remove
    pkg_update
    pkg_upgrade
    pkg_full_upgrade
    pkg_search
    pkg_info
    pkg_list
    pkg_autoremove
    pkg_clean
)

# Boleh tidak ada; dispatcher memakai fallback return 3.
OPTIONAL_FUNCS=(
    pkg_files
    pkg_owner
    pkg_orphans
    pkg_autoclean
)

FAILED=0

_fail() {
    printf '  gagal: %s\n' "$*" >&2
    return 1
}

# Cetak fungsi kontrak yang didefinisikan modul. Dijalankan di subshell supaya
# definisi satu modul tidak bocor ke modul berikutnya.
_defined_funcs() {
    local file="$1"
    (
        set +e
        _priv() { :; }
        _run() { :; }
        _info() { :; }
        _warn() { :; }
        _err() { :; }
        # shellcheck disable=SC1090
        . "$file" >/dev/null 2>&1
        local fn=""
        for fn in "${REQUIRED_FUNCS[@]}" "${OPTIONAL_FUNCS[@]}"; do
            if declare -F "$fn" >/dev/null 2>&1; then
                printf '%s\n' "$fn"
            fi
        done
    )
}

check_module() {
    local file="$1"
    local name
    name="${file#"$ROOT_DIR/"}"
    local ok=1

    if [[ "$(head -n 1 "$file")" != "#!/usr/bin/env bash" ]]; then
        _fail "$name: shebang bukan #!/usr/bin/env bash"
        ok=0
    fi

    # Modul tidak boleh mengubah mode shell dispatcher.
    if grep -qE '^[[:space:]]*set[[:space:]]+-[a-z]*e' "$file"; then
        _fail "$name: modul memakai set -e (mode shell diurus dispatcher)"
        ok=0
    fi

    # Modul tidak boleh mem-parse argumen global sendiri.
    if grep -qE '(^|[^[:alnum:]_])(getopts|while[[:space:]]+\[\[[[:space:]]*\$#)' "$file"; then
        _fail "$name: modul mem-parse argumen sendiri (flag global diurus dispatcher)"
        ok=0
    fi

    local defined=""
    defined="$(_defined_funcs "$file")"

    local fn=""
    local -a missing=()
    for fn in "${REQUIRED_FUNCS[@]}"; do
        if ! grep -qx -- "$fn" <<<"$defined"; then
            missing+=("$fn")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        _fail "$name: fungsi wajib tidak ada: ${missing[*]}"
        ok=0
    fi

    local -a present=()
    for fn in "${OPTIONAL_FUNCS[@]}"; do
        if grep -qx -- "$fn" <<<"$defined"; then
            present+=("${fn#pkg_}")
        fi
    done

    if [[ "$ok" == "1" ]]; then
        local optional="tidak ada"
        if [[ ${#present[@]} -gt 0 ]]; then
            optional="${present[*]}"
        fi
        printf 'PASS  %s (%d wajib, opsional: %s)\n' \
            "$name" "${#REQUIRED_FUNCS[@]}" "$optional"
        return 0
    fi

    printf 'FAIL  %s\n' "$name"
    FAILED=$((FAILED + 1))
    return 1
}

if [[ $# -gt 0 ]]; then
    MODULES=("$@")
else
    MODULES=("$ROOT_DIR"/os/*.sh)
fi

printf 'kontrak modul osw (%s)\n\n' "$ROOT_DIR"
for module in "${MODULES[@]}"; do
    if [[ ! -f "$module" ]]; then
        printf 'FAIL  %s: file tidak ada\n' "$module"
        FAILED=$((FAILED + 1))
        continue
    fi
    check_module "$module" || true
done

printf '\n%d modul: %d gagal\n' "${#MODULES[@]}" "$FAILED"

if [[ "$FAILED" -gt 0 ]]; then
    exit 1
fi

exit 0
