$ErrorActionPreference = "Stop"

$AppName = "PortalKeepalive"
# Stamped from the git tag by the release workflow; "dev" builds skip the update check
$AppVersion = "dev"
$Repo = "promidal/TOGU-Auto-Login"
# Machine-wide (not %APPDATA%): the task runs as SYSTEM at boot, before any user logs on
$BaseDir = Join-Path $env:ProgramData $AppName
$ConfigFile = Join-Path $BaseDir "config.json"
$PassFile = Join-Path $BaseDir "pass.enc"
$TokenFile = Join-Path $BaseDir "token.txt"
$LogFile = Join-Path $BaseDir "portal.log"
# A keepalive line every minute is about 30 MB a year; keep this file plus one previous (portal.log.1)
$LogMaxBytes = 1MB
# Present while the portal rejects the saved password; keepalive stops trying until new credentials are entered
$BadCredsFile = Join-Path $BaseDir "bad-credentials"
$UpdateCheckFile = Join-Path $BaseDir "update-check.json"
# SYSTEM has no desktop; it leaves these for the logon task ("notify" mode) to show once in the user's session
$BadCredsShownFile = Join-Path $BaseDir "bad-credentials-shown"
$UpdatePendingFile = Join-Path $BaseDir "update-pending.json"

function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$ts $msg"
    if (-not (Test-Path $BaseDir)) { New-Item -ItemType Directory -Path $BaseDir | Out-Null }
    try {
        if ((Test-Path $LogFile) -and (Get-Item $LogFile).Length -ge $LogMaxBytes) { Move-Item $LogFile "$LogFile.1" -Force }
    } catch {}  # a failed rotation must not stop the keepalive
    Add-Content -Path $LogFile -Value $line
    Write-Host $line
}

function Load-Config {
    if (Test-Path $ConfigFile) {
        try { return (Get-Content $ConfigFile -Raw | ConvertFrom-Json) } catch { return $null }
    }
    return $null
}

function Test-Credentials {
    $cfg = Load-Config
    return ($cfg -and $cfg.Username -and (Test-Path $PassFile))
}

# LocalMachine scope so SYSTEM (boot) and the user (password change) both read the same file
# shortcut: any local user can decrypt it, fine for a personal PC; use a per-user task if that matters
function Protect-Text($text) {
    Add-Type -AssemblyName System.Security
    [Convert]::ToBase64String([Security.Cryptography.ProtectedData]::Protect([Text.Encoding]::UTF8.GetBytes($text), $null, "LocalMachine"))
}

function Unprotect-Text($b64) {
    Add-Type -AssemblyName System.Security
    [Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect([Convert]::FromBase64String($b64), $null, "LocalMachine"))
}

function Get-Credentials($Prompt = $false) {
    if ($Prompt -or -not (Test-Credentials)) {
        if (-not (Test-Path $BaseDir)) { New-Item -ItemType Directory -Path $BaseDir | Out-Null }
        do {
            $user = (Read-Host "Kullanici adi (kurumsal e-posta, ornek: isminiz.soyisminizXXXX@gop.edu.tr)").Trim()
        } while (-not $user)
        $secure = Read-Host "Parola" -AsSecureString
        $enc = Protect-Text ([pscredential]::new("x", $secure).GetNetworkCredential().Password)
        Set-Content -Path $PassFile -Value $enc
        $cfg = @{ Username = $user }
        $cfg | ConvertTo-Json | Set-Content -Path $ConfigFile
        Remove-Item $BadCredsFile, $BadCredsShownFile -ErrorAction SilentlyContinue
        Write-Log "Credentials saved"
    }
    $pass = Unprotect-Text (Get-Content $PassFile -Raw).Trim()
    $cfg = Load-Config
    return @{ Username = $cfg.Username; Password = $pass }
}

function Invoke-CurlGet($url, $outFile) {
    $args = @("-sS", "-k", "--max-time", "15", "-A", "Mozilla/5.0", "-o", $outFile, "-w", "%{http_code}", $url)
    $code = & curl.exe @args
    if ($LASTEXITCODE -ne 0 -or "$code".Trim() -eq "000") {
        throw "curl.exe failed (exit=$LASTEXITCODE, http=$code) for $url"
    }
    return $code
}

function Parse-Input($html, $name) {
    $patterns = @(
        "name=`"$name`"\s+value=`"([^`"]*)`"",
        "value=`"([^`"]*)`"[^>]*name=`"$name`""
    )
    foreach ($p in $patterns) {
        $m = [regex]::Match($html, $p, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($m.Success) { return $m.Groups[1].Value }
    }
    return ""
}

