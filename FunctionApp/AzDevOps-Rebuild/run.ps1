param([string] $QueueItem, $TriggerMetadata)

$item = $QueueItem | ConvertFrom-Json

$settings = Get-Settings -organization $item.organization -project $item.project

if ($null -ne $settings.azdevops -and $null -ne $settings.azdevops.organization) {
    $organization = $settings.azdevops.organization
}
else {
    $organization = $item.organization
}

if ($null -ne $settings.azdevops -and $null -ne $settings.azdevops.project) {
    $project = $settings.azdevops.project
}
else {
    $project = $item.project
}

Write-Host "Organization: $organization; Project: $project"

function Push-GitHubComment($message) {
    Push-OutputBinding -Name githubrespond -Value @{ url = $item.commentsUrl; message = $message }
}

Write-Host "Retrieving PR from '$($item.pr)'"
$headers = @{
    Authorization = "token $($env:GITHUB_PERSONAL_ACCESS_TOKEN)"
}
$pr = Invoke-RestMethod -Uri $item.pr -Headers $headers

$cred = [pscredential]::new("empty", (ConvertTo-SecureString -String $env:DEVOPS_ACCESSTOKEN -AsPlainText -Force))

Write-Host "Retrieving statuses from '$($pr.statuses_url)'"
$statuses = (Invoke-RestMethod -Uri $pr.statuses_url -Headers $headers) | Where-Object {
    $null -ne $_.target_url -and ($_.target_url.StartsWith("https://$organization.visualstudio.com", $true, $null) -or
    ($_.target_url.StartsWith("https://dev.azure.com/$organization", $true, $null)))
}

Write-Host "Got $($statuses.Count) matching statuses"
if ($statuses.Count -eq 0) {
    $message = "@$($item.user), did not find any matching pull request checks"
    Push-GitHubComment -message $message
    return
}

foreach ($context in $item.context) {
    $status = $statuses | Where-Object { $_.context -eq $context } | Sort-Object id -Descending | Select-Object -First 1

    if ($null -eq $status) {
        $contexts = ($statuses | Select-Object context -Unique).context
        $message = "@$($item.user), did not find matching build context: ``$context``; allowed contexts: $([string]::Join(", ",$contexts))"
        Write-Error $message
        Push-GitHubComment -message $message
        return
    }

    if ($status.target_url -match "\?buildId=(?<buildId>\d*)") {
        $buildId = $matches.buildId
    }
    Write-Host "Found buildId: $buildId"
    if ($null -eq $buildId) {
        $message = "@$($item.user), could not find ``buildId`` in '$($status.target_url)'"
        Write-Error $message
        Push-GitHubComment -message $message
        return
    }

    try {
        $url = "https://dev.azure.com/$organization/$project/_apis/build/builds/$($buildId)?api-version=5.0"
        Write-Host "Getting build from: $url"
        $build = Invoke-RestMethod -Uri $url -Authentication Basic -Credential $cred
    }
    catch {
        $e = $_ | Out-String
        $e | Write-Error
        $message = "@$($item.user), could not find build at: $url, error: $e"
        Push-GitHubComment -message $message
        return
    }

    switch ($item.action) {
        "rebuild" {
            $params = @{
                Uri = "https://dev.azure.com/$organization/$project/_apis/build/builds?api-version=5.0"
                Method = "Post"
                Authentication = "Basic"
                Credential = $cred
                Body = @{
                    buildNumberRevision = [int]($build.buildNumberRevision) + 1
                    id = $build.id
                    definition = $build.definition
                    sourceVersion = $build.sourceVersion
                    sourceBranch = $build.sourceBranch
                    buildNumber = $build.buildNumber
                    parameters = $build.parameters
                    triggerInfo = $build.triggerInfo
                } | ConvertTo-Json
                ContentType = "application/json"
            }

            Write-Host "Params:"
            $params | ConvertTo-Json

            try {
                Write-Host "Starting rebuild of ``$($item.context)``"
                $null = Invoke-RestMethod @params
            }
            catch {
                $_ | Out-String | Write-Error
                $message = "@$($item.user), failed to start rebuild of ``$context``, error: $($_ | Out-String)"
                Push-GitHubComment -message $message
                return
            }
        }

        "retry" {
            try {
                Write-Host "Starting retry of ``$($item.context)``"
                $params = @{
                    Uri = "https://dev.azure.com/$organization/$project/_apis/build/builds?api-version=5.0&retry=true"
                    Method = "Patch"
                    Authentication = "Basic"
                    Credential = $cred
                }
                $null = Invoke-RestMethod @params
            }
            catch {
                $_ | Out-String | Write-Error
                $message = "@$($item.user), failed to start retry of ``$context``, error: $($_ | Out-String)"
                Push-GitHubComment -message $message
                return
            }
        }

        default {
            $message = "@$($item.user), unknown AzDevOps action ``$($item.action)``"
            Push-GitHubComment -message $message
        }
    }
}

$message = "@$($item.user), successfully started $($item.action) of ``$([string]::Join(", ", $item.context))``"
Push-GitHubComment -message $message
