$ErrorActionPreference = 'Stop'
$sharedPlanPath = '\\hercascloud\VERIFICACIONES HERCAS\Optimizaciones Hercas\Hercas - Plan de trabajo Anderson y tu.xlsx'
$stagedPlanPath = Join-Path $PSScriptRoot 'shared-plan-review.xlsx'
$expectedPlanHash = '2C41BCCB8DF90E9E4656BCE0089AC78FDA23E17F9EA9B06FEBAC2848A716C3A6'
$planStream = $null
$backupPath = $null
$originalBytes = $null
$writeStarted = $false
try {
    $replacementBytes = [System.IO.File]::ReadAllBytes($stagedPlanPath)
    $planStream = [System.IO.File]::Open($sharedPlanPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    $planHasher = [System.Security.Cryptography.SHA256]::Create()
    $currentPlanHash = [System.BitConverter]::ToString($planHasher.ComputeHash($planStream)).Replace('-', '')
    if ($currentPlanHash -ne $expectedPlanHash) { throw 'The shared plan changed. No write was performed. Read and reconcile the latest version.' }
    $planStream.Position = 0
    $planMemory = [System.IO.MemoryStream]::new()
    $planStream.CopyTo($planMemory)
    $originalBytes = $planMemory.ToArray()
    $planMemory.Dispose()
    $backupDirectory = Join-Path ([System.IO.Path]::GetDirectoryName($sharedPlanPath)) 'Respaldos del plan'
    [System.IO.Directory]::CreateDirectory($backupDirectory) | Out-Null
    $backupPath = Join-Path $backupDirectory ('Plan antes de corregir etapa 0 - ' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss-fff') + '.xlsx')
    $backupStream = [System.IO.File]::Open($backupPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try { $backupStream.Write($originalBytes, 0, $originalBytes.Length); $backupStream.Flush($true) } finally { $backupStream.Dispose() }
    $writeStarted = $true
    $planStream.Position = 0
    $planStream.Write($replacementBytes, 0, $replacementBytes.Length)
    $planStream.SetLength($replacementBytes.Length)
    $planStream.Flush($true)
    $planStream.Position = 0
    $savedHash = [System.BitConverter]::ToString($planHasher.ComputeHash($planStream)).Replace('-', '')
    $replacementHash = [System.BitConverter]::ToString($planHasher.ComputeHash($replacementBytes)).Replace('-', '')
    if ($savedHash -ne $replacementHash) { throw 'Saved content did not match the verified correction.' }
    Write-Output ('UPDATED: ' + $sharedPlanPath)
    Write-Output ('BACKUP: ' + $backupPath)
    Write-Output ('VERIFIED_SHA256: ' + $savedHash)
} catch {
    if ($writeStarted -and $null -ne $originalBytes -and $null -ne $planStream) {
        $planStream.Position = 0
        $planStream.Write($originalBytes, 0, $originalBytes.Length)
        $planStream.SetLength($originalBytes.Length)
        $planStream.Flush($true)
    }
    throw
} finally {
    if ($null -ne $planStream) { $planStream.Dispose() }
}
