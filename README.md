# Scoop 特供优化版

Scoop 修改优化特供版。通过第三方方式解决痛点问题，让您轻松使用 Scoop。

## 特点

1. 添加 hook，自动判断并替换下载链接为国内源，无需替换 Bucket，让您不再使用“垃圾桶”；基于 ISP 检测，加速策略更为精准

   - 支持自定义 GitHub Proxy 加速镜像地址，只需执行 `scoop config GH_PROXY ghproxy.cc` 设置即可

   - 如果出现下载出错、校验错误的情况，可以执行 `scoop config URL_REPLACE false` 关闭此功能

   - 如有镜像站软件未替换，欢迎提 issue

2. 执行 `scoop search` 时优先调用 [scoop-search](https://github.com/shilangyu/scoop-search) 执行搜索，速度更快

   - 优先级：`scoop-search` > `PowerShell Core` > `Windows PowerShell`

3. 执行 `scoop update` 时不使用 `git pull` 同步 Bucket，无需手动解决 commit 冲突

4. ~~执行 `scoop update` 时优先调用 [hok](https://github.com/chawyehsu/hok) 使用 Rust Git2 多线程同步 Bucket~~ (暂时停用)

   - 优先级：`PowerShell Core + Git` 多线程 > `Windows PowerShell + Git` 单线程

5. 支持自动创建桌面快捷方式

   - 启用：`scoop config DESKTOP_SHORTCUT true` （安装脚本默认配置）

   - 禁用：`scoop config DESKTOP_SHORTCUT false` 或 `scoop config rm DESKTOP_SHORTCUT`

6. 支持自动创建控制面板卸载程序快捷方式，可通过控制面板卸载/重设应用

   - 优先级：首个快捷方式名称 > 应用名称，使用 `scoop_` + 应用名称 作为注册表项，使用 bucket 名称作为发布者

   - 启用：`scoop config UNINSTALL_SHORTCUT true` （安装脚本默认配置）

   - 禁用：`scoop config UNINSTALL_SHORTCUT false` 或 `scoop config rm UNINSTALL_SHORTCUT`

7. 仓库同步到 [Gitee](https://gitee.com/xrgzs/scoop)，方便国内用户更新规则

   - 切换到 GitHub 版本：`scoop config scoop_repo 'https://github.com/xrgzs/scoop'`

8. 安装脚本自动配置好 `7zip`、`git`、`aria2`、`scoop-search`，并做好相关优化

9. 安装脚本支持管理员权限安装，自动修复 Scoop 文件 ACL 到当前用户

## 安装

### 默认安装

安装脚本适配 PowerShell 2.0 及更高版本，支持 Windows 7 SP1 及更高版本。

```powershell
irm c.xrgzs.top/c/scoop | iex
```

Win7 SP1 (PowerShell 2.0) 及更高版本：

```powershell
(New-Object System.Net.WebClient).DownloadString('http://c.xrgzs.top/c/scoop') | iex
```

对于未安装 PowerShell 5.1 的系统，我们将自动安装 PowerShell 7.2，并强制使用 PowerShell 7.2 执行 Scoop。

对于 Windows PE，需要补全 `C:\Windows\System32\Robocopy.exe` 才可安装 Scoop。

### 增加指定软件

多个可用空格分隔。

```powershell
iex "& { $(irm c.xrgzs.top/c/scoop) } -Append xrok"
```

### 精简安装

仅安装主程序、git、aria2，添加 main 和 sdoog。

```powershell
iex "& { $(irm c.xrgzs.top/c/scoop) } -Slim"
```

### 设置安装路径

安装到 D 盘。

```powershell
iex "& { $(irm c.xrgzs.top/c/scoop) } -ScoopDir 'D:\Scoop' -ScoopGlobalDir 'D:\ScoopGlobal'"
```

### 切换到此版本

如果已经安装 Scoop，可以切换到此专用版本。

```powershell
# scoop config scoop_repo "https://gh.xrgzs.top/https://github.com/xrgzs/scoop"
scoop config scoop_repo 'https://gitee.com/xrgzs/scoop'
scoop config scoop_branch 'master'

scoop update
```

### 强制更新

如果您的 Scoop 无法更新，可以执行以下命令强制更新 Scoop：

```powershell
Remove-Item -Path "~\scoop\apps\scoop\current\.git\" -Recurse -Force
scoop update
```

或：

```powershell
Push-Location "~\scoop\apps\scoop\current\"
git fetch origin master
git reset --hard origin/master
Pop-Location
```
