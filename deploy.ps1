# =====================================================================
#  TOEIC 単語トレーナー デプロイスクリプト（Windows PowerShell 版）
#  ファイル最終更新日時: 2026-07-30 10:20 (JST)
#  バージョン: 1.0.1
# ---------------------------------------------------------------------
#  【作成の意図 / 経緯】
#    もともと deploy.sh（bash用）を用意したが、実行環境が Windows の
#    PowerShell だったため動かなかった。
#      - PowerShell の cp (Copy-Item) は「cp a b c .」の書き方ができない
#        （複数指定はカンマ区切り）
#      - .sh は PowerShell から直接実行できない
#    そこで、同じ処理を PowerShell 用に書き直した。deploy.sh は
#    Mac/Linux 用として残してある。
#
#  【使い方】
#    初回だけ（このセッションで .ps1 の実行を許可する）:
#        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#    以降:
#        cd ~\toeic-vocab
#        .\deploy.ps1                    # 通常のデプロイ
#        .\deploy.ps1 -DryRun            # コピーと検査だけ（pushしない）
#        .\deploy.ps1 -Message "説明"    # コミットメッセージを指定
#        .\deploy.ps1 -SrcDir D:\dl      # ダウンロード先を変える
#
#  【やっていること】
#    1. SrcDir にあるファイルのうち、更新されたものだけ RepoDir へコピー
#    2. index.html の APP_VERSION と sw.js の CACHE 名が一致するか検査
#       （ここがずれると iPhone のホーム画面アプリが古いまま更新されない）
#    3. 同梱JSONが壊れていないか検査
#    4. git add / commit / push
#
#  【v1.0.1 での変更】
#    deploy.ps1 / deploy.sh 自身もコピー対象に追加した。
#    スクリプトを更新したとき、手でコピーし直さずに済むようにするため。
# =====================================================================
[CmdletBinding()]
param(
    [string]$RepoDir = (Join-Path $HOME 'toeic-vocab'),
    [string]$SrcDir  = (Join-Path $HOME 'Downloads'),
    [string]$Branch  = 'main',
    [string]$Message = '',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# 更新対象になりうるファイル（存在するものだけコピーする）
$Files = @(
    'index.html',
    'shadowing.html',
    'shadowing.json',
    'word-relations.json',
    'sw.js',
    'manifest.json',
    'README.md',
    'toeic-500.json', 'toeic-1000.json', 'toeic-extra.json', 'toeic-extra2.json',
    'toeic-new1000.json', 'toeic-new2.json',
    'part5.json', 'part6.json',
    'imagevocab.html',
    'deploy.ps1',       # スクリプト自身も更新できるようにしておく
    'deploy.sh'
)

Write-Host "-- リポジトリ : $RepoDir"
Write-Host "-- コピー元   : $SrcDir"

if (-not (Test-Path (Join-Path $RepoDir '.git'))) {
    Write-Host "x $RepoDir がgitリポジトリではありません" -ForegroundColor Red
    exit 1
}

# ---- 1. コピー ------------------------------------------------------
Write-Host ''
Write-Host '▼ ファイルをコピー'
$copied = 0
foreach ($f in $Files) {
    $src = Join-Path $SrcDir  $f
    $dst = Join-Path $RepoDir $f
    if (-not (Test-Path $src)) { continue }

    # 中身が同じならスキップ（無駄なコミットを作らない）
    $same = $false
    if (Test-Path $dst) {
        $a = (Get-FileHash $src -Algorithm SHA256).Hash
        $b = (Get-FileHash $dst -Algorithm SHA256).Hash
        $same = ($a -eq $b)
    }
    if ($same) {
        Write-Host "   = $f (変更なし)"
    } else {
        Copy-Item -Path $src -Destination $dst -Force
        Write-Host "   o $f" -ForegroundColor Green
        $copied++
    }
}
if ($copied -eq 0) { Write-Host '   (新しく反映するファイルはありませんでした)' }

Set-Location $RepoDir

# ---- 2. 検査: バージョンとキャッシュ名の整合 ------------------------
Write-Host ''
Write-Host '▼ 検査'

$indexText = Get-Content -Raw -Encoding UTF8 'index.html'
$swText    = Get-Content -Raw -Encoding UTF8 'sw.js'

$verMatch   = [regex]::Match($indexText, 'const\s+APP_VERSION\s*=\s*"([^"]+)"')
$updMatch   = [regex]::Match($indexText, 'const\s+LAST_UPDATED\s*=\s*"([^"]+)"')
$cacheMatch = [regex]::Match($swText,    "const\s+CACHE\s*=\s*'([^']+)'")

if (-not $verMatch.Success -or -not $cacheMatch.Success) {
    Write-Host '   x index.html / sw.js からバージョンを読み取れませんでした' -ForegroundColor Red
    exit 1
}
$ver   = $verMatch.Groups[1].Value
$upd   = if ($updMatch.Success) { $updMatch.Groups[1].Value } else { '' }
$cache = $cacheMatch.Groups[1].Value

Write-Host "   アプリ版     : $ver  ($upd)"
Write-Host "   SWキャッシュ : $cache"

if ($cache -notlike "*$ver*") {
    Write-Host "   x sw.js の CACHE 名にアプリ版 $ver が入っていません。" -ForegroundColor Red
    Write-Host '     上げ忘れるとホーム画面アプリが古いまま残ります。sw.js を直してください。' -ForegroundColor Red
    exit 1
}
Write-Host '   o キャッシュ名は最新版に一致' -ForegroundColor Green

# JSONの構文チェック（壊れたJSONを公開しないため）
foreach ($j in (Get-ChildItem -Filter *.json -File)) {
    try {
        Get-Content -Raw -Encoding UTF8 $j.FullName | ConvertFrom-Json | Out-Null
    } catch {
        Write-Host "   x $($j.Name) が壊れています" -ForegroundColor Red
        exit 1
    }
}
Write-Host '   o JSONの構文は正常' -ForegroundColor Green

# ---- 3. push --------------------------------------------------------
Write-Host ''
$status = git status --porcelain
if ([string]::IsNullOrWhiteSpace($status)) {
    Write-Host '▼ 変更なし。pushする内容はありません。'
    exit 0
}
Write-Host '▼ 変更内容'
git status --short

if ($DryRun) {
    Write-Host ''
    Write-Host '(-DryRun 指定のため push しませんでした)' -ForegroundColor Yellow
    exit 0
}

if ([string]::IsNullOrWhiteSpace($Message)) { $Message = "v$ver ($upd)" }
git add -A
git commit -m $Message
git push origin $Branch

Write-Host ''
Write-Host "o 完了: v$ver を公開しました" -ForegroundColor Green
Write-Host '  反映まで1分ほどかかります。スマホはアイコンから開き直すと自動で更新されます。'
Write-Host '  変わらないときは アプリ内 設定 → 「最新版に更新する」を押してください。'
