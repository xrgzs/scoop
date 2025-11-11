# Usage: scoop search <query>
# Summary: Search available apps
# Help: Searches for apps that are available to install.
#
# If used with [query], shows app names that match the query.
#   - With 'use_sqlite_cache' enabled, [query] is partially matched against app names, binaries, and shortcuts.
#   - Without 'use_sqlite_cache', [query] can be a regular expression to match against app names and binaries.
# Without [query], shows all the available apps.
param($query)

. "$PSScriptRoot\..\lib\manifest.ps1" # 'manifest'
. "$PSScriptRoot\..\lib\versions.ps1" # 'Get-LatestVersion'
. "$PSScriptRoot\..\lib\download.ps1"

$list = [System.Collections.Generic.List[PSCustomObject]]::new()

function bin_match($manifest, $query) {
    if (!$manifest.bin) { return $false }
    $bins = foreach ($bin in $manifest.bin) {
        $exe, $alias, $args = $bin
        $fname = Split-Path $exe -Leaf -ErrorAction Stop

        if ((strip_ext $fname) -match $query) { $fname }
        elseif ($alias -match $query) { $alias }
    }

    if ($bins) { return $bins }
    else { return $false }
}

function bin_match_json($json, $query) {
    [System.Text.Json.JsonElement]$bin = [System.Text.Json.JsonElement]::new()
    if (!$json.RootElement.TryGetProperty('bin', [ref] $bin)) { return $false }
    $bins = @()
    if ($bin.ValueKind -eq [System.Text.Json.JsonValueKind]::String -and [System.IO.Path]::GetFileNameWithoutExtension($bin) -match $query) {
        $bins += [System.IO.Path]::GetFileName($bin)
    } elseif ($bin.ValueKind -eq [System.Text.Json.JsonValueKind]::Array) {
        foreach ($subbin in $bin.EnumerateArray()) {
            if ($subbin.ValueKind -eq [System.Text.Json.JsonValueKind]::String -and [System.IO.Path]::GetFileNameWithoutExtension($subbin) -match $query) {
                $bins += [System.IO.Path]::GetFileName($subbin)
            } elseif ($subbin.ValueKind -eq [System.Text.Json.JsonValueKind]::Array) {
                if ([System.IO.Path]::GetFileNameWithoutExtension($subbin[0]) -match $query) {
                    $bins += [System.IO.Path]::GetFileName($subbin[0])
                } elseif ($subbin.GetArrayLength() -ge 2 -and $subbin[1] -match $query) {
                    $bins += $subbin[1]
                }
            }
        }
    }

    if ($bins) { return $bins }
    else { return $false }
}

function search_bucket($bucket, $query) {
    $apps = Get-ChildItem (Find-BucketDirectory $bucket) -Filter '*.json' -Recurse

    $apps | ForEach-Object {
        $filepath = $_.FullName

        $json = try {
            [System.Text.Json.JsonDocument]::Parse([System.IO.File]::ReadAllText($filepath))
        } catch {
            debug "Failed to parse manifest file: $filepath (error: $_)"
            return
        }

        $name = $_.BaseName

        if ($name -match $query) {
            $list.Add([PSCustomObject]@{
                    Name     = $name
                    Version  = $json.RootElement.GetProperty('version')
                    Source   = $bucket
                    Binaries = ''
                })
        } else {
            $bin = bin_match_json $json $query
            if ($bin) {
                $list.Add([PSCustomObject]@{
                        Name     = $name
                        Version  = $json.RootElement.GetProperty('version')
                        Source   = $bucket
                        Binaries = $bin -join ' | '
                    })
            }
        }
    }
}

