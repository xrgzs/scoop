
function Get-ISPName {
    try {
        info '[GetISP] Detecting ISP information (API: ipwho.is)...'
        $ipInfo = Invoke-RestMethod -Uri 'https://ipwho.is/' -UseBasicParsing -TimeoutSec 3 -UserAgent 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.6261.95 Safari/537.36'
        return $ipInfo.connection.isp
    } catch {
        error '[GetISP] Failed to detect ISP information.'
        debug "$_"
        try {
            info '[GetISP] Detecting ISP information (API: ip.sb)...'
            $ipInfo = Invoke-RestMethod -Uri 'https://api.ip.sb/geoip/' -UseBasicParsing -TimeoutSec 3 -UserAgent 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.6261.95 Safari/537.36'
            return $ipInfo.isp
        } catch {
            error '[GetISP] Failed to detect ISP information.'
            debug "$_"
            try {
                info '[GetISP] Detecting IP information (API: realip.cc)...'
                $ipInfo = Invoke-RestMethod -Uri 'https://realip.cc/' -UseBasicParsing -TimeoutSec 3 -UserAgent 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.6261.95 Safari/537.36'
                return $ipInfo.isp
            } catch {
                error '[GetISP] Failed to detect ISP information.'
                debug "$_"
                return 'Unknown'
            }
        }
    }
}


