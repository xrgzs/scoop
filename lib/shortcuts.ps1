# Creates shortcut for the app in the start menu
function create_startmenu_shortcuts($manifest, $dir, $global, $arch) {
    $shortcuts = @(arch_specific 'shortcuts' $manifest $arch)
    $shortcuts | Where-Object { $_ -ne $null } | ForEach-Object {
        $target = [System.IO.Path]::Combine($dir, $_.item(0))
        $target = New-Object System.IO.FileInfo($target)
        $name = $_.item(1)
        $arguments = ''
        $icon = $null
        if ($_.length -ge 3) {
            $arguments = $_.item(2)
        }
        if ($_.length -ge 4) {
            $icon = [System.IO.Path]::Combine($dir, $_.item(3))
            $icon = New-Object System.IO.FileInfo($icon)
        }
        $arguments = (substitute $arguments @{ '$dir' = $dir; '$original_dir' = $original_dir; '$persist_dir' = $persist_dir })
        startmenu_shortcut $target $name $arguments $icon $global
    }
}

function shortcut_folder($global) {
    if ($global) {
        $startmenu = 'CommonStartMenu'
    } else {
        $startmenu = 'StartMenu'
    }
    return Convert-Path (ensure ([System.IO.Path]::Combine([Environment]::GetFolderPath($startmenu), 'Programs', 'Scoop Apps')))
}

function desktop_folder($global) {
    if ($global) {
        $desktop = 'CommonDesktopDirectory'
    } else {
        $desktop = 'DesktopDirectory'
    }
    return Convert-Path ([Environment]::GetFolderPath($desktop))
}

function startmenu_shortcut([System.IO.FileInfo] $target, $shortcutName, $arguments, [System.IO.FileInfo]$icon, $global) {
    if (!$target.Exists) {
        Write-Host -f DarkRed "Creating shortcut for $shortcutName ($(fname $target)) failed: Couldn't find $target"
        return
    }
    if ($icon -and !$icon.Exists) {
        Write-Host -f DarkRed "Creating shortcut for $shortcutName ($(fname $target)) failed: Couldn't find icon $icon"
        return
    }

    $scoop_startmenu_folder = shortcut_folder $global
    $subdirectory = [System.IO.Path]::GetDirectoryName($shortcutName)
    if ($subdirectory) {
        $subdirectory = ensure $([System.IO.Path]::Combine($scoop_startmenu_folder, $subdirectory))
    }

    $wsShell = New-Object -ComObject WScript.Shell
    $wsShell = $wsShell.CreateShortcut("$scoop_startmenu_folder\$shortcutName.lnk")
    $wsShell.TargetPath = $target.FullName
    $wsShell.WorkingDirectory = $target.DirectoryName
    if ($arguments) {
        $wsShell.Arguments = $arguments
    }
    if ($icon -and $icon.Exists) {
        $wsShell.IconLocation = $icon.FullName
    }
    $wsShell.Save()
    Write-Host "Creating shortcut for $shortcutName ($(fname $target))"
    if (get_config DESKTOP_SHORTCUT) {
        Write-Host "Creating desktop shortcut for $shortcutName ($(fname $target))"
        $scoop_desktop_folder = desktop_folder $global
        $subdirectory = [System.IO.Path]::GetDirectoryName($shortcutName)
        if ($subdirectory) {
            $subdirectory = ensure $([System.IO.Path]::Combine($scoop_desktop_folder, $subdirectory))
        }
        Copy-Item "$scoop_startmenu_folder\$shortcutName.lnk" "$scoop_desktop_folder\$shortcutName.lnk" -Force
    }
}

# Removes the Startmenu shortcut if it exists
function rm_startmenu_shortcuts($manifest, $global, $arch) {
    $shortcuts = @(arch_specific 'shortcuts' $manifest $arch)
    $shortcuts | Where-Object { $_ -ne $null } | ForEach-Object {
        $name = $_.item(1)
        $shortcut = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath("$(shortcut_folder $global)\$name.lnk")
        Write-Host "Removing shortcut $(friendly_path $shortcut)"
        if (Test-Path -Path $shortcut) {
            Remove-Item $shortcut
        }
        if (get_config DESKTOP_SHORTCUT) {
            $desktop_shortcut = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath("$(desktop_folder $global)\$name.lnk")
            Write-Host "Removing desktop shortcut $(friendly_path $desktop_shortcut)"
            if (Test-Path -Path $desktop_shortcut) {
                Remove-Item $desktop_shortcut
            }
        }
    }
}

function create_uninstall_shortcuts($app, $manifest, $bucket, $version, $dir, $global, $arch) {
    $name = $app
    $icon = $null
    $shortcut = @(arch_specific 'shortcuts' $manifest $arch) | Where-Object { $_ -ne $null } | Select-Object -First 1
    if ($shortcut) {
        $icon = [System.IO.Path]::Combine($dir, $shortcut.item(0))
        $name = [System.IO.Path]::GetFileNameWithoutExtension($shortcut.item(1))
        if ($shortcut.length -ge 4) {
            $icon = [System.IO.Path]::Combine($dir, $shortcut.item(3))
        }
    }
    Write-Host "Creating uninstall shortcut for $name to control panel"
    if ($global) {
        $regpath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\scoop_$app"
        $modifyPathValue = "cmd.exe /c `"sudo scoop reset `"$app`"`""
        $uninstallStringValue = "cmd.exe /c `"sudo scoop uninstall `"$app`" -p -g`""
    } else {
        $regpath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\scoop_$app"
        $modifyPathValue = "cmd.exe /c `"scoop reset `"$app`"`""
        $uninstallStringValue = "cmd.exe /c `"scoop uninstall `"$app`" -p`""
    }
    Remove-Item -Path $regpath -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
    New-Item -Path $regpath -Force | Out-Null
    New-ItemProperty -Path $regpath -Name 'DisplayName' -Value "$name (Scoop)" -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $regpath -Name 'DisplayVersion' -Value $version -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $regpath -Name 'ModifyPath' -Value $modifyPathValue -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $regpath -Name 'UninstallString' -Value $uninstallStringValue -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $regpath -Name 'Publisher' -Value $bucket -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $regpath -Name 'InstallDate' -Value (Get-Date -Format yyyyMMdd) -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $regpath -Name 'InstallLocation' -Value $dir -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $regpath -Name 'EstimatedSize' -Value ((Get-ChildItem $dir -Recurse -File | Measure-Object -Property Length -Sum).Sum / 1KB) -PropertyType DWord -Force | Out-Null
    if ($icon) {
        New-ItemProperty -Path $regpath -Name 'DisplayIcon' -Value $icon -PropertyType String -Force | Out-Null
    }
    if ($manifest.homepage) {
        New-ItemProperty -Path $regpath -Name 'URLInfoAbout' -Value $manifest.homepage -PropertyType String -Force | Out-Null
    }
}

function rm_uninstall_shortcuts($app, $global) {
    Write-Host "Removing uninstall shortcut for $app from control panel"
    if ($global) {
        $regpath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\scoop_$app"
    } else {
        $regpath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\scoop_$app"
    }
    Remove-Item -Path $regpath -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
}
