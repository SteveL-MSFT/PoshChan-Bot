# This cmdlet reads the ./.poshchan/settings.json file and parses it to a hashtable

# $PR is the URL to the Pull Request, currently only understands GitHub json
function Get-Settings($organization, $project) {
    $params = @{
        Uri = "https://api.github.com/repos/$organization/$project/contents/.poshchan/settings.json"
        Headers = @{
            Authorization = "token $($env:GITHUB_PERSONAL_ACCESS_TOKEN)"
        }
    }

    try {
        $settingsFile = Invoke-RestMethod @params
        [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($settingsFile.content)) | ConvertFrom-Json
    }
    catch {
        $_ | Out-String | Write-Error
    }
}

function Test-User($user, $settings, $setting) {
    if ($null -eq $settings.$setting) {
        Write-Error "The '$setting' section doesn't exist in settings.json"
        return $false
    }

    if ($null -eq $settings.$setting.authorized_users) {
        Write-Error "Authorized_Users is not set in '$setting' section in settings.json"
        return $false
    }

    if ($settings.$setting.authorized_users -eq "*" -or $user -in $settings.$setting.authorized_users) {
        return $true
    }

    Write-Error "User was not found in $([string]::Join(',', $settings.$setting.authorized_users))"
    $false
}

function Get-PoshChanHelp($settings, $user) {
    $sb = [System.Text.StringBuilder]::new()
    $null = $sb.Append("`nCommands available in this repo for you:`n")
    if (Test-User -User $user -Settings $settings -Setting azdevops) {
        $targets = [string]::Join(",",($settings.azdevops.build_targets.psobject.properties.name | ForEach-Object { "``$_``" }))
        $null = $sb.Append("  - ``retry <target>`` this will attempt to retry only the failed jobs for the target pipeline, ``restart`` can be used in place of ``retry```n")
        $null = $sb.Append("  - ``rebuild <target>`` this will perform a complete rebuild of the target pipeline, ``rerun`` can be used in place of ``rebuild```n")
        $null = $sb.Append("    Supported values for \<target\> which can be a comma separated list are: $targets`n")
    }

    if (Test-User -User $user -Settings $settings -Setting failures) {
        $null = $sb.Append("  - ``get failures`` this will attempt to get the latest failures for all of the target pipelines`n")
    }

    if (Test-User -User $user -Settings $settings -Setting reminders) {
        $null = $sb.Append("  - ``remind me in <value> <units>`` this will create a reminder that will be posted after the specified duration`n")
        $null = $sb.Append("    \<value\> is a number, and \<units\> can be ``minutes``, ``hours``, or ``days`` (singular or plural)`n")
    }

    $sb.ToString()
}
