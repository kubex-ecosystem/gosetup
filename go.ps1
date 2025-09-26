# PowerShell script to install, update, or remove Go, mirroring the robustness of the bash version.

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false, Position = 0)]
    [ValidateSet('install', 'update', 'remove', 'check', 'help')]
    [string]$Command = "install",

    [Parameter(Mandatory = $false, Position = 1)]
    [string]$Version = "latest"
)

# --- Global Variables & Initial Setup ---
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue' # We will use custom progress bars

# Temporary directory for downloads, cleaned up at the end.
$TempDir = New-Item -ItemType Directory -Path (Join-Path $env:TEMP ([System.Guid]::NewGuid().ToString()))
$GoRootPath = Join-Path $env:USERPROFILE ".go"
$GoPath = Join-Path $env:USERPROFILE "go"

# --- Utility Functions ---

function Show-Help {
    Write-Output @"
NAME:
    go.ps1 - A tool to easily install, update, or uninstall Go on Windows.

USAGE:
    .\go.ps1 [COMMAND] [ARGUMENTS]

COMMANDS:
    install [version]   Installs a specific Go version (e.g., '1.21.5' or '1.21'). Defaults to 'latest'.
    update              Updates to the latest stable version of Go.
    remove              Uninstalls Go from your system.
    check [version]     Checks if a specific version is installed. Defaults to 'latest'.
    help                Prints this help message.

EXAMPLES:
    .\go.ps1 install
    .\go.ps1 install 1.21.5
    .\go.ps1 update
"@
}

function Get-PlatformInfo {
    $os = "windows"
    $arch = switch ($env:PROCESSOR_ARCHITECTURE) {
        "AMD64" { "amd64" }
        "ARM64" { "arm64" }
        default { throw "Unsupported architecture: $env:PROCESSOR_ARCHITECTURE" }
    }
    return "$os-$arch"
}

function Get-InstalledGoVersion {
    $goExecutable = Join-Path $GoRootPath "bin/go.exe"
    if (Test-Path $goExecutable) {
        try {
            $versionOutput = & $goExecutable version
            if ($versionOutput -match "go(\d+\.\d+(\.\d+)?)") {
                return $Matches[1]
            }
        }
        catch {
            # Could not run `go version`, so no version is "installed"
        }
    }
    return $null
}

function Get-ShellProfilePath {
    if ($PROFILE) {
        if (-not (Test-Path $PROFILE)) {
            New-Item -Path $PROFILE -ItemType File -Force | Out-Null
        }
        return $PROFILE
    }
    throw "Could not determine PowerShell profile path."
}


# --- Core Logic Functions ---

function Find-GoVersionInfo {
    param(
        [string]$VersionToFind,
        [string]$Platform
    )

    $goApiUrl = "https://go.dev/dl/?mode=json"
    Write-Host "Fetching available Go versions for $Platform..."
    try {
        $versionsJson = Invoke-RestMethod -Uri $goApiUrl
    }
    catch {
        throw "Error: Failed to fetch Go versions from API. $_"
    }

    $os, $arch = $Platform.Split('-')

    $versionInfo = $versionsJson | ForEach-Object {
        if (($VersionToFind -eq 'latest' -and $_.stable) -or ($_.version -like "go$VersionToFind*")) {
            $file = $_.files | Where-Object { $_.os -eq $os -and $_.arch -eq $arch -and $_.kind -eq 'archive' }
            if ($file) {
                return [pscustomobject]@{
                    Version  = $_.version
                    Filename = $file.filename
                    Sha256   = $file.sha256
                }
            }
        }
    } | Select-Object -First 1

    if (-not $versionInfo) {
        throw "Error: Could not find Go version '$VersionToFind' for platform '$Platform'."
    }

    return $versionInfo
}

