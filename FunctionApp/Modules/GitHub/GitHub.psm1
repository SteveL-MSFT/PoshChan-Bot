$headers = @{
    Authorization = "token $($env:GITHUB_PERSONAL_ACCESS_TOKEN)"
}

function Get-GitHubPullRequest($PullRequestUrl) {
    try {
        Invoke-RestMethod -Uri $PullRequestUrl -Headers $headers
    }
    catch {
        $_ | Out-String | Write-Error
        throw $_
    }
}

function Get-GitHubPullRequestDiff($PullRequestDiffUrl) {
    try {
        Invoke-RestMethod -Uri $PullRequestDiffUrl -Headers $headers
    }
    catch {
        $_ | Out-String | Write-Error
        throw $_
    }
}

function Get-GitHubPullRequestStatuses($PullRequestStatusesUrl, $Organization) {
    try {
        $statuses = Invoke-RestMethod -Uri $PullRequestStatusesUrl -Headers $headers
        $statuses | Where-Object {
            $null -ne $_.target_url -and ($_.target_url.StartsWith("https://$organization.visualstudio.com", $true, $null) -or
            ($_.target_url.StartsWith("https://dev.azure.com/$organization", $true, $null)))
        } | Sort-Object updated_at | Sort-Object context -Unique
    }
    catch {
        $_ | Out-String | Write-Error
        throw $_
    }
}

function Send-GitHubCommentOrReview($Url, $Body) {
    try {
        $null = Invoke-RestMethod -Headers $headers -Uri $url -Method Post -Body $Body
    }
    catch {
        $_ | Out-String | Write-Error
        throw $_
    }
}

function Send-GitHubReaction($Url, $Reaction) {
    $myHeaders = $headers
    $myHeaders += @{ Accept = 'application/vnd.github.squirrel-girl-preview+json'} # needed for preview of Reactions API

    $body = @{ content = $Reaction } | ConvertTo-Json

    try {
        $null = Invoke-RestMethod -Headers $myHeaders -Uri "$url/reactions" -Method Post -Body $body
    }
    catch {
        $_ | Out-String | Write-Error
        throw $_
    }
}
