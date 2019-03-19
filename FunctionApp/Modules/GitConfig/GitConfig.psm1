# This cmdlet reads the ./.poshchan/settings.json file and parses it to a hashtable

# $PR is the URL to the Pull Request, currently only understands GitHub json
function Get-Config($organization, $project) {
    $params = @{
        $uri = "https://api.github.com/repos/$organization/$project/contents/.poshchan/settings.json"
        $headers = @{
            Authorization = "token $($env:GITHUB_PERSONAL_ACCESS_TOKEN)"
        }
    }

    try {
        $settingsFile = Invoke-RestMethod @params
        [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($settingsFile.content)) | ConvertFrom-Json -AsHashtable
    }
    catch {
        $_ | Out-String | Write-Error
    }
}