function Remove-Go {
    $installedVersion = Get-InstalledGoVersion
    if (-not $installedVersion) {
        Write-Host "Go is not installed in $GoRootPath. Nothing to remove." -ForegroundColor Yellow
        return
    }

    Write-Host "Removing Go version $installedVersion from $GoRootPath" -ForegroundColor Red

    if (Test-Path $GoRootPath) {
        if ($PSCmdlet.ShouldProcess($GoRootPath, "Remove Directory")) {
            Remove-Item -Recurse -Force -Path $GoRootPath
        }
    }

    $shellProfile = Get-ShellProfilePath
    if (Test-Path $shellProfile) {
        Write-Host "Creating a backup of your shell profile to ${shellProfile}.bak"
        Copy-Item -Path $shellProfile -Destination "${shellProfile}.bak" -Force

        Write-Host "Removing Go environment variables from $shellProfile"
        $content = Get-Content $shellProfile -Raw
        $newContent = $content -replace '(?ms)# GoLang ENV.*?# End GoLang ENV\s*'
        if ($newContent.Length -lt $content.Length) {
            Set-Content -Path $shellProfile -Value $newContent.Trim()
        }
    }

    Write-Host "Go uninstalled successfully!" -ForegroundColor Green
    Write-Host "Please restart your shell or run: . `"$shellProfile`"" -ForegroundColor Yellow
}

function Install-Go {
    param(
        [string]$VersionToInstall,
        [string]$Platform
    )

    # --- Check if the requested version is already installed ---
    $currentVersion = Get-InstalledGoVersion
    $targetVersionStr = $VersionToInstall
    if ($targetVersionStr -eq 'latest') {
        $targetVersionStr = (Find-GoVersionInfo -VersionToFind 'latest' -Platform $Platform).Version.Replace('go', '')
    }

    if ($currentVersion -and $currentVersion -eq $targetVersionStr) {
        Write-Host "Go version $currentVersion is already installed. Nothing to do." -ForegroundColor Green
        return
    }
    # --- End of check ---

    # --- Restore from backup if available ---
    if ($VersionToInstall -ne 'latest') {
        $targetBackupDir = "${GoRootPath}-$targetVersionStr"
        if (Test-Path $targetBackupDir) {
            Write-Host "Found existing backup for Go version $targetVersionStr." -ForegroundColor Green
            Write-Host "Restoring from $targetBackupDir..."

            if (Test-Path $GoRootPath) {
                $currentBackupVersion = Get-InstalledGoVersion
                if ($currentBackupVersion -and $currentBackupVersion -ne $targetVersionStr) {
                    $currentBackupDir = "${GoRootPath}-${currentBackupVersion}"
                    Write-Host "Moving current installation to $currentBackupDir..."
                    if (Test-Path $currentBackupDir) { Remove-Item -Recurse -Force -Path $currentBackupDir }
                    Move-Item -Path $GoRootPath -Destination $currentBackupDir
                }
            }

            Move-Item -Path $targetBackupDir -Destination $GoRootPath

            $shellProfile = Get-ShellProfilePath
            $content = Get-Content $shellProfile -Raw
            if (-not ($content -match "# GoLang ENV")) {
                Update-ShellProfile -GoRootPath $GoRootPath -GoPath $GoPath -ShellProfile $shellProfile
            }

            Write-Host "Go version $targetVersionStr restored successfully!" -ForegroundColor Green
            Write-Host "Please restart your shell or run: . `"$shellProfile`"" -ForegroundColor Yellow
            return
        }
    }
    # --- End of restore logic ---

    $versionInfo = Find-GoVersionInfo -VersionToFind $VersionToInstall -Platform $Platform
    $versionNumber = $versionInfo.Version.Replace('go', '')

    Write-Host "Downloading Go $($versionInfo.Version) ($($versionInfo.Filename))..." -ForegroundColor Cyan
    $downloadUrl = "https://dl.google.com/go/$($versionInfo.Filename)"
    $tempFilePath = Join-Path $TempDir $versionInfo.Filename

    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $tempFilePath -UseBasicParsing
    }
    catch {
        throw "Failed to download Go. $_"
    }

    Write-Host "Verifying checksum..."
    $calculatedSha = (Get-FileHash -Path $tempFilePath -Algorithm SHA256).Hash.ToLower()

    if ($calculatedSha -ne $versionInfo.Sha256) {
        throw "Error: Checksum mismatch! File is corrupt or has been tampered with."
    }
    Write-Host "Checksum verified."

    if (Test-Path $GoRootPath) {
        $currentVersion = Get-InstalledGoVersion
        if ($currentVersion) {
            $backupDir = "${GoRootPath}-${currentVersion}"
            Write-Host "Moving existing Go installation to $backupDir..."
            if (Test-Path $backupDir) { Remove-Item -Recurse -Force -Path $backupDir }
            Move-Item -Path $GoRootPath -Destination $backupDir
        }
        else {
            $backupDir = "$GoRootPath.bak"
            Write-Host "Moving existing Go installation to $backupDir..."
            if (Test-Path $backupDir) { Remove-Item -Recurse -Force -Path $backupDir }
            Move-Item -Path $GoRootPath -Destination $backupDir
        }
    }

    Write-Host "Extracting $($versionInfo.Filename) to $GoRootPath..."
    New-Item -ItemType Directory -Path $GoRootPath -Force | Out-Null
    Expand-Archive -Path $tempFilePath -DestinationPath $GoRootPath -Force

    # The extracted files are inside a 'go' folder, move them up.
    $extractedGoDir = Join-Path $GoRootPath "go"
    if (Test-Path $extractedGoDir) {
        Get-ChildItem -Path $extractedGoDir | Move-Item -Destination $GoRootPath
        Remove-Item -Recurse -Force -Path $extractedGoDir
    }

    New-Item -ItemType Directory -Path (Join-Path $GoPath "src") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $GoPath "pkg") -Force | Out-Null
