# =====================================================================
#  TOEIC 単語トレーナー デプロイスクリプト（Windows PowerShell 版）
#
#  【重要・文字コードについて】
#    このファイルは必ず「UTF-8 (BOM付き)」で保存すること。
#    Windows PowerShell 5.1 は BOM の無い UTF-8 ファイルを
#    Shift-JIS として読むため、日本語コメントが文字化けし、
#    「式またはステートメントのトークン ')' を使用できません」等の
#    構文エラーで起動しなくなる。
#    メモ帳なら「UTF-8 (BOM付き)」、VS Codeなら右下の文字コード表示から
#    「Save with Encoding → UTF-8 with BOM」を選ぶ。
#  ファイル最終更新日時: 2026-07-30 11:30 (JST)
#  バージョン: 1.1.1
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
#
#  【v1.1.0 での変更（重要）】
#    ① 同名ファイルを何度もダウンロードすると、Windowsのブラウザは
#       「index (1).html」「index (2).html」のように連番を付けて保存する。
#       素直に index.html をコピーすると "最初にダウンロードした古い版" を
#       コピーしてしまい、更新したつもりが反映されない事故が起きた。
#       → 連番付きも含めて拾い、更新日時が最も新しいものを採用するようにした。
#         連番付きを採用したときは、どのファイルを使ったか画面に出す。
#    ② コピー後、直前のコミット(HEAD)の APP_VERSION と比べて版が下がって
#       いたら警告して中止する（古い版で上書きする事故を止めるため）。
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

# ---------------------------------------------------------------------
#  ダウンロードフォルダから「本当に使うべきファイル」を選ぶ
#  index.html / index (1).html / index (2).html … を全部拾って
#  更新日時が最も新しいものを返す。
# ---------------------------------------------------------------------
function Resolve-Source {
    param([string]$Dir, [string]$Name)
    $base = [IO.Path]::GetFileNameWithoutExtension($Name)
    $ext  = [IO.Path]::GetExtension($Name)
    $re   = '^' + [regex]::Escape($base) + '( \(\d+\))?' + [regex]::Escape($ext) + '$'
    Get-ChildItem -LiteralPath $Dir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match $re } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

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
    $srcItem = Resolve-Source -Dir $SrcDir -Name $f
    if ($null -eq $srcItem) { continue }
    $src = $srcItem.FullName
    $dst = Join-Path $RepoDir $f

    # 連番付き（index (1).html など）を採用したときは、必ず知らせる
    $note = ''
    if ($srcItem.Name -ne $f) { $note = "  <- $($srcItem.Name) を使用" }

    # 中身が同じならスキップ（無駄なコミットを作らない）
    $same = $false
    if (Test-Path $dst) {
        $a = (Get-FileHash $src -Algorithm SHA256).Hash
        $b = (Get-FileHash $dst -Algorithm SHA256).Hash
        $same = ($a -eq $b)
    }
    if ($same) {
        Write-Host "   = $f (変更なし)$note"
    } else {
        Copy-Item -LiteralPath $src -Destination $dst -Force
        if ($note) { Write-Host "   o $f$note" -ForegroundColor Yellow }
        else       { Write-Host "   o $f"      -ForegroundColor Green }
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

# 直前のコミットより版が下がっていないか（古いファイルで上書きする事故の検知）
$prev = git show HEAD:index.html 2>$null
if ($LASTEXITCODE -eq 0 -and $prev) {
    $pm = [regex]::Match(($prev -join "`n"), 'const\s+APP_VERSION\s*=\s*"([^"]+)"')
    if ($pm.Success) {
        $prevVer = $pm.Groups[1].Value
        try {
            if ([version]$ver -lt [version]$prevVer) {
                Write-Host "   x 版が下がっています（$prevVer -> $ver）。" -ForegroundColor Red
                Write-Host '     古いファイルをコピーした可能性があります。' -ForegroundColor Red
                Write-Host '     ダウンロードフォルダに古い同名ファイルが残っていないか確認してください。' -ForegroundColor Red
                exit 1
            } elseif ([version]$ver -eq [version]$prevVer) {
                Write-Host "   - 版は据え置き（$prevVer）" -ForegroundColor DarkGray
            } else {
                Write-Host "   o 版が上がりました（$prevVer -> $ver）" -ForegroundColor Green
            }
        } catch { }
    }
}

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
