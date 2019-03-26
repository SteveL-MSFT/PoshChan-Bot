param([string] $QueueItem, $TriggerMetadata)

$item = $QueueItem | ConvertFrom-Json

$settings = Get-Settings -organization $item.organization -project $item.project

$organization, $project = Get-DevOpsOrgAndProject -Settings $settings -DefaultOrganization $item.organization -DefaultProject $item.project

Write-Host "Organization: $organization; Project: $project"

function Push-GitHubComment($message) {
    Push-OutputBinding -Name githubrespond -Value @{ url = $item.commentsUrl; message = $message }
}

Write-Host "Retrieving PR from '$($item.pr)'"
$pr = Get-GitHubPullRequest -PullRequestUrl $item.pr

Write-Host "Retrieving statuses from '$($pr.statuses_url)'"
$statuses = Get-GitHubPullRequestStatuses -PullRequestStatusesUrl $pr.statuses_url -Organization $organization

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
        Write-Host "Starting rebuild of ``$($item.context)``"
        $build = Get-DevOpsBuild -Organization $organization -Project $project -BuildId $buildId
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
            try {
                Invoke-DevOpsRebuild -Organization $organization -Project $project -Build $build
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
                Invoke-DevOpsRetry -Organization $organization -Project $project -BuildId $buildId
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
