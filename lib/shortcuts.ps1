# Creates shortcut for the app in the start menu
function create_startmenu_shortcuts($manifest, $dir, $global, $arch) {
    $shortcuts = @(arch_specific 'shortcuts' $manifest $arch | Where-Object { $_ -ne $null })
    $shortcuts | ForEach-Object {
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

    sync_desktop_shortcut $manifest $dir $global $arch $app
}

function shortcut_folder($global) {
    if ($global) {
        $startmenu = 'CommonStartMenu'
    } else {
        $startmenu = 'StartMenu'
    }
    return Convert-Path (ensure ([System.IO.Path]::Combine([Environment]::GetFolderPath($startmenu), 'Programs', 'Scoop Apps')))
}

function desktop_shortcut_path($global, $shortcutName) {
    $desktop = if ($global) { 'CommonDesktopDirectory' } else { 'Desktop' }
    $desktop = [Environment]::GetFolderPath($desktop)
    Join-Path $desktop "$([System.IO.Path]::GetFileName($shortcutName)).lnk"
}

function sync_desktop_shortcut($manifest, $dir, $global, $arch, $app) {
    $shortcuts = @(arch_specific 'shortcuts' $manifest $arch | Where-Object { $_ -ne $null })
    if (!$shortcuts) { return }
    if ($app -in @('7zip', 'git')) { return }

    $shortcut = $shortcuts[0]
    $name = $shortcut.item(1)
    $path = desktop_shortcut_path $global $name
    if (!(get_config DESKTOP_SHORTCUT)) {
        remove_shortcut_file $path
        return
    }

    $target = New-Object System.IO.FileInfo([System.IO.Path]::Combine($dir, $shortcut.item(0)))
    $arguments = ''
    $icon = $null
    if ($shortcut.length -ge 3) { $arguments = $shortcut.item(2) }
    if ($shortcut.length -ge 4) {
        $icon = New-Object System.IO.FileInfo([System.IO.Path]::Combine($dir, $shortcut.item(3)))
    }
    $arguments = substitute $arguments @{ '$dir' = $dir; '$original_dir' = $original_dir; '$persist_dir' = $persist_dir }
    create_shortcut_file $target $name $arguments $icon $path
}

function startmenu_shortcut([System.IO.FileInfo] $target, $shortcutName, $arguments, [System.IO.FileInfo]$icon, $global) {
    $scoop_startmenu_folder = shortcut_folder $global
    $subdirectory = [System.IO.Path]::GetDirectoryName($shortcutName)
    if ($subdirectory) {
        $subdirectory = ensure $([System.IO.Path]::Combine($scoop_startmenu_folder, $subdirectory))
    }
    create_shortcut_file $target $shortcutName $arguments $icon "$scoop_startmenu_folder\$shortcutName.lnk"
}

function create_shortcut_file([System.IO.FileInfo] $target, $shortcutName, $arguments, [System.IO.FileInfo]$icon, $path) {
    if (!$target.Exists) {
        Write-Host -f DarkRed "Creating shortcut for $shortcutName ($(fname $target)) failed: Couldn't find $target"
        return
    }
    if ($icon -and !$icon.Exists) {
        Write-Host -f DarkRed "Creating shortcut for $shortcutName ($(fname $target)) failed: Couldn't find icon $icon"
        return
    }

    $wsShell = New-Object -ComObject WScript.Shell
    $wsShell = $wsShell.CreateShortcut($path)
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
}

function remove_shortcut_file($path) {
    if (Test-Path -LiteralPath $path) {
        Write-Host "Removing shortcut $(friendly_path $path)"
        Remove-Item -LiteralPath $path -ErrorAction Stop
    }
}

# Removes the app's shortcuts if they exist
function rm_startmenu_shortcuts($manifest, $global, $arch) {
    $shortcuts = @(arch_specific 'shortcuts' $manifest $arch | Where-Object { $_ -ne $null })
    $shortcuts | ForEach-Object {
        $name = $_.item(1)
        $shortcut = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath("$(shortcut_folder $global)\$name.lnk")
        Write-Host "Removing shortcut $(friendly_path $shortcut)"
        remove_shortcut_file $shortcut
    }
    if ($shortcuts -and $app -notin @('7zip', 'git')) {
        remove_shortcut_file (desktop_shortcut_path $global $shortcuts[0].item(1))
    }
}

function uninstall_shortcut_registry_path($app, $global) {
    $root = if ($global) { 'HKLM:' } else { 'HKCU:' }
    Join-Path $root "Software\Microsoft\Windows\CurrentVersion\Uninstall\scoop_$app"
}

function write_uninstall_shortcut_entry($path, $values) {
    New-Item -Path $path -Force | Out-Null
    foreach ($name in $values.Keys) {
        Set-ItemProperty -LiteralPath $path -Name $name -Value $values[$name]
    }
}

function remove_uninstall_shortcut($app, $global) {
    if (!$app) { return }
    $path = uninstall_shortcut_registry_path $app $global
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
    }
}

function sync_uninstall_shortcut($manifest, $dir, $global, $arch, $app, $bucket) {
    if (!$app) { return }
    if (!(get_config UNINSTALL_SHORTCUT)) {
        remove_uninstall_shortcut $app $global
        return
    }

    $shortcuts = @(arch_specific 'shortcuts' $manifest $arch | Where-Object { $_ -ne $null })
    $displayName = $app
    $displayIcon = $null
    if ($shortcuts) {
        $displayName = [System.IO.Path]::GetFileName($shortcuts[0].item(1))
        $displayIcon = [System.IO.Path]::Combine($dir, $shortcuts[0].item(0))
    }
    $globalArgument = if ($global) { ' -g' } else { '' }
    $values = @{
        DisplayName = "$displayName (Scoop)"
        DisplayVersion = $manifest.version
        Publisher = if ($bucket) { $bucket } else { 'Scoop' }
        InstallLocation = $dir
        UninstallString = "cmd.exe /c `"scoop uninstall `"$app`" -p$globalArgument`""
        ModifyPath = "cmd.exe /c `"scoop reset `"$app`"`""
    }
    if ($displayIcon) { $values.DisplayIcon = $displayIcon }
    write_uninstall_shortcut_entry (uninstall_shortcut_registry_path $app $global) $values
}
