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
    $null = $sb.Append("`n<details>`n<summary>")
    $null = $sb.Append("Commands available in this repo for you:")
    $null = $sb.Append("`n</summary>`n<ul>")
    if (Test-User -User $user -Settings $settings -Setting azdevops) {
        $targets = [string]::Join(",",($settings.azdevops.build_targets.psobject.properties.name | ForEach-Object { "``$_``" }))
        Add-LineItem -stringBuilder $sb -Message '`retry &lt;target&gt;` this will attempt to retry only the failed jobs for the target pipeline, `restart` can be used in place of `retry`'
        Add-LineItem -stringBuilder $sb -Message "``rebuild &lt;target&gt;`` this will perform a complete rebuild of the target pipeline, ``rerun`` can be used in place of ``rebuild`` Supported values for &lt;target&gt; which can be a comma separated list are: $targets"
    }

    if (Test-User -User $user -Settings $settings -Setting failures) {
        Add-LineItem -stringBuilder $sb -Message "``get failures`` this will attempt to get the latest failures for all of the target pipelines"
    }

    if (Test-User -User $user -Settings $settings -Setting reminders) {
        Add-LineItem -stringBuilder $sb -Message "``remind me in &lt;value&gt; &lt;units&gt;`` this will create a reminder that will be posted after the specified duration &lt;value&gt; is a number, and &lt;units&gt; can be ``minutes``, ``hours``, or ``days`` (singular or plural)"
    }

    $null = $sb.Append("`n</ul>`n</details>")

    $sb.ToString()
}

function Add-LineItem($message,[System.Text.StringBuilder]$stringBuilder)
{
    $null = $stringBuilder.Append("<li>`n")
    $htmlMessage = Convert-CodeMarkdownToHTML -markdown $message
    $null = $stringBuilder.Append($htmlMessage)
    $null = $stringBuilder.Append("`n")
    $null = $stringBuilder.Append("</li>`n")
}

function Convert-CodeMarkdownToHTML
{
    param(
        $markdown
    )

    if($markdown -notmatch '`')
    {
        return $markdown
    }

    $markdownParts = $markdown -split '`'

    if($markdownParts.Count % 2 -ne 1)
    {
        throw 'Invalid formed markdown'
    }

    $sb = [System.Text.StringBuilder]::new()

    $max = ($markdownParts.Count -1)
    0..($markdownParts.Count -1)| ForEach-Object {
        $part = $_
        if($part -eq 0)
        {
            $null=$sb.Append($markdownParts[$part])
        }
        else
        {
            switch($_ % 2)
            {
                1 {
                    $null=$sb.Append('<code>')
                    $null=$sb.Append($markdownParts[$part].replace('<','&lt;').replace('>','&gt;'))
                }
                0 {
                    $null=$sb.Append('</code>')
                    $null=$sb.Append($markdownParts[$part].replace('\<','&lt;').replace('\>','&gt;'))
                }
            }
        }
    }
    return $sb.ToString()
}