function url_replace($url) {
    if ((get_config URL_REPLACE) -eq $False) {
        return $url
    }
    # 获取客户端ip属地
    # $ip = ''
    info '[UrlReplace] Detecting IP region (API: Cloudflare)...'
    $region = 'Unknown'
    foreach ($ipapi in ('https://dash.cloudflare.com/cdn-cgi/trace', 'https://www.cf-ns.com/cdn-cgi/trace', 'https://1.0.0.1/cdn-cgi/trace')) {
        try {
            $ipapi = Invoke-RestMethod -Uri $ipapi -TimeoutSec 1 -UseBasicParsing
            # if ($ipapi -match 'ip=([\d.]+)' ) {
            #     $ip = $Matches[1]
            # }
            if ($ipapi -match 'loc=(\w+)' ) {
                $region = $Matches[1]
                break
            }
        } catch {
            $region = 'CN'
        }
    }
    # 如果不在 CN，则使用直连
    if ($region -ne 'CN') {
        success '[UrlReplace] direct (Not in CN)'
        return $url
    }
    # 如果在 CN，则使用加速地址
    info '[UrlReplace] You are in CN.'

    $ghproxy = get_config GH_PROXY
    if (!$ghproxy) {
        $ghproxy = 'gh.xrgzs.top'
        set_config GH_PROXY $ghproxy | Out-Null
    }

    # 定义替换规则的映射表
    $replacementMap = @{
        # XRWEBDL
        'list\.xrgzs\.top/d/pxy'                                              = 'dl.xrgzs.top/d/pxy'

        # GitHub Clone
        '(^https?://github\.com/.+/.+$)'                                       = 'https://' + $ghproxy + '/$1'
        '(^https?://github\.com/.+/.+\.git$)'                                  = 'https://' + $ghproxy + '/$1.git'

        # GitHub Releases
        '(^https?://github\.com/.+/releases/.*download)'                       = 'https://' + $ghproxy + '/$1'

        # GitHub Archive
        '(^https?://github\.com/.+/archive/)'                                  = 'https://' + $ghproxy + '/$1'

        # GitHub Raw
        '(^https?://raw\.githubusercontent\.com)'                              = 'https://' + $ghproxy + '/$1'
        '(^https?://github\.com/.+/raw/)'                                      = 'https://' + $ghproxy + '/$1'

        # KDE Apps
        'download\.kde\.org'                                                   = 'mirrors.cernet.edu.cn/kde'

        # 7-Zip
        'www\.7-zip\.org/a'                                                    = 'mirror.nju.edu.cn/7-zip'

        # LaTeX, MiKTeX
        'miktex\.org/download/ctan'                                            = 'mirrors.aliyun.com/CTAN'
        'mirrors.+/CTAN'                                                       = 'mirrors.aliyun.com/CTAN'

        # Node
        'nodejs\.org/dist'                                                     = 'npmmirror.com/mirrors/node'

        # Python
        'www\.python\.org/ftp/python'                                          = 'npmmirror.com/mirrors/python'

        # Go
        'dl\.google\.com/go'                                                   = 'mirrors.aliyun.com/golang'

        # Flutter
        'storage\.googleapis\.com/flutter_infra'                               = 'storage.flutter-io.cn/flutter_infra'
        'storage\.googleapis\.com/flutter_infra_release'                       = 'storage.flutter-io.cn/flutter_infra_release'

        # Rustup
        'static\.rust-lang\.org/rustup'                                        = 'mirrors.aliyun.com/rustup/rustup'

        # Apache
        'dlcdn\.apache\.org'                                                   = 'mirrors.aliyun.com/apache'

        # Eclipse
        'download\.eclipse\.org'                                               = 'mirrors.cernet.edu.cn/eclipse'

        # JetBrains
        # 'download\.jetbrains\.com'                                           = 'download-alibaba.jetbrains.com.cn'

        # Gradle
        'services\.gradle\.org/distributions'                                  = 'mirror.nju.edu.cn/gradle'

        # VLC
        'download\.videolan\.org/pub'                                          = 'mirrors.aliyun.com/videolan'

        # Inkscape
        'media\.inkscape\.org/dl/resources/file'                               = 'mirrors.nju.edu.cn/inkscape'

        # DBeaver
        'dbeaver\.io/files'                                                    = $ghproxy + '/https://github.com/dbeaver/dbeaver/releases/download'

        # OBS Studio
        'cdn-fastly\.obsproject\.com/downloads/OBS-Studio-(.+)-Windows\.zip'   = $ghproxy + '/https://github.com/obsproject/obs-studio/releases/download/$1/OBS-Studio-$1-Windows.zip'
        'cdn-fastly\.obsproject\.com/downloads/OBS-Studio-(.+)-Full'           = $ghproxy + '/https://github.com/obsproject/obs-studio/releases/download/$1/OBS-Studio-$1-Full'

        # GIMP
        'download\.gimp\.org/mirror/pub'                                       = 'mirrors.aliyun.com/gimp'

        # Blender
        'download\.blender\.org'                                               = 'mirrors.aliyun.com/blender'

        # VirtualBox
        'download\.virtualbox\.org/virtualbox'                                 = 'mirrors.cernet.edu.cn/virtualbox'

        # WireShark
        'www\.wireshark\.org/download'                                         = 'mirrors.cernet.edu.cn/wireshark'

        # Lunacy
        'lun-eu\.icons8\.com/s/'                                               = 'lcdn.icons8.com/'

        # Strawberry
        'files\.jkvinge\.net/packages/strawberry/StrawberrySetup-(.+)-mingw-x' = $ghproxy + '/https://github.com/strawberrymusicplayer/strawberry/releases/download/$1/StrawberrySetup-$1-mingw-x'

        # SumatraPDF
        'files\.sumatrapdfreader\.org/file/kjk-files/software/sumatrapdf/rel'  = 'www.sumatrapdfreader.org/dl/rel'

        # Vim
        'ftp\.nluug\.nl/pub/vim/pc'                                            = 'mirrors.cernet.edu.cn/vim/pc'

        # Cygwin
        '//.*/cygwin/'                                                         = '//mirrors.aliyun.com/cygwin/'

        # MSYS2
        'mirror\.msys2\.org'                                                   = 'mirrors.cernet.edu.cn/msys2'
        'repo\.msys2\.org'                                                     = 'mirrors.cernet.edu.cn/msys2'

        # FastCopy
        'fastcopy\.jp/archive'                                                 = $ghproxy + '/https://raw.githubusercontent.com/FastCopyLab/FastCopyDist2/main'

        # Kodi
        'mirrors\.kodi\.tv'                                                    = 'mirrors.cernet.edu.cn/kodi'

        # LibreOffice
        'download\.documentfoundation\.org/libreoffice'                        = 'mirrors.cernet.edu.cn/libreoffice/libreoffice'

        # Typora
        'download\.typora\.io'                                                 = 'downloads.typoraio.cn'
    }

    # SourceForge特殊处理
    if ($ghproxy -eq 'gh.xrgzs.top') {
        $replacementMap += @{
            '(^https?://downloads\.sourceforge\.net/project/.+)' = 'https://' + $ghproxy + '/$1'
            '(^https?://sourceforge\.net/projects/.+/files/.+)'  = 'https://' + $ghproxy + '/$1'
            '(^https?://\w+\.dl\.sourceforge\.net/.+)'           = 'https://' + $ghproxy + '/$1'
        }
    }

    # 循环处理每个替换规则
    foreach ($pattern in $replacementMap.Keys) {
        if ($url -match $pattern) {
            $url = $url -replace $pattern, $replacementMap[$pattern]
            info "[UrlReplace] Hit: $pattern"
            success "[UrlReplace] Result: $url"
            break
        }
    }

    # 移动网络特殊处理
    # $replacementMapCM = @{
    #     # SourceForge
    #     # Use liquidtelecom
    #     '(//downloads\.sourceforge\.net/project/.+)' = '$1?use_mirror=liquidtelecom'
    #     '(//sourceforge\.net/projects/.+/files/.+)'  = '$1?use_mirror=liquidtelecom'
    #     '(\w+)(\.dl\.sourceforge\.net)'              = 'liquidtelecom$2'
    # }
    # foreach ($pattern in $replacementMapCM.Keys) {
    #     if ($url -match $pattern) {
    #         if (-not $ipisp) {
    #             $ipisp = Get-ISPName
    #         }
    #         if ($ipisp -like '*China Mobile*') {
    #             $url = $url -replace $pattern, $replacementMapCM[$pattern]
    #             info "[UrlReplace] Hit: $pattern"
    #             success "[UrlReplace] Result: $url"
    #             break
    #         }
    #     }
    # }
    # 返回处理后的URL
    return $url
}
