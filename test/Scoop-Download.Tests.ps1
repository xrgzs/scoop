BeforeAll {
    . "$PSScriptRoot\Scoop-TestLib.ps1"
    . "$PSScriptRoot\..\lib\core.ps1"
    . "$PSScriptRoot\..\lib\download.ps1"
}

Describe 'Test-Aria2Enabled' -Tag 'Scoop' {
    It 'should return true if aria2 is installed' {
        Mock Test-HelperInstalled { $true }
        Mock get_config { $true }
        Test-Aria2Enabled | Should-BeTrue
    }

    It 'should return false if aria2 is not installed' {
        Mock Test-HelperInstalled { $false }
        Mock get_config { $false }
        Test-Aria2Enabled | Should-BeFalse

        Mock Test-HelperInstalled { $false }
        Mock get_config { $true }
        Test-Aria2Enabled | Should-BeFalse

        Mock Test-HelperInstalled { $true }
        Mock get_config { $false }
        Test-Aria2Enabled | Should-BeFalse
    }
}

Describe 'Test-GhostEnabled' -Tag 'Scoop' {
    It 'should return false when Ghost Downloader is disabled' {
        Mock get_config { $false } -ParameterFilter { $name -eq 'ghost-enabled' }
        Mock Get-GhostCliPath { 'ghd.exe' }
        Test-GhostEnabled | Should-BeFalse
    }

    It 'should return false when Ghost Downloader is enabled but ghd is missing' {
        Mock get_config { $true } -ParameterFilter { $name -eq 'ghost-enabled' }
        Mock Get-GhostCliPath { $null }
        Test-GhostEnabled | Should-BeFalse
    }

    It 'should return true when Ghost Downloader is enabled and ghd is available' {
        Mock get_config { $true } -ParameterFilter { $name -eq 'ghost-enabled' }
        Mock Get-GhostCliPath { 'ghd.exe' }
        Test-GhostEnabled | Should-BeTrue
    }
}

Describe 'Get-GhostCliPath' -Tag 'Scoop' {
    BeforeEach {
        Remove-Item Env:GHD_CLI -ErrorAction SilentlyContinue
    }

    AfterAll {
        Remove-Item Env:GHD_CLI -ErrorAction SilentlyContinue
    }

    It 'should use the configured ghost-path' {
        $ghd = Join-Path $TestDrive 'ghd.exe'
        New-Item -ItemType File -Path $ghd | Out-Null
        Mock get_config { $ghd } -ParameterFilter { $name -eq 'ghost-path' }
        Mock Get-AppFilePath { $null }
        Mock Get-Command { $null }

        Get-GhostCliPath | Should-Be (Convert-Path -LiteralPath $ghd)
    }

    It 'should accept a folder for ghost-path' {
        $folder = Join-Path $TestDrive 'ghost'
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        $ghd = Join-Path $folder 'ghd.exe'
        New-Item -ItemType File -Path $ghd | Out-Null
        Mock get_config { $folder } -ParameterFilter { $name -eq 'ghost-path' }
        Mock Get-AppFilePath { $null }
        Mock Get-Command { $null }

        Get-GhostCliPath | Should-Be (Convert-Path -LiteralPath $ghd)
    }

    It 'should use GHD_CLI when ghost-path is unset' {
        $ghd = Join-Path $TestDrive 'ghd-env.exe'
        New-Item -ItemType File -Path $ghd | Out-Null
        $env:GHD_CLI = $ghd
        Mock get_config { $null }
        Mock Get-AppFilePath { $null }
        Mock Get-Command { $null }

        Get-GhostCliPath | Should-Be (Convert-Path -LiteralPath $ghd)
    }

    It 'should auto-detect the Ghost Downloader app' {
        Mock get_config { $null }
        Mock Get-AppFilePath { $null }
        Mock Get-AppFilePath { 'C:\scoop\apps\Ghost-Downloader-portable\current\bin\ghd.exe' } -ParameterFilter { $App -eq 'Ghost-Downloader-portable' }
        Mock Get-Command { $null }

        Get-GhostCliPath | Should-Be 'C:\scoop\apps\Ghost-Downloader-portable\current\bin\ghd.exe'
    }

    It 'should return null when ghd cannot be found' {
        Mock get_config { $null }
        Mock Get-AppFilePath { $null }
        Mock Get-Command { $null }

        Get-GhostCliPath | Should-BeNull
    }
}

