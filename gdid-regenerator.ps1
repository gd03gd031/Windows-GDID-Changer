Write-Host "[*] Stopping Identity Service..."

$identityService = Get-Service wlidsvc

if ($identityService.Status -eq "Running") {
    net stop wlidsvc | Out-Null
}

$identityPath = "Registry::HKEY_USERS\.DEFAULT\Software\Microsoft\IdentityCRL"

$currentLid = (Get-ItemProperty "$identityPath\ExtendedProperties").LID

Write-Host "`nCurrent GDID: " -NoNewline
Write-Host "g:$([Convert]::ToUInt64($currentLid,16))" -ForegroundColor Yellow

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
                Write-Host "g:$([Convert]::ToUInt64($newLid,16))" -ForegroundColor Green

                Write-Host "`n[+] Complete. New GDID received from device registration service."

                Write-Host "`n[!] Note: For the strongest separation, change relevant hardware configuration before forcing a new GDID."
                Write-Host "    Device association can still be recreated from existing hardware identifiers and machine attributes."

                exit
            }
        }
        catch {}
    }

    Write-Host "`n`n[!] Timed out waiting for a new GDID." -ForegroundColor Yellow
