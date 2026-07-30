#!/usr/bin/env bash
# ====================================================================
#  TOEIC 単語トレーナー デプロイスクリプト
#  ファイル最終更新日時: 2026-07-30 10:20 (JST)
#  バージョン: 1.0.1
# --------------------------------------------------------------------
#  【作成の意図 / 経緯】
#    更新のたびに「ダウンロード → リポジトリへコピー → commit → push」を
#    手で打っていると、コピー漏れや sw.js のキャッシュ名の上げ忘れが起きる。
#    （キャッシュ名を上げ忘れると、iPhoneのホーム画面アプリが古いままになる）
#    そこで、コピーと検査とpushを1コマンドにまとめた。
#
#  【使い方】
#    1) チャットからダウンロードしたファイルは ~/Downloads に置いたまま
#    2) ./deploy.sh            … 通常のデプロイ
#       ./deploy.sh -n         … コピーと検査だけ（pushしない・確認用）
#       ./deploy.sh -m "説明"  … コミットメッセージを指定
#
#  【やっていること】
#    - SRC_DIR にあるファイルのうち、更新対象のものだけを REPO_DIR へコピー
#    - index.html から APP_VERSION を読み取る
#    - sw.js の CACHE 名にそのバージョンが入っているか検査（入っていなければ中止）
#    - JSON が壊れていないか検査
#    - git add / commit / push
# ====================================================================
set -euo pipefail

# ---- 環境に合わせてここだけ書き換える ------------------------------
REPO_DIR="${REPO_DIR:-$HOME/toeic-vocab}"     # ローカルのリポジトリ
SRC_DIR="${SRC_DIR:-$HOME/Downloads}"         # ダウンロード先
BRANCH="${BRANCH:-main}"
# --------------------------------------------------------------------

# 更新対象になりうるファイル（存在するものだけコピーする）
FILES=(
  index.html
  shadowing.html
  shadowing.json
  word-relations.json
  sw.js
  manifest.json
  README.md
  toeic-500.json toeic-1000.json toeic-extra.json toeic-extra2.json
  toeic-new1000.json toeic-new2.json
  part5.json part6.json
  imagevocab.html
  deploy.sh
  deploy.ps1
)

DRY=0
MSG=""
while getopts "nm:" opt; do
  case "$opt" in
    n) DRY=1 ;;
    m) MSG="$OPTARG" ;;
    *) echo "使い方: ./deploy.sh [-n] [-m \"コミットメッセージ\"]"; exit 1 ;;
  esac
done

echo "── リポジトリ : $REPO_DIR"
echo "── コピー元   : $SRC_DIR"
[ -d "$REPO_DIR/.git" ] || { echo "✗ $REPO_DIR がgitリポジトリではありません"; exit 1; }

# ---- 1. コピー -----------------------------------------------------
echo
echo "▼ ファイルをコピー"
COPIED=0
for f in "${FILES[@]}"; do
  if [ -f "$SRC_DIR/$f" ]; then
    # 中身が同じならスキップ（無駄なコミットを作らない）
    if [ -f "$REPO_DIR/$f" ] && cmp -s "$SRC_DIR/$f" "$REPO_DIR/$f"; then
      echo "   = $f (変更なし)"
    else
      cp "$SRC_DIR/$f" "$REPO_DIR/$f"
      echo "   ✓ $f"
      COPIED=$((COPIED+1))
    fi
  fi
done
[ "$COPIED" -eq 0 ] && echo "   （新しく反映するファイルはありませんでした）"

cd "$REPO_DIR"

# ---- 2. 検査: バージョンとキャッシュ名の整合 ------------------------
echo
echo "▼ 検査"
VER="$(grep -m1 -o 'const APP_VERSION *= *"[^"]*"' index.html | sed 's/.*"\(.*\)"/\1/')"
UPD="$(grep -m1 -o 'const LAST_UPDATED *= *"[^"]*"' index.html | sed 's/.*"\(.*\)"/\1/')"
CACHE="$(grep -m1 -o "const CACHE *= *'[^']*'" sw.js | sed "s/.*'\(.*\)'/\1/")"
echo "   アプリ版      : $VER  ($UPD)"
echo "   SWキャッシュ  : $CACHE"

if [[ "$CACHE" != *"$VER"* ]]; then
  echo "   ✗ sw.js の CACHE 名にアプリ版 $VER が入っていません。"
  echo "     上げ忘れるとホーム画面アプリが古いまま残ります。sw.js を直してください。"
  exit 1
fi
echo "   ✓ キャッシュ名は最新版に一致"

# JSONの構文チェック（壊れたJSONを公開しないため）
for j in *.json; do
  [ -f "$j" ] || continue
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "import json,sys; json.load(open(sys.argv[1],encoding='utf-8'))" "$j" \
      || { echo "   ✗ $j が壊れています"; exit 1; }
  fi
done
echo "   ✓ JSONの構文は正常"

# ---- 3. push -------------------------------------------------------
echo
if [ -z "$(git status --porcelain)" ]; then
  echo "▼ 変更なし。pushする内容はありません。"
  exit 0
fi
echo "▼ 変更内容"
git status --short

if [ "$DRY" -eq 1 ]; then
  echo
  echo "（-n 指定のため push しませんでした）"
  exit 0
fi

[ -n "$MSG" ] || MSG="v$VER ($UPD)"
git add -A
git commit -m "$MSG"
git push origin "$BRANCH"

echo
echo "✓ 完了: v$VER を公開しました"
echo "  反映まで1分ほどかかります。スマホはアイコンから開き直すと自動で更新されます。"
echo "  変わらないときは アプリ内 設定 →「🔄 最新版に更新する」を押してください。"
