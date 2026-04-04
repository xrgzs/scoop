<#
.DESCRIPTION
    Xiaoran System Scoop Deployment Script
.EXAMPLE
    # Default installation
    irm c.xrgzs.top/c/scoop | iex
    # Default installation (Win7+)
    (New-Object System.Net.WebClient).DownloadString('http://c.xrgzs.top/c/scoop') | iex
.EXAMPLE
    # Add specified software (multiple can be separated by spaces)
    iex "& { $(irm c.xrgzs.top/c/scoop) } -Append xrok"
.EXAMPLE
    # Slim installation (only install main program, git, aria2, add main and sdoog)
    iex "& { $(irm c.xrgzs.top/c/scoop) } -Slim"
.EXAMPLE
    # Set installation path (install to D drive)
    iex "& { $(irm c.xrgzs.top/c/scoop) } -ScoopDir 'D:\Scoop' -ScoopGlobalDir 'D:\ScoopGlobal'"
.EXAMPLE
    # Use Custom GitHub Proxy
    iex "& { $(irm c.xrgzs.top/c/scoop) } -GitHubProxy 'https://ghfast.top'"
#>

param (
    # Additional components to install
    [String]
    $Append,

    # Scoop installation directory
    [String]
    $ScoopDir,

    # Scoop global installation directory
    [String]
    $ScoopGlobalDir,

    # Scoop cache directory
    [String]
    $ScoopCacheDir,

    # GitHub Proxy
    [String]
    $GitHubProxy,

    # Slim installation
    [switch]
    $Slim
)

$ErrorActionPreference = 'Stop'

# Enable debugging
# Set-PSDebug -Trace 1


