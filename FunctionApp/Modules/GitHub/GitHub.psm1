$headers = @{
    Authorization = "token $($env:GITHUB_PERSONAL_ACCESS_TOKEN)"
}

function Get-GitHubPullRequest($PullRequestUrl) {
    Invoke-RestMethod -Uri $PullRequestUrl -Headers $headers
}

function Get-GitHubPullRequestStatuses($PullRequestUrl) {
    Invoke-RestMethod -Uri $PullRequestUrl.statuses_url -Headers $headers | Where-Object {
        $null -ne $_.target_url -and ($_.target_url.StartsWith("https://$organization.visualstudio.com", $true, $null) -or
        ($_.target_url.StartsWith("https://dev.azure.com/$organization", $true, $null)))
    }
}

function Send-GitHubComment($Url, $Body) {
    $null = Invoke-RestMethod -Headers $headers -Uri $url -Method Post -Body $Body
}