function Parse-Token($html) {
    $m = [regex]::Match($html, "keepalive\?([0-9a-fA-F]+)")
    if ($m.Success) { return $m.Groups[1].Value }
    $m = [regex]::Match($html, "logout\?([0-9a-fA-F]+)")
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

# Windows' own captive check: the portal intercepts it until we log in
function Test-Internet {
    $out = & curl.exe -s --max-time 5 -H "Cache-Control: no-cache" "http://www.msftconnecttest.com/connecttest.txt"
    return ($out -eq "Microsoft Connect Test")
}

function Test-PortalReachable {
    $code = & curl.exe -s -k --max-time 5 -o NUL -w "%{http_code}" "https://denetim.gop.edu.tr/login?0"
    return ($LASTEXITCODE -eq 0 -and $code -and "$code".Trim() -ne "000")
}

function Test-LoginPage($html) {
    return ($html -match 'name="username"') -or ($html -match "Giriş Başarısız")
}

function Login($creds) {
    if (-not (Test-Path $BaseDir)) { New-Item -ItemType Directory -Path $BaseDir | Out-Null }
    $tmp = [System.IO.Path]::GetTempFileName()
    $postTmp = [System.IO.Path]::GetTempFileName()
    try {
        $code = Invoke-CurlGet "https://denetim.gop.edu.tr/login?0" $tmp
        $html = Get-Content $tmp -Raw
        $magic = Parse-Input $html "magic"
        $redir = Parse-Input $html "4Tredir"
        if (-not $redir) { $redir = "https://denetim.gop.edu.tr/login?0" }
        $body = "4Tredir=$([System.Uri]::EscapeDataString($redir))&magic=$([System.Uri]::EscapeDataString($magic))&username=$([System.Uri]::EscapeDataString($creds.Username))&password=$([System.Uri]::EscapeDataString($creds.Password))"
        $code = & curl.exe -sS -k --max-time 15 -A "Mozilla/5.0" -o $postTmp -w "%{http_code}" -d $body "https://denetim.gop.edu.tr/"
        if ($LASTEXITCODE -ne 0 -or "$code".Trim() -eq "000") {
            throw "curl.exe login POST failed (exit=$LASTEXITCODE, http=$code)"
        }
        $resp = Get-Content $postTmp -Raw
        if ($resp -match "Giriş Başarısız" -or $resp -match "Kullanıcı adı / parola hatalı") {
            Set-Content -Path $BadCredsFile -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            throw "Login failed: bad credentials"
        }
        if (Test-LoginPage $resp) {
            throw "Login failed: still on login page"
        }
        $token = Parse-Token $resp
        if (-not $token) { throw "Login succeeded but no token found" }
        Set-Content -Path $TokenFile -Value $token
        Write-Log "Login OK, token=$token"
        return $token
    } finally {
        Remove-Item $tmp, $postTmp -ErrorAction SilentlyContinue
    }
}

function Keepalive-Once {
    $creds = Get-Credentials
    $token = $null
    if (Test-Path $TokenFile) { $token = (Get-Content $TokenFile).Trim() }
    if (-not $token) {
        if (-not (Test-PortalReachable) -and (Test-Internet)) {
            Write-Log "No token and off campus (portal unreachable, internet works); skipping"
            return
        }
        Write-Log "No token; attempting login"
        Login $creds | Out-Null
        return
    }

    $tmp = [System.IO.Path]::GetTempFileName()
    try {
        try {
            $code = Invoke-CurlGet "https://denetim.gop.edu.tr/keepalive?$token" $tmp
            $html = Get-Content $tmp -Raw
        } catch {
            if (-not (Test-PortalReachable) -and (Test-Internet)) {
                Write-Log "Keepalive failed ($_) and portal unreachable while internet works, off campus; dropping token"
                Remove-Item $TokenFile -ErrorAction SilentlyContinue
                return
            }
            Write-Log "Keepalive request failed ($_), attempting re-login"
            Login $creds | Out-Null
            return
        }
        if (Test-LoginPage $html) {
            Write-Log "Session expired, re-login"
            Login $creds | Out-Null
            return
        }
        if ([string]::IsNullOrWhiteSpace($html)) {
            if (-not (Test-PortalReachable) -and (Test-Internet)) {
                Write-Log "Empty keepalive response and portal unreachable while internet works, off campus; dropping token"
                Remove-Item $TokenFile -ErrorAction SilentlyContinue
                return
            }
            Write-Log "Empty response, attempting re-login"
            Login $creds | Out-Null
            return
        }
        $newToken = Parse-Token $html
        if ($newToken -and $newToken -ne $token) {
            Set-Content -Path $TokenFile -Value $newToken
            $token = $newToken
        }
        Write-Log "Keepalive OK, token=$token"
    } finally {
        Remove-Item $tmp -ErrorAction SilentlyContinue
    }
}

# At most once a day (GitHub allows 60 unauthenticated requests/hour); each new release is announced once
function Check-Update {
    if ($AppVersion -eq "dev") { return }
    $state = $null
    if (Test-Path $UpdateCheckFile) {
        try { $state = Get-Content $UpdateCheckFile -Raw | ConvertFrom-Json } catch {}
    }
    if ($state -and $state.LastCheck -and ((Get-Date) - [datetime]$state.LastCheck).TotalHours -lt 24) { return }

    # Behind the captive portal this returns the portal's HTML, ConvertFrom-Json throws and we try again next run
    $json = & curl.exe -s --max-time 10 -A "PortalKeepalive" "https://api.github.com/repos/$Repo/releases/latest"
    try { $rel = ($json | Out-String) | ConvertFrom-Json } catch { return }
    if (-not $rel.tag_name) { return }

    $notified = $null
    if ($state) { $notified = $state.Notified }
    @{ LastCheck = (Get-Date).ToString("o"); Notified = $notified } | ConvertTo-Json | Set-Content -Path $UpdateCheckFile

    try {
        $latest = [version]($rel.tag_name.TrimStart("v"))
        $current = [version]$AppVersion
    } catch { return }
    if ($latest -le $current -or $notified -eq $rel.tag_name) { return }

    Write-Log "Update available: $($rel.tag_name) (installed $AppVersion)"
    @{ LastCheck = (Get-Date).ToString("o"); Notified = $rel.tag_name } | ConvertTo-Json | Set-Content -Path $UpdateCheckFile
    @{ Tag = $rel.tag_name; Url = $rel.html_url } | ConvertTo-Json | Set-Content -Path $UpdatePendingFile
}

function Show-UpdateNotice($tag, $url) {
    Add-Type -AssemblyName System.Windows.Forms
    $answer = [System.Windows.Forms.MessageBox]::Show(
        "PortalKeepalive için yeni sürüm yayınlandı: $tag (kurulu sürüm: $AppVersion).`n`nİndirme sayfası açılsın mı? Yeni yükleyiciyi çalıştırmanız yeterli.",
        "PortalKeepalive - Güncelleme",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Information)
    if ($answer -eq [System.Windows.Forms.DialogResult]::Yes -and $url -match '^https://github\.com/') {
        Start-Process $url
    }
}

function Retry($action, $attempts = 3, $delays = @(5, 10, 20)) {
    for ($i = 0; $i -lt $attempts; $i++) {
        try {
            & $action | Out-Null
            return $true
        } catch {
            Write-Log "Attempt $($i+1)/$attempts failed: $_"
            # Retrying a rejected password only risks locking the account
            if (Test-Path $BadCredsFile) { break }
            if ($i -lt ($attempts - 1)) { Start-Sleep -Seconds $delays[$i] }
        }
    }
    Write-Log "All attempts failed"
    return $false
}

if (-not (Test-Path $BaseDir)) { New-Item -ItemType Directory -Path $BaseDir | Out-Null }

$mode = "keepalive"
if ($args.Count -gt 0) { $mode = $args[0] }

if ($mode -eq "notify") {
    # Logon task, user session: show what the SYSTEM keepalive could not
    Add-Type -AssemblyName System.Windows.Forms
    if ((Test-Path $BadCredsFile) -and -not (Test-Path $BadCredsShownFile)) {
        Set-Content -Path $BadCredsShownFile -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        [System.Windows.Forms.MessageBox]::Show(
            "Portal şifrenizi kabul etmedi; şifreniz değişmiş olabilir.`n`nYeni şifrenizi girmek için Başlat menüsünden 'PortalKeepalive - Şifreyi Değiştir' kısayolunu açın.`n`nO zamana kadar otomatik giriş durduruldu.",
            "PortalKeepalive",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
    }
    if (Test-Path $UpdatePendingFile) {
        $u = Get-Content $UpdatePendingFile -Raw | ConvertFrom-Json
        Remove-Item $UpdatePendingFile
        Show-UpdateNotice $u.Tag $u.Url
    }
} elseif ($mode -eq "login") {
    # Always ask: this is how the user changes the saved username/password
    # (installer, or the "Sifreyi Degistir" Start menu shortcut)
    $ok = $false
    for ($i = 0; $i -lt 3 -and -not $ok; $i++) {
        $creds = Get-Credentials -Prompt $true
        $ok = Retry { Login $creds }
        if ($ok -or -not (Test-Path $BadCredsFile)) { break }
        Write-Host "Kullanici adi veya parola hatali, tekrar deneyin." -ForegroundColor Yellow
    }
    if ($ok) {
        Write-Host "Giris basarili, bilgiler kaydedildi." -ForegroundColor Green
    } elseif (Test-Path $BadCredsFile) {
        Write-Host "Giris yapilamadi: kullanici adi veya parola hatali." -ForegroundColor Red
    } else {
        Write-Host "Bilgiler kaydedildi ama su an portala giris yapilamadi (kampus agi disinda olabilirsiniz). Kampus agina baglaninca otomatik giris yapilacak." -ForegroundColor Yellow
    }
    Read-Host "Kapatmak icin Enter'a basin" | Out-Null
} else {
    # Runs hidden from Task Scheduler: Read-Host would hang forever, so never prompt here
    if (-not (Test-Credentials)) {
        Write-Log "No saved credentials; run the installer (or: PortalKeepalive.ps1 login)"
        exit 1
    }
    if (Test-Path $BadCredsFile) {
        Write-Log "Skipping keepalive: bad-credentials flag is set"
        exit 1  # already told the user; wait for new credentials
    }
    Retry { Keepalive-Once } | Out-Null
    try { Check-Update } catch { Write-Log "Update check failed: $_" }
}
