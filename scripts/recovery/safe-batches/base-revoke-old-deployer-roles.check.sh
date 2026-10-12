#!/usr/bin/env bash
# Pre-flight / post-check for base-revoke-old-deployer-roles.json.
# Usage: ./base-revoke-old-deployer-roles.check.sh [pre|post] [RPC_URL]
# Prints every relevant role and draw recipient, then the expected-vs-actual verdict for the
# chosen phase. Exit code 1 when anything differs from the expectation.
set -euo pipefail
PHASE="${1:-pre}"
RPC="${2:-https://mainnet.base.org}"
CTRL=0xb0D7Eb2D5036fB85A231D0E243a5b723BA5D2868
KASU=0xC3128d734563E0d034d3ea177129657408C09D35
DEP=0x0e7e0a898ddBbE859d08976dE1673c7A9F579483
ADM=0x7adf999af5E0617257014C94888cf98c4584E5E9
MGR=0x39905d92Fc61643546D0940F97E5B5D0C0FB69F2
GENESIS=0xe621eC2A0De3C9EAb96e088256b60c59FFF87607
INVOICE=0x54A98e1baeD45854789B0448ED1277997D64FFFE
TAXATION=0xA30D35aa4eBb885c9c7Bb9de766266CD6a221eBe
ROLES=(ROLE_POOL_ADMIN ROLE_POOL_CLEARING_MANAGER ROLE_POOL_MANAGER ROLE_POOL_FUNDS_MANAGER)

fail=0
has() { # pool role account
  local out
  for _ in 1 2 3 4 5; do
    out=$(cast call --rpc-url "$RPC" "$CTRL" 'hasLendingPoolRole(address,bytes32,address)(bool)' "$1" "$(cast keccak "$2")" "$3" 2>/dev/null) && { echo "$out"; return; }
    sleep 2
  done
  echo ERR
}
expect() { # label actual expected
  if [ "$2" = "$3" ]; then printf '  ok   %-58s %s\n' "$1" "$2"; else printf '  FAIL %-58s %s (expected %s)\n' "$1" "$2" "$3"; fail=1; fi
}
draw() {
  cast call --rpc-url "$RPC" "$1" 'poolConfiguration()(((uint256,uint256,uint256,uint256)[],address,uint256,uint256,uint256,uint256))' \
    | grep -oE '0x[0-9a-fA-F]{40}' | head -1
}

echo "phase=$PHASE rpc=$RPC block=$(cast block-number --rpc-url "$RPC")"
creator=$(cast call --rpc-url "$RPC" "$CTRL" 'hasRole(bytes32,address)(bool)' "$(cast keccak ROLE_LENDING_POOL_CREATOR)" "$DEP")
kasuAdmin=$(cast call --rpc-url "$RPC" "$CTRL" 'hasRole(bytes32,address)(bool)' 0x0000000000000000000000000000000000000000000000000000000000000000 "$KASU")
expect "Kasu Safe DEFAULT_ADMIN_ROLE" "$kasuAdmin" true
if [ "$PHASE" = pre ]; then expect "old deployer ROLE_LENDING_POOL_CREATOR" "$creator" true
else expect "old deployer ROLE_LENDING_POOL_CREATOR" "$creator" false; fi

for pool in GENESIS INVOICE TAXATION; do
  P=${!pool}
  echo "$pool $P draw=$(draw "$P")"
  for r in "${ROLES[@]}"; do
    dep=$(has "$P" "$r" "$DEP"); adm=$(has "$P" "$r" "$ADM"); mgr=$(has "$P" "$r" "$MGR"); kasu=$(has "$P" "$r" "$KASU")
    stray=false; [ "$pool" = INVOICE ] && stray=$(has "$P" "$r" "$GENESIS")
    echo "  $r dep=$dep adm=$adm mgr=$mgr kasu=$kasu stray=$stray"
    if [ "$PHASE" = post ]; then
      expect "$pool $r old deployer" "$dep" false
      expect "$pool $r Kasu Safe (temporary admin dropped)" "$kasu" false
      expect "$pool $r stray pool-contract holder" "$stray" false
      expect "$pool $r Apxium pool admin" "$adm" true
      case $r in
        ROLE_POOL_MANAGER|ROLE_POOL_FUNDS_MANAGER) expect "$pool $r Apxium pool manager" "$mgr" true ;;
        *) expect "$pool $r Apxium pool manager" "$mgr" false ;;
      esac
    else
      expect "$pool $r old deployer (to be revoked)" "$dep" true
      expect "$pool $r Kasu Safe holds nothing yet" "$kasu" false
    fi
  done
done

if [ "$PHASE" = post ]; then
  expect "INVOICE draw recipient" "$(draw "$INVOICE")" "$KASU"
  expect "TAXATION draw recipient" "$(draw "$TAXATION")" "$KASU"
  expect "GENESIS draw recipient (unchanged)" "$(draw "$GENESIS")" "$MGR"
else
  expect "INVOICE draw recipient (to be moved)" "$(draw "$INVOICE")" "$ADM"
  expect "TAXATION draw recipient (to be moved)" "$(draw "$TAXATION")" "$DEP"
  expect "GENESIS draw recipient" "$(draw "$GENESIS")" "$MGR"
  expect "LendingPoolManager not paused" "$(cast call --rpc-url "$RPC" "$CTRL" 'paused()(bool)')" false
fi
[ $fail = 0 ] && echo "ALL OK" || { echo "MISMATCH - do not sign/execute until explained"; exit 1; }