# fallback function for PowerShell 5
function search_bucket_legacy($bucket, $query) {
    $apps = Get-ChildItem (Find-BucketDirectory $bucket) -Filter '*.json' -Recurse

    $apps | ForEach-Object {
        $manifest = [System.IO.File]::ReadAllText($_.FullName) | ConvertFrom-Json -ErrorAction Continue
        $name = $_.BaseName

        if ($name -match $query) {
            $list.Add([PSCustomObject]@{
                    Name     = $name
                    Version  = $manifest.Version
                    Source   = $bucket
                    Binaries = ''
                })
        } else {
            $bin = bin_match $manifest $query
            if ($bin) {
                $list.Add([PSCustomObject]@{
                        Name     = $name
                        Version  = $manifest.Version
                        Source   = $bucket
                        Binaries = $bin -join ' | '
                    })
            }
        }
    }
}

function search_azure($body) {
    $api_link = 'https://scoopsearch.search.windows.net/indexes/apps/docs/search?api-version=2020-06-30'
    $api_key = 'DC6D2BBE65FC7313F2C52BBD2B0286ED'
    return Invoke-RestMethod -Uri $api_link -Method Post -Body $body -Headers @{
        'api-key'      = $api_key
        'Content-Type' = 'application/json'
    }
}
function get_large_buckets {
    $results = search_azure('{"count":true,"facets":["Metadata/Repository,count:10000"],"filter":"Metadata/OfficialRepositoryNumber eq 0","top":0}')
    $buckets = @()
    $results.'@search.facets'.'Metadata/Repository' | ForEach-Object {
        if ($_.count -gt 5000) {
            $buckets += $_.value
        }
    }
    return $buckets
}

function search_remotes($query) {
    $body = @{
        count      = $true
        search     = $query
        searchMode = 'all'
        # filter     = 'Metadata/OfficialRepositoryNumber eq 1'
        top        = 20
        select     = 'Name,Version,Metadata/Repository,Metadata/RepositoryStars'
    } | ConvertTo-Json -Compress
    $results = search_azure($body)
    $remote_list = @()
    $trash_bucket = get_large_buckets
    $results.value | ForEach-Object {
        if ($_.Metadata.Repository -notin $trash_bucket) {
            $remote_list += [PSCustomObject]@{
                Name    = $_.Name
                Version = $_.Version
                Source  = $_.Metadata.Repository
                Stars   = $_.Metadata.RepositoryStars
            }
        }
    }
    $remote_list
}

if (Get-Command 'scoop-search' -ErrorAction Ignore) {
    $scoopSearchOutput = scoop-search $query
    foreach ($line in $scoopSearchOutput -split "`n") {
        if ($line -match "'(?<bucket>.+)' bucket:") {
            $currentBucket = $matches.bucket
        } elseif ($line -match "    (?<name>.+) \((?<version>.+)\)( --> includes '(?<binary>.+)')?") {
            $list.Add([PSCustomObject]@{
                    Name     = $matches.name
                    Version  = $matches.version
                    Source   = $currentBucket
                    Binaries = if ($matches.binary) { $matches.binary } else { $null }
                })
        }
    }
} elseif (get_config USE_SQLITE_CACHE) {
    . "$PSScriptRoot\..\lib\database.ps1"
    Select-ScoopDBItem $query -From @('name', 'binary', 'shortcut') |
    Select-Object -Property name, version, bucket, binary |
    ForEach-Object {
        $list.Add([PSCustomObject]@{
                Name     = $_.name
                Version  = $_.version
                Source   = $_.bucket
                Binaries = $_.binary
            })
    }
} else {
    try {
        $query = New-Object Regex $query, 'IgnoreCase'
    } catch {
        abort "Invalid regular expression: $($_.Exception.InnerException.Message)"
    }

    $jsonTextAvailable = [System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Location) -eq 'System.Text.Json' }

    Get-LocalBucket | ForEach-Object {
        if ($jsonTextAvailable) {
            search_bucket $_ $query
        } else {
            search_bucket_legacy $_ $query
        }
    }
}

if ($list.Count -gt 0) {
    Write-Host 'Results from local buckets...'
    $list
}

if ($list.Count -eq 0) {
    $remote_results = search_remotes $query
    if (!$remote_results) {
        warn 'No matches found.'
        exit 1
    }
    Write-Host "Results from remote buckets...`n(add them using 'scoop bucket add <Source>')"
    $remote_results
}

exit 0
