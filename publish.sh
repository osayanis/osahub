#!/bin/bash
# Publie une version d'OsaHUB sur GitHub (osayanis/osahub) :
#   ./publish.sh 0.1.1 notes.md
# notes.md = les nouveautés en Markdown ; les images qu'il contient (![](…)) s'affichent en
# captures dans OsaHUB. Construit l'app, fait OsaHUB.zip (mises à jour) et OsaHUB.dmg
# (installation), crée la release, puis commit + tag + push.
set -euo pipefail
cd "$(dirname "$0")"

V="${1:-}"
NOTES="${2:-}"
[[ "$V" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Usage : ./publish.sh X.Y.Z [notes.md]"; exit 1; }
gh release view "v$V" -R osayanis/osahub >/dev/null 2>&1 && { echo "La version $V est déjà publiée."; exit 1; }

git pull --rebase -q
echo "$V" > VERSION
./build.sh

rm -f OsaHUB.zip OsaHUB.dmg
ditto -c -k --keepParent OsaHUB.app OsaHUB.zip
STAGE="$(mktemp -d)"
cp -R OsaHUB.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -srcfolder "$STAGE" -volname OsaHUB -fs HFS+ -format UDZO -ov OsaHUB.dmg >/dev/null
rm -rf "$STAGE"

if [ -n "$NOTES" ]; then
  NOTES_ARGS=(--notes-file "$NOTES")
else
  NOTES_ARGS=(--notes "OsaHUB $V")
fi

git add VERSION
git commit -q -m "Version $V" || true
git tag "v$V"
git push -q && git push -q --tags
gh release create "v$V" OsaHUB.zip OsaHUB.dmg -R osayanis/osahub --title "OsaHUB $V" "${NOTES_ARGS[@]}"
echo "✅ OsaHUB $V publié."
