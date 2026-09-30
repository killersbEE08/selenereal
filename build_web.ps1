# Builds the Flutter web app and (optionally) deploys it to Cloudflare Pages.
#   .\build_web.ps1            -> build only (build\web)
#   .\build_web.ps1 -Deploy    -> build + wrangler pages deploy
# Public build values come from web.env (KEY=VALUE lines, not secret: they ship in the JS bundle).
param([switch]$Deploy, [string]$Branch = "main")
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$defines = @()
if (Test-Path web.env) {
  foreach ($line in Get-Content web.env) {
    $l = $line.Trim()
    if ($l -eq "" -or $l.StartsWith("#")) { continue }
    $k, $v = $l.Split("=", 2)
    if ($v) { $defines += "--dart-define=$($k.Trim())=$($v.Trim())" }
  }
}
if (-not ($defines -match "RECAPTCHA_SITE_KEY=")) { Write-Warning "RECAPTCHA_SITE_KEY missing in web.env: App Check will be off and enforced backend calls will fail." }

# --no-web-resources-cdn bundles CanvasKit locally (no runtime dependency on gstatic for the renderer).
flutter build web --release --no-web-resources-cdn @defines
if ($LASTEXITCODE -ne 0) { throw "flutter build web failed" }

# Legal pages are also served from the web domain.
Copy-Item hosting\privacy_policy.html, hosting\terms_of_use.html, hosting\delete_account.html build\web\ -Force

if ($Deploy) {
  # Run from build\web: from the project root wrangler would treat Firebase's functions\ folder
  # as Cloudflare Pages Functions and try to bundle it.
  Push-Location build\web
  try {
    npx wrangler pages deploy . --project-name selene-web --branch $Branch --commit-dirty=true
    if ($LASTEXITCODE -ne 0) { throw "wrangler deploy failed" }
  } finally { Pop-Location }
}
