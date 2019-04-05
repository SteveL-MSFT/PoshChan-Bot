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

    Write-Error "$user not found in $([string]::Join(',', $settings.$setting.authorized_users))"
    $false
}

function Get-PoshChanHelp($settings, $user) {
    $sb = [System.Text.StringBuilder]::new()
    $sb.Append("Commands available in this repo for you:`n")
    if ($null -ne $settings.azdevops -and $null -ne $settings.azdevops.authorized_users -and $user -in $settings.azdevops.authorized_users) {
        $targets = [string]::Join(",",$settings.azdevops.build_targets.psobject.properties.name)
        $sb.Append("  - ``retry <target>`` this will attempt to retry only the failed jobs for the target pipeline`n")
        $sb.Append("  - ``rebuild <target>`` this will perform a complete rebuild of the target pipeline, ``rerun`` can be used in place of ``rebuild```n")
        $sb.Append("    Supported values for <target> which can be a comma separated list are: $targets`n")
    }

    if ($null -ne $settings.failures -and $null -ne $settings.failures.authorized_users -and $user -in $settings.failures.authorized_users) {
        $sb.Append("  - ``get failures`` this will attempt to get the latest failures for all of the target pipelines`n")
    }

    if ($null -ne $settings.reminders -and $null -ne $settings.reminders.authorized_users -and $user -in $settings.reminders.authorized_users) {
        $sb.Append("  - ``remind me in <value> <units>`` this will create a reminder that will be posted after the specified duration`n")
        $sb.Append("    <value> is a number, and <units> can be `minutes`, `hours`, or `days` (singular or plural)`n")
    }

    $sb.ToString()
}