function Update-ShellProfile {
    param(
        [string]$GoRootPath,
        [string]$GoPath,
        [string]$ShellProfile
    )

    # Remove old entries before adding new ones
    $content = Get-Content $ShellProfile -Raw
    $newContent = $content -replace '(?ms)# GoLang ENV.*?# End GoLang ENV\s*'
    Set-Content -Path $ShellProfile -Value $newContent.Trim()

    Write-Host "Updating shell profile: $ShellProfile"
    $envBlock = @"

# GoLang ENV
`$env:GOROOT = "$GoRootPath"
`$env:GOPATH = "$GoPath"
`$env:PATH = "`$env:PATH;`$env:GOROOT\bin;`$env:GOPATH\bin"
# End GoLang ENV
"@
    Add-Content -Path $ShellProfile -Value $envBlock
}

function Install-Go {
    param(
        [string]$VersionToInstall,
        [string]$Platform
    )
//...
    New-Item -ItemType Directory -Path (Join-Path $GoPath "bin") -Force | Out-Null

    $shellProfile = Get-ShellProfilePath
    Update-ShellProfile -GoRootPath $GoRootPath -GoPath $GoPath -ShellProfile $shellProfile

    Write-Host "Go $versionNumber installed successfully!" -ForegroundColor Green
    Write-Host "Please restart your shell or run: . `"$shellProfile`"" -ForegroundColor Yellow
}

function Check-Go {
    param(
        [string]$VersionToCheck,
        [string]$Platform
    )

    # First, validate that the version exists remotely.
    try {
        $remoteVersionInfo = Find-GoVersionInfo -VersionToFind $VersionToCheck -Platform $Platform
    }
    catch {
        Write-Host "The specified Go version '$VersionToCheck' is not a valid or available version." -ForegroundColor Red
        return $false
    }
    $remoteVersion = $remoteVersionInfo.Version.Replace('go', '')

    $currentVersion = Get-InstalledGoVersion
    if (-not $currentVersion) {
        Write-Host "Go is not installed, but version $remoteVersion is a valid version."
        return $false
    }

    Write-Host "Installed version: $currentVersion"
    Write-Host "Checked version:   $remoteVersion"

    if ($currentVersion -eq $remoteVersion) {
        Write-Host "Go version $remoteVersion is installed." -ForegroundColor Green
        return $true
    }
    else {
        Write-Host "Go version $remoteVersion is NOT installed. Current version is $currentVersion." -ForegroundColor Yellow
        return $false
    }
}


# --- Main Execution ---

try {
    $platform = Get-PlatformInfo

    switch ($Command) {
        "install" {
            $currentVersion = Get-InstalledGoVersion
            if ($currentVersion -and $Version -ne 'latest' -and $currentVersion -like "$Version*") {
                Write-Host "Go version $Version is already installed."
            }
            else {
                Install-Go -VersionToInstall $Version -Platform $platform
            }
        }
        "update" {
            $currentVersion = Get-InstalledGoVersion
            $latestVersionInfo = Find-GoVersionInfo -VersionToFind 'latest' -Platform $platform
            $latestVersion = $latestVersionInfo.Version.Replace('go', '')

            if ($currentVersion -and $currentVersion -eq $latestVersion) {
                Write-Host "You are already running the latest version of Go ($currentVersion)." -ForegroundColor Green
            }
            else {
                Write-Host "Updating Go from version $currentVersion to $latestVersion..."
                Install-Go -VersionToInstall "latest" -Platform $platform
            }
        }
        "remove" {
            Remove-Go
        }
        "check" {
            Check-Go -VersionToCheck $Version -Platform $platform
        }
        "help" {
            Show-Help
        }
        default {
            Write-Host "Invalid command. Use 'install', 'update', 'remove', 'check', or 'help'." -ForegroundColor Red
            Show-Help
        }
    }
}
catch {
    Write-Error "An unexpected error occurred: $_"
}
finally {
    # Cleanup the temporary directory
    if (Test-Path $TempDir) {
        Remove-Item -Recurse -Force -Path $TempDir
    }
}