Describe 'New-DownloadRequest Accept header' -Tag 'Scoop' {
    BeforeAll {
        Mock Get-UserAgent { 'Scoop-Test' }
        Mock Get-GitHubToken { 'fake-token' }
        Mock get_config { }
    }

    It 'omits the Accept header for an Actions artifact zip so it is not rejected with 415' {
        $req = New-DownloadRequest 'https://api.github.com/repos/example/example/actions/artifacts/11138249207/zip'
        $req.Accept | Should-BeNull
    }

    It 'omits the Accept header for an artifact zip even when a filename-override fragment is appended' {
        # Exercises the $reqUrl fragment-strip + Accept-check interaction (the original bug)
        $req = New-DownloadRequest 'https://api.github.com/repos/example/example/actions/artifacts/11138249207/zip#/example.zip'
        $req.Accept | Should-BeNull
    }

    It 'sets octet-stream Accept for a release asset so it returns the binary' {
        $req = New-DownloadRequest 'https://api.github.com/repos/example/example/releases/assets/599854636'
        $req.Accept | Should-Be 'application/octet-stream'
    }

    It 'sets octet-stream Accept for other api.github.com paths' {
        $req = New-DownloadRequest 'https://api.github.com/repos/example/example/actions/artifacts/11138249207'
        $req.Accept | Should-Be 'application/octet-stream'
    }
}

Describe 'url_filename' -Tag 'Scoop' {
    It 'should extract the real filename from an url' {
        url_filename 'http://example.org/foo.txt' | Should-Be 'foo.txt'
        url_filename 'http://example.org/foo.txt?var=123' | Should-Be 'foo.txt'
    }

    It 'can be tricked with a hash to override the real filename' {
        url_filename 'http://example.org/foo-v2.zip#/foo.zip' | Should-Be 'foo.zip'
    }
}

Describe 'url_remote_filename' -Tag 'Scoop' {
    It 'should extract the real filename from an url' {
        url_remote_filename 'http://example.org/foo.txt' | Should-Be 'foo.txt'
        url_remote_filename 'http://example.org/foo.txt?var=123' | Should-Be 'foo.txt'
    }

    It 'can not be tricked with a hash to override the real filename' {
        url_remote_filename 'http://example.org/foo-v2.zip#/foo.zip' | Should-Be 'foo-v2.zip'
    }
}

