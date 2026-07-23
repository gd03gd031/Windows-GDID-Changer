function Reset-PushNotifications-Service-Cache {
    param(
        [Parameter(Mandatory)]
        [string]$GDID
    )

    $pushRoot = "Registry::HKEY_USERS\.DEFAULT\Software\Microsoft\Windows\CurrentVersion\PushNotifications"

    $gdidKey = Join-Path $pushRoot $GDID
    if (Test-Path $gdidKey) {
        Remove-Item $gdidKey -Recurse -Force -ErrorAction SilentlyContinue
    }

    $deviceInfo = Join-Path $pushRoot "DeviceInfo"
    if (Test-Path $deviceInfo) {
        Remove-ItemProperty `
            -Path $deviceInfo `
            -Name "DeviceVersionRepresentation" `
            -ErrorAction SilentlyContinue
    }

    Write-Host "[*] Refreshing WpnService..."

    $svc = Get-Service WpnService -ErrorAction SilentlyContinue
    if ($svc) {
        if ($svc.Status -eq "Running") {
            net stop WpnService | Out-Null
        }

        net start WpnService | Out-Null
    }
}


$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[!] This script must be run as Administrator." -ForegroundColor Red
    exit 1
}

Write-Host "[*] Stopping Identity Service..."

$identityService = Get-Service wlidsvc

if ($identityService.Status -eq "Running") {
    net stop wlidsvc | Out-Null
}

$identityPath = "Registry::HKEY_USERS\.DEFAULT\Software\Microsoft\IdentityCRL"

$currentLid = (Get-ItemProperty "$identityPath\ExtendedProperties").LID

Write-Host "`nCurrent GDID: " -NoNewline
Write-Host "g:$([Convert]::ToUInt64($currentLid,16)) [$currentLid]" -ForegroundColor Yellow

Write-Host "`n[*] Forcing new device registration and GDID assignment..."

Get-ChildItem "$identityPath\Immersive\production\Token" | ForEach-Object {
    $tokenInfo = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue

    if ($tokenInfo.DeviceID -eq $currentLid) {
        Remove-Item $_.PSPath -Recurse -Force
    }
}

$systemDevicePath = "$identityPath\DeviceIdentities\production\S-1-5-18"

Remove-Item $systemDevicePath -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "[*] Starting Identity Service..."

if ((Get-Service wlidsvc).Status -ne "Running") {
    net start wlidsvc | Out-Null
}

Write-Host "[*] Waiting for new GDID..." -NoNewline

for ($attempt = 0; $attempt -lt 60; $attempt++) {
    Start-Sleep 2
    Write-Host "." -NoNewline

    try {
        $newLid = (Get-ItemProperty "$identityPath\ExtendedProperties" -ErrorAction Stop).LID

        if ($newLid -ne $currentLid) {

            Write-Host "`n`nNew GDID: " -NoNewline
            Write-Host "g:$([Convert]::ToUInt64($newLid,16)) [$newLid]" -ForegroundColor Green
            Write-Host "`n[+] Complete. New GDID received from device registration service."

            Reset-PushNotifications-Service-Cache -GDID $currentLid

            Write-Host "`n[!] Note: For the strongest separation, change relevant hardware configuration before forcing a new GDID."
            Write-Host "    Device association can still be recreated from existing hardware identifiers and machine attributes."

            exit
        }
    }
    catch {}
}

Write-Host "`n`n[!] Timed out waiting for a new GDID." -ForegroundColor Yellow
