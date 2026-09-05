#!/bin/zsh
# Twin-file guard. The shared document model and clipboard parsers are
# byte-identical between the macOS app and the iPhone app's CosmoCoreKit
# (they are `public` on both sides and Foundation-only). Run from either
# repo; exits non-zero and prints a diff summary when a twin drifts.
#
#   Tools/verify_twins.sh            # compare against the sibling repo
#   Tools/verify_twins.sh --list     # print the twin table
set -u

MAC_ROOT=${MAC_ROOT:-"$HOME/CosmoOS-Swift"}
IOS_ROOT=${IOS_ROOT:-"$HOME/CosmoOS-iOS"}

# mac-relative path : ios-relative path
TWINS=(
  "Editor/Model/RichPassthrough.swift:CosmoCoreKit/Sources/Models/RichPassthrough.swift"
  "Editor/Model/RichTable.swift:CosmoCoreKit/Sources/Models/RichTable.swift"
  "Editor/Model/RichTableOperations.swift:CosmoCoreKit/Sources/Models/RichTableOperations.swift"
  "Editor/Model/RichSectionStyle.swift:CosmoCoreKit/Sources/Models/RichSectionStyle.swift"
  "Editor/Model/RichInlineColor.swift:CosmoCoreKit/Sources/Models/RichInlineColor.swift"
  "Editor/Clipboard/CosmoHTMLReader.swift:CosmoCoreKit/Sources/Models/CosmoHTMLReader.swift"
  "Editor/Clipboard/HTMLBlockImporter.swift:CosmoCoreKit/Sources/Models/HTMLBlockImporter.swift"
  "Editor/Clipboard/TabularTextImporter.swift:CosmoCoreKit/Sources/Models/TabularTextImporter.swift"
  "Editor/Clipboard/TableClipboardWriter.swift:CosmoCoreKit/Sources/Models/TableClipboardWriter.swift"
  "Editor/BlockEditor/Table/TableLayout.swift:CosmoCoreKit/Sources/Models/TableLayout.swift"
)

if [[ "${1:-}" == "--list" ]]; then
  for pair in "${TWINS[@]}"; do echo "${pair%%:*}  ↔  ${pair##*:}"; done
  exit 0
fi

rc=0
for pair in "${TWINS[@]}"; do
  mac="$MAC_ROOT/${pair%%:*}"
  ios="$IOS_ROOT/${pair##*:}"
  if [[ ! -f "$mac" ]]; then echo "MISSING (mac): $mac"; rc=1; continue; fi
  if [[ ! -f "$ios" ]]; then echo "MISSING (ios): $ios"; rc=1; continue; fi
  # Access modifiers are the one sanctioned difference: the Mac app is one
  # module (RichBlock is internal there), CosmoCoreKit exports everything.
  if ! cmp -s <(sed -E 's/public //g' "$mac") <(sed -E 's/public //g' "$ios"); then
    echo "DRIFT: ${pair%%:*}"
    diff <(sed -E 's/public //g' "$mac") <(sed -E 's/public //g' "$ios") | head -20
    rc=1
  fi
done

if [[ $rc -eq 0 ]]; then
  echo "twins ok (${#TWINS[@]} files)"
fi
exit $rc