Describe 'setup_proxy' -Tag 'Scoop' {
    BeforeEach {
        Mock get_config { $null }
        # reset to direct connection so assertions are deterministic
        [Net.WebRequest]::DefaultWebProxy = [Net.GlobalProxySelection]::Select
        $env:HTTP_PROXY = $null
        $env:HTTPS_PROXY = $null
        $env:ALL_PROXY = $null
    }

    AfterAll {
        # restore default proxy behavior after tests
        [Net.WebRequest]::DefaultWebProxy = [Net.GlobalProxySelection]::Select
    }

    It 'should set no proxy when config and env vars are unset' {
        setup_proxy
        [Net.WebRequest]::DefaultWebProxy.GetProxy('http://example.org').AbsoluteUri | Should -Be 'http://example.org/'
    }

    It 'should use proxy from PROXY config' {
        Mock get_config { '127.0.0.1:10808' } -ParameterFilter { $name -eq 'PROXY' }
        setup_proxy
        [Net.WebRequest]::DefaultWebProxy.GetProxy('http://example.org').AbsoluteUri | Should -Be 'http://127.0.0.1:10808/'
    }

    It 'should keep http scheme from env var instead of duplicating it' {
        $env:HTTP_PROXY = 'http://127.0.0.1:10808'
        setup_proxy
        [Net.WebRequest]::DefaultWebProxy.GetProxy('http://example.org').AbsoluteUri | Should -Be 'http://127.0.0.1:10808/'
    }

    It 'should keep https scheme from env var' {
        $env:HTTPS_PROXY = 'https://127.0.0.1:10808'
        setup_proxy
        [Net.WebRequest]::DefaultWebProxy.GetProxy('http://example.org').AbsoluteUri | Should -Be 'https://127.0.0.1:10808/'
    }

    It 'should read ALL_PROXY env var as fallback' {
        $env:ALL_PROXY = 'http://127.0.0.1:10809'
        setup_proxy
        [Net.WebRequest]::DefaultWebProxy.GetProxy('http://example.org').AbsoluteUri | Should -Be 'http://127.0.0.1:10809/'
    }

    It 'should support user:pass credentials in address' {
        $env:HTTP_PROXY = 'user:pass@127.0.0.1:10808'
        setup_proxy
        [Net.WebRequest]::DefaultWebProxy.GetProxy('http://example.org').AbsoluteUri | Should -Be 'http://127.0.0.1:10808/'
        ([Net.WebRequest]::DefaultWebProxy.Credentials -as [Net.NetworkCredential]).UserName | Should -Be 'user'
        ([Net.WebRequest]::DefaultWebProxy.Credentials -as [Net.NetworkCredential]).Password | Should -Be 'pass'
    }

    It 'should support scheme with credentials (http://user:pass@host)' {
        $env:HTTP_PROXY = 'http://user:pass@127.0.0.1:10808'
        setup_proxy
        [Net.WebRequest]::DefaultWebProxy.GetProxy('http://example.org').AbsoluteUri | Should -Be 'http://127.0.0.1:10808/'
        ([Net.WebRequest]::DefaultWebProxy.Credentials -as [Net.NetworkCredential]).UserName | Should -Be 'user'
        ([Net.WebRequest]::DefaultWebProxy.Credentials -as [Net.NetworkCredential]).Password | Should -Be 'pass'
    }

    It 'should support socks5 scheme on PowerShell 7+' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
        $env:ALL_PROXY = 'socks5://127.0.0.1:10808'
        setup_proxy
        [Net.WebRequest]::DefaultWebProxy.GetProxy('http://example.org').AbsoluteUri | Should -Be 'socks5://127.0.0.1:10808/'
    }

    It 'should support socks5h scheme on PowerShell 7+' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
        $env:ALL_PROXY = 'socks5h://127.0.0.1:10808'
        setup_proxy
        [Net.WebRequest]::DefaultWebProxy.GetProxy('http://example.org').AbsoluteUri | Should -Be 'socks5h://127.0.0.1:10808/'
    }

    It 'should support socks4 scheme on PowerShell 7+' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
        $env:ALL_PROXY = 'socks4://127.0.0.1:10808'
        setup_proxy
        [Net.WebRequest]::DefaultWebProxy.GetProxy('http://example.org').AbsoluteUri | Should -Be 'socks4://127.0.0.1:10808/'
    }

    It 'should disable proxy with none' {
        $env:HTTP_PROXY = 'none'
        setup_proxy
        [Net.WebRequest]::DefaultWebProxy | Should -BeNullOrEmpty
    }

    It 'should use system default proxy with default' {
        $env:HTTP_PROXY = 'default'
        setup_proxy
        [Net.WebRequest]::DefaultWebProxy | Should -Be ([Net.GlobalProxySelection]::Select)
    }

    It 'should warn on socks proxy in PowerShell 5.1' -Skip:($PSVersionTable.PSVersion.Major -ge 7) {
        Mock warn { $true }
        $env:ALL_PROXY = 'socks5://127.0.0.1:10808'
        setup_proxy
        Should -Invoke warn -Times 1

        $env:ALL_PROXY = 'socks4://127.0.0.1:10808'
        setup_proxy
        Should -Invoke warn -Times 2
    }
}
