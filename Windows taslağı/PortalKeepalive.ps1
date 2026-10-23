$ErrorActionPreference = "Stop"

$AppName = "PortalKeepalive"
$BaseDir = Join-Path $env:APPDATA $AppName
$ConfigFile = Join-Path $BaseDir "config.json"
$PassFile = Join-Path $BaseDir "pass.enc"
$TokenFile = Join-Path $BaseDir "token.txt"
$LogFile = Join-Path $BaseDir "portal.log"

function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$ts $msg"
    if (-not (Test-Path $BaseDir)) { New-Item -ItemType Directory -Path $BaseDir | Out-Null }
    Add-Content -Path $LogFile -Value $line
    Write-Host $line
}

function Load-Config {
    if (Test-Path $ConfigFile) {
        try { return (Get-Content $ConfigFile -Raw | ConvertFrom-Json) } catch { return $null }
    }
    return $null
}

function Get-Credentials {
    $cfg = Load-Config
    if (-not $cfg -or -not $cfg.Username -or -not (Test-Path $PassFile)) {
        if (-not (Test-Path $BaseDir)) { New-Item -ItemType Directory -Path $BaseDir | Out-Null }
        $user = Read-Host "Kullanici adi (kurumsal e-posta, ornek: isminiz.soyisminizXXXX@gop.edu.tr)"
        $secure = Read-Host "Parola" -AsSecureString
        $enc = $secure | ConvertFrom-SecureString
        Set-Content -Path $PassFile -Value $enc
        $cfg = @{ Username = $user }
        $cfg | ConvertTo-Json | Set-Content -Path $ConfigFile
        Write-Log "Credentials saved"
    }
    $secure = Get-Content $PassFile | ConvertTo-SecureString
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    $pass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    $cfg = Load-Config
    return @{ Username = $cfg.Username; Password = $pass }
}

function Invoke-CurlGet($url, $outFile) {
    $args = @("-sS", "-k", "--max-time", "15", "-A", "Mozilla/5.0", "-o", $outFile, "-w", "%{http_code}", $url)
    $code = & curl.exe @args
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

function Test-LoginPage($html) {
    return ($html -match 'name="username"') -or ($html -match "Giriş Başarısız")
}

function Login($creds) {
    if (-not (Test-Path $BaseDir)) { New-Item -ItemType Directory -Path $BaseDir | Out-Null }
    $tmp = [System.IO.Path]::GetTempFileName()
    $code = Invoke-CurlGet "https://denetim.gop.edu.tr/login?0" $tmp
    $html = Get-Content $tmp -Raw
    $magic = Parse-Input $html "magic"
    $redir = Parse-Input $html "4Tredir"
    if (-not $redir) { $redir = "https://denetim.gop.edu.tr/login?0" }
    $postTmp = [System.IO.Path]::GetTempFileName()
    $body = "4Tredir=$([System.Uri]::EscapeDataString($redir))&magic=$([System.Uri]::EscapeDataString($magic))&username=$([System.Uri]::EscapeDataString($creds.Username))&password=$([System.Uri]::EscapeDataString($creds.Password))"
    $code = & curl.exe -sS -k --max-time 15 -A "Mozilla/5.0" -o $postTmp -w "%{http_code}" -d $body "https://denetim.gop.edu.tr/"
    $resp = Get-Content $postTmp -Raw
    if ($resp -match "Giriş Başarısız" -or $resp -match "Kullanıcı adı / parola hatalı") {
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
}

function Keepalive-Once {
    $creds = Get-Credentials
    $token = $null
    if (Test-Path $TokenFile) { $token = (Get-Content $TokenFile).Trim() }
    if (-not $token) { Login $creds | Out-Null; return }

    $tmp = [System.IO.Path]::GetTempFileName()
    try {
        $code = Invoke-CurlGet "https://denetim.gop.edu.tr/keepalive?$token" $tmp
        $html = Get-Content $tmp -Raw
    } catch {
        Write-Log "Keepalive request failed ($_), attempting re-login"
        Login $creds | Out-Null
        return
    }
    if (Test-LoginPage $html) {
        Write-Log "Session expired, re-login"
        Login $creds | Out-Null
        return
    }
    # empty reply handling: if file empty
    if ([string]::IsNullOrWhiteSpace($html)) {
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
}

function Retry($action, $attempts = 3, $delays = @(5, 10, 20)) {
    for ($i = 0; $i -lt $attempts; $i++) {
        try {
            & $action
            return $true
        } catch {
            Write-Log "Attempt $($i+1)/$attempts failed: $_"
            if ($i -lt ($attempts - 1)) { Start-Sleep -Seconds $delays[$i] }
        }
    }
    Write-Log "All attempts failed"
    return $false
}

if (-not (Test-Path $BaseDir)) { New-Item -ItemType Directory -Path $BaseDir | Out-Null }

$mode = "keepalive"
if ($args.Count -gt 0) { $mode = $args[0] }

if ($mode -eq "login") {
    $creds = Get-Credentials
    Retry { Login $creds } | Out-Null
} else {
    Retry { Keepalive-Once } | Out-Null
}
