#!/usr/bin/env sh
# AscensionLFM local checks: Lua 5.1 compile + parser unit tests.
#
#   sh scripts/check.sh
set -eu
cd "$(dirname "$0")/.."

FAILED=0

echo "== Lua syntax (luac5.1 -p) =="
while IFS= read -r file; do
    if ! luac5.1 -p "$file" >/dev/null 2>&1; then
        echo "  FAIL: $file"
        FAILED=1
    else
        echo "  OK:   $file"
    fi
done <<EOF
$(find . -name '*.lua' ! -path './.git/*' ! -path './dist/*' | sort)
EOF

echo ""
echo "== No forbidden retail / suite APIs =="
# C_Manastorm is a verified Ascension 3.3.5a API, not a retail one, and the
# addon uses it deliberately (always type-guarded and wrapped in pcall).
# Without this allowlist the check printed FAILED on every single run, which
# is the fastest way to teach everyone to ignore it. Add a name here only
# after verifying it in the client extract.
ALLOWED_C_API='C_Manastorm'
FORBIDDEN=$(grep -rn -E '\b(C_Wildcard|RollAbilities|RerollAbilities|StartRapidRolling|C_[A-Za-z]+[.:])' . \
    --include='*.lua' \
    --exclude-dir=dist --exclude-dir=.git \
    | grep -v -E '^[^:]+:[0-9]+:[[:space:]]*--' \
    | grep -v -E "\b($ALLOWED_C_API)[.:]" || true)
if [ -n "$FORBIDDEN" ]; then
    echo "$FORBIDDEN" | sed 's/^/  /'
    FAILED=1
else
    echo "  OK: no forbidden C_* / roll / wildcard references (allowed: $ALLOWED_C_API)"
fi

echo ""
echo "== tests =="
RAN=0
for test in tests/test_*.lua; do
    [ -f "$test" ] || continue
    RAN=$((RAN + 1))
    if lua5.1 "$test"; then
        echo "  OK:   $test"
    else
        echo "  FAIL: $test"
        FAILED=1
    fi
done

if [ "$RAN" -eq 0 ]; then
    echo "  FAIL: no tests found in tests/"
    FAILED=1
fi

echo ""
if [ "$FAILED" -ne 0 ]; then
    echo "FAILED" >&2
    exit 1
fi
echo "OK: all checks passed"