# Import utility functions
function Test-CommandAvailable {
    param (
        [Parameter(Mandatory = $True, Position = 0)]
        [String] $Command
    )
    return [Boolean](Get-Command $Command -ErrorAction SilentlyContinue)
}
function Test-IsAdministrator {
    return ([Security.Principal.WindowsPrincipal]`
            [Security.Principal.WindowsIdentity]::GetCurrent()`
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Update-Env {
    # Update PATH via registry
    $Env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')
}

# Import functional functions
function Add-ScoopBucketJob {
    param(
        [Parameter(Mandatory = $True, Position = 0)]
        [String] $Name,
        [Parameter(Position = 1)]
        [String] $Uri
    )
    return Start-Job -ScriptBlock {
        param($Name, $Uri, $SCOOP_DIR)
        scoop bucket rm $Name *>$null
        while (-not (Test-Path -Path "$SCOOP_DIR\buckets\$Name\bucket")) {
            Write-Host "Adding bucket: $Name ..." -ForegroundColor Cyan
            scoop bucket rm $Name *>$null
            if (-not $Uri) {
                Write-Host "Adding known bucket: $Name ..." -ForegroundColor Cyan
                scoop bucket add $Name >$null
            } else {
                Write-Host "Adding bucket: $Name from $Uri ..." -ForegroundColor Cyan
                scoop bucket add $Name "$Uri" >$null
            }
            if (-not (Test-Path -Path "$SCOOP_DIR\buckets\$Name\bucket")) {
                Write-Host "Failed to add bucket: $Name, trying again." -ForegroundColor Red
            }
        }
    } -ArgumentList $Name, $Uri, $SCOOP_DIR
}

function Get-Aria2 {
    Write-Host 'Downloading aria2c...'
    if ([System.Environment]::Is64BitOperatingSystem -or ($env:PROCESSOR_ARCHITECTURE -eq 'AMD64')) {
        $Aria2Url = 'http://url.xrgzs.top/aria2c64'
    } else {
        $Aria2Url = 'http://url.xrgzs.top/aria2c'
    }
    try {
        # Try using curl command
        Write-Host 'Try to use the curl method to download aria2c...'
        curl.exe -ksSL -o aria2c.exe "$Aria2Url"
        if ($LASTEXITCODE -ne 0) { throw }
    } catch {
        # Try WebClient method
        try {
            Write-Warning 'Failed to download aria2c using the curl method, now trying the WebClient method...'
            # Skip certificate check
            if ($PSVersionTable.PSVersion.Major -le 5) {
                Add-Type -TypeDefinition 'using System;using System.Net;using System.Net.Security;using System.Security.Cryptography.X509Certificates;public class TrustAllCertsPolicy : ICertificatePolicy {public bool CheckValidationResult(ServicePoint srvPoint, X509Certificate certificate, WebRequest request, int certificateProblem) {return true;}}'
                [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
            } else {
                [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
            }
            # .\xxx.exe cannot work, must be absolute path
            (New-Object System.Net.WebClient).DownloadFile($Aria2Url, "$PWD\aria2c.exe")
        } catch {
            # Try iwr method
            try {
                Write-Warning 'Failed to download aria2c using the WebClient method, now trying the iwr method...'
                # Win8.1+(PS 4+) Test OK, Win7 (PS 2) has no Iwr
                [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
                Invoke-WebRequest -Uri $Aria2Url -OutFile 'aria2c.exe'
            } catch {
                Write-Error 'All attempts to download aria2c have failed, please check the availability of your internet connection or download address.'
            }
        }
    }
}


function Install-Scoop {

    # Tls12
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072

    # Install Scoop
    Write-Host 'Installing Scoop...' -ForegroundColor Cyan

    $ScoopInstallerScript = Invoke-RestMethod "$GitHubProxy/https://raw.githubusercontent.com/scoopinstaller/install/master/install.ps1" -UseBasicParsing
    $ScoopInstallerScript = $ScoopInstallerScript -replace "(?<=\`$SCOOP_PACKAGE_REPO = ').*?(?=')", "$GitHubProxy/https://github.com/xrgzs/scoop/archive/master.zip"
    $ScoopInstallerScript = $ScoopInstallerScript -replace "(?<=\`$SCOOP_MAIN_BUCKET_REPO = ').*?(?=')", "$GitHubProxy/https://github.com/ScoopInstaller/Main/archive/master.zip"
    $ScoopInstallerScript = $ScoopInstallerScript -replace "(?<=\`$SCOOP_PACKAGE_GIT_REPO = ').*?(?=')", "https://gitcode.com/xrgzs/scoop.git"
    $ScoopInstallerScript = $ScoopInstallerScript -replace "(?<=\`$SCOOP_MAIN_BUCKET_GIT_REPO = ').*?(?=')", "$GitHubProxy/https://github.com/ScoopInstaller/Main.git"

    # $ScoopInstallerScript = Invoke-RestMethod http://c.xrgzs.top/c/scoop-installer.ps1
    $ScoopInstaller = Join-Path $env:TEMP "scoop_installer_$(Get-Random).ps1"
    $ScoopInstallerScript | Out-File $ScoopInstaller
    . $ScoopInstaller -RunAsAdmin -ScoopDir $SCOOP_DIR -ScoopGlobalDir $SCOOP_GLOBAL_DIR -ScoopCacheDir $SCOOP_CACHE_DIR
    Remove-Item $ScoopInstaller -Force

    # Refresh system environment, no need to refresh again if scoop\shims exists
    Update-Env
}

# ========================================================================
# Main program starts here
# ========================================================================

# Scoop root directory
$SCOOP_DIR = $env:SCOOP = $ScoopDir, $env:SCOOP, "$env:USERPROFILE\scoop" | Where-Object { -not [String]::IsNullOrEmpty($_) } | Select-Object -First 1
[Environment]::SetEnvironmentVariable('SCOOP', $SCOOP_DIR, 'User')
Write-Host "Scoop will install to $SCOOP_DIR"
# Scoop global apps directory
$SCOOP_GLOBAL_DIR = $ScoopGlobalDir, $env:SCOOP_GLOBAL, "$env:ProgramData\scoop" | Where-Object { -not [String]::IsNullOrEmpty($_) } | Select-Object -First 1
# Scoop cache directory
$SCOOP_CACHE_DIR = $ScoopCacheDir, $env:SCOOP_CACHE, "$SCOOP_DIR\cache" | Where-Object { -not [String]::IsNullOrEmpty($_) } | Select-Object -First 1
# GitHub Proxy
$GitHubProxy = $GitHubProxy, $env:GITHUB_PROXY, 'https://gh.xrgzs.top' | Where-Object { -not [String]::IsNullOrEmpty($_) } | Select-Object -First 1
# Get Version
$OsVersion = [System.Environment]::OSVersion.Version


# Allow running unsigned scripts
# Need to open the built-in PowerShell with administrator privileges first, set script execution permissions
try { Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force } catch { }


# NT6 special handling
if ($OsVersion.Major -eq 6) {
    Write-Warning 'Detected this PC is running Windows 7/8/8.1.'
    Write-Warning 'It is recommended to upgrade to Windows 10 or later because some CLI tools do not work on Windows 7.'

    $ScriptTemp = [System.IO.Path]::GetTempPath() + 'SCOOPNT6_' + $(Get-Random)
    New-Item -Path $ScriptTemp -ItemType Directory | Out-Null
    Push-Location $ScriptTemp

    Get-Aria2
    Write-Host 'Installing OpenSSL build of aria2c.exe for Scoop...'
    New-Item "$SCOOP_DIR\shims" -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
    Copy-Item .\aria2c.exe "$SCOOP_DIR\shims" -Force -ErrorAction SilentlyContinue | Out-Null
    New-Item "$SCOOP_DIR\apps\aria2\current" -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
    Copy-Item .\aria2c.exe "$SCOOP_DIR\apps\aria2\current" -Force -ErrorAction SilentlyContinue | Out-Null

    .\aria2c.exe -c -R --retry-wait=5 --check-certificate=false -o '7z.exe' 'http://url.xrgzs.top/7zexe'
    if ($LASTEXITCODE -ne 0) { throw 'Cannot download 7z.exe!' }
    .\aria2c.exe -c -R --retry-wait=5 --check-certificate=false -o '7z.dll' 'http://url.xrgzs.top/7zdll'
    if ($LASTEXITCODE -ne 0) { throw 'Cannot download 7z.dll!' }

    # Install Git, which will be used to pull Scoop to avoid network issues preventing downloads
    if (-not (Test-CommandAvailable git.exe)) {
        Write-Host 'Installing Git for Windows...' -ForegroundColor Cyan
        if ([System.Environment]::Is64BitOperatingSystem -or ($env:PROCESSOR_ARCHITECTURE -eq 'AMD64')) {
            $GitDownloadUrl = 'http://api.xrgzs.top/ghrelease/?repo=git-for-windows/git&search=MinGit-&filter=-64-bit.zip&mirror=auto'
        } else {
            $GitDownloadUrl = 'http://api.xrgzs.top/ghrelease/?repo=git-for-windows/git&search=MinGit-&filter=-32-bit.zip&mirror=auto'
        }
        .\aria2c.exe -c -R --retry-wait=5 --check-certificate=false -s16 -x16 -k1M -o 'MinGit.zip' "$GitDownloadUrl"
        if ($LASTEXITCODE -ne 0) { throw 'Cannot download Git, please install it manually!' }
        Remove-Item "$SCOOP_DIR\apps\git" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
        New-Item "$SCOOP_DIR\apps\git" -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
        .\7z.exe x -y 'MinGit.zip' -o"current"
        Move-Item 'current' "$SCOOP_DIR\apps\git" -Force -ErrorAction SilentlyContinue | Out-Null
        [Environment]::SetEnvironmentVariable('PATH', $("$SCOOP_DIR\apps\git\current\cmd;" + [Environment]::GetEnvironmentVariable('PATH', 'User')), 'User')
        [Environment]::SetEnvironmentVariable('GIT_INSTALL_ROOT', $("$SCOOP_DIR\apps\git\current"))
        Update-Env
    }

    # Install PowerShell Core, which will be used to install and run Scoop
    if (-not (Test-CommandAvailable pwsh.exe)) {
        Write-Host 'Installing PowerShell Core for Windows...' -ForegroundColor Cyan
        if ([System.Environment]::Is64BitOperatingSystem -or ($env:PROCESSOR_ARCHITECTURE -eq 'AMD64')) {
            $PwshDownloadUrl = 'https://dl.xrgzs.top/d/pxy/Software/PowerShell/PowerShell-7.2.24-win-x64.zip'
        } else {
            $PwshDownloadUrl = 'https://dl.xrgzs.top/d/pxy/Software/PowerShell/PowerShell-7.2.24-win-x86.zip'
        }
        .\aria2c.exe -c -R --retry-wait=5 --check-certificate=false -s16 -x16 -k1M -o 'pwsh.zip' "$PwshDownloadUrl"
        if ($LASTEXITCODE -ne 0) { throw 'Cannot download PowerShell Core, please install it manually!' }
        Remove-Item "$SCOOP_DIR\apps\pwsh" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
        New-Item "$SCOOP_DIR\apps\pwsh" -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
        .\7z.exe x -y 'pwsh.zip' -o"current"
        Move-Item 'current' "$SCOOP_DIR\apps\pwsh" -Force -ErrorAction SilentlyContinue | Out-Null
        [Environment]::SetEnvironmentVariable('PATH', $("$SCOOP_DIR\apps\pwsh\current;" + [Environment]::GetEnvironmentVariable('PATH', 'User')), 'User')
        Update-Env
    }

    Pop-Location
    Remove-Item -Path $ScriptTemp -Recurse
}

# Not compatible with PowerShell 5 or earlier versions
# Prefer using PowerShell Core
if ($PSVersionTable.PSVersion.Major -lt 5) {
    if (Test-CommandAvailable pwsh.exe) {
        pwsh.exe -v
        if ($LASTEXITCODE -ne 0) {
            if ([System.Environment]::Is64BitOperatingSystem -or ($env:PROCESSOR_ARCHITECTURE -eq 'AMD64')) {
                Start-Process 'https://download.microsoft.com/download/0/8/E/08E0386B-F6AF-4651-8D1B-C0A95D2731F0/Windows6.1-KB3063858-x64.msu'
            } else {
                Start-Process 'https://download.microsoft.com/download/C/9/6/C96CD606-3E05-4E1C-B201-51211AE80B1E/Windows6.1-KB3063858-x86.msu'
            }
            Write-Error 'Please install the msu update opened in your browser and reboot if you are using Windows 7.'
        }
        Clear-Host
        pwsh.exe -c 'irm c.xrgzs.top/c/scoop | iex'
        Update-Env
        if (Test-CommandAvailable scoop) {
            New-Item "$env:USERPROFILE\Documents\WindowsPowerShell" -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
            "function scoop { . pwsh.exe -noprofile -ex unrestricted -file `"$SCOOP_DIR\apps\scoop\current\bin\scoop.ps1`" @args }" >> "$env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
            return
        }
    }
    Write-Error 'PowerShell 5 or later is required to run Scoop.'
}

# Avoid schannel issues on Windows causing connection failures
if (Test-CommandAvailable git.exe) {
    git config --global http.sslBackend openssl
    git config --global http.sslverify false
}

# Determine if Scoop needs to be installed
if (Test-CommandAvailable scoop) {
    Write-Host 'Scoop has already been installed.' -ForegroundColor Green
    Remove-Item "$SCOOP_DIR\apps\scoop\current\.git" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
} else {
    while (-not (Test-CommandAvailable scoop)) {
        Install-Scoop
    }
}

$ErrorActionPreference = 'Continue'

# Replace Scoop repository source with modified one
# scoop config scoop_repo "$GitHubProxy/https://github.com/xrgzs/scoop"
scoop config scoop_repo 'https://gitcode.com/xrgzs/scoop'
scoop config scoop_branch 'master'

# Configure GitHub Proxy for Scoop
scoop config gh_proxy "$($GitHubProxy -replace '^https?://', '')"

# Aria2 configuration optimization
scoop config aria2-options '--check-certificate=false'
scoop config aria2-max-connection-per-server 16
scoop config aria2-split 16
scoop config aria2-min-split-size 1M
scoop config aria2-enabled true
scoop config aria2-warning-enabled false

# Currently Git is not installed, but the main bucket installation script has been downloaded and extracted

# Install 7zip git aria2c
# WinPE may not extract 7zip using msiexec
while (-not (Test-CommandAvailable aria2c.exe)) {
    scoop install aria2
}
if (Test-Path 'X:\Windows\System32\cmd.exe') {
    scoop config use_external_7zip true
    scoop config use_lessmsi true
    scoop install mingit
} else {
    while (-not (Test-CommandAvailable 7z.exe)) {
        scoop install 7zip
        reg.exe import "$SCOOP_DIR\apps\7zip\current\install-context.reg" *>$null
    }
}
while (-not (Test-CommandAvailable git.exe)) {
    scoop install git
    reg.exe import "$SCOOP_DIR\apps\git\current\install-context.reg" *>$null
    reg.exe import "$SCOOP_DIR\apps\git\current\install-file-associations.reg" *>$null
    git config --global credential.helper manager
}

# Avoid Windows connection issues due to schannel problems
git config --global http.sslBackend openssl
if ($OsVersion.Major -eq 6) { git config --global http.sslverify false }

# Execute update, automatically convert main bucket to git directory
scoop update

# Add known buckets
Write-Host 'Adding known buckets...' -ForegroundColor Cyan
$BucketJobs = @()
$BucketJobs += Add-ScoopBucketJob -Name 'main'
if (!$Slim) {
    $BucketJobs += Add-ScoopBucketJob -Name 'extras'
    $BucketJobs += Add-ScoopBucketJob -Name 'versions'
    $BucketJobs += Add-ScoopBucketJob -Name 'nirsoft'
    $BucketJobs += Add-ScoopBucketJob -Name 'sysinternals'
    # $BucketJobs += Add-ScoopBucketJob -Name 'php'
    $BucketJobs += Add-ScoopBucketJob -Name 'nerd-fonts'
    $BucketJobs += Add-ScoopBucketJob -Name 'nonportable'
    $BucketJobs += Add-ScoopBucketJob -Name 'java'
    $BucketJobs += Add-ScoopBucketJob -Name 'games'
}
$BucketJobs += Add-ScoopBucketJob -Name 'sdoog' -Uri "$GitHubProxy/https://github.com/xrgzs/sdoog"

# Add curated repository sources
if (!$Slim) {
    $BucketJobs += Add-ScoopBucketJob -Name 'dorado' -Uri "$GitHubProxy/https://github.com/chawyehsu/dorado"
    # $BucketJobs += Add-ScoopBucketJob -Name 'DoveBoy' -Uri "$GitHubProxy/https://github.com/DoveBoy/Apps"
    # $BucketJobs += Add-ScoopBucketJob -Name 'aki' -Uri "$GitHubProxy/https://github.com/akirco/aki-apps"
    # $BucketJobs += Add-ScoopBucketJob -Name 'abgo_bucket' -Uri "$GitHubProxy/https://github.com/abgox/abgo_bucket"
    # $BucketJobs += Add-ScoopBucketJob -Name 'scoop-zapps' -Uri "$GitHubProxy/https://github.com/kkzzhizhou/scoop-zapps"
}

# Wait for bucket addition tasks to complete
Write-Host 'Waiting for the bucket addition task to complete...'
Receive-Job -Job $BucketJobs -Wait -AutoRemoveJob
$BucketJobs = $null
Write-Host 'Known buckets added!' -ForegroundColor Green

# Install some recommended packages
if (!$Slim) {
    # Windows 7 does not support scoop-search
    if ($OsVersion.Build -gt 7602) { scoop install scoop-search gsudo }
    if ($Append) { scoop install $Append }
}

# Add aliases
# scoop alias list | ForEach-Object { scoop alias rm $_.name }
scoop alias add reinstall 'scoop uninstall $args; scoop install $args' 'Reinstall: uninstall and install app(s)'
# scoop alias add remove 'scoop uninstall $args' 'Remove: = uninstall app(s)'
# scoop alias add show 'scoop info $args' 'Show: = info app(s)'
scoop alias add upgrade 'scoop update $($args ? $args : "*")' 'Upgrade: update (all) app(s)'

# Configure automatic creation of desktop shortcuts
scoop config desktop_shortcut true

# Configure automatic creation of uninstall shortcuts
scoop config uninstall_shortcut true

# Reset ACL to current user if UAC is enabled and running as administrator (important)
if (($SCOOP_DIR -eq "$env:USERPROFILE\scoop") -and (Test-IsAdministrator) -and ($env:USERNAME -notin 'Administrator', 'SYSTEM')) {
    Write-Host "Resetting ACL to $env:USERNAME..." -ForegroundColor Cyan
    takeown /F "$SCOOP_DIR" /R /SKIPSL | Out-Null
    # $userAcl = Get-Acl "$env:USERPROFILE\Appdata"
    # Get-ChildItem -Path "$SCOOP_DIR" -Recurse -Force | Set-Acl -AclObject $userAcl
}

# Refresh system environment
Update-Env

Write-Host 'Scoop was installed successfully!' -ForegroundColor Cyan

Start-Sleep -Seconds 5
