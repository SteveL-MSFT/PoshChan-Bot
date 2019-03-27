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
    if ($null -eq $settings.$setting -or $null -eq $settings.$setting.authorized_users) {
        return $false
    }

    if ($settings.$setting -eq "*" -or $user -in $settings.$setting.authorized_users) {
        return $true
    }

    $false
}
