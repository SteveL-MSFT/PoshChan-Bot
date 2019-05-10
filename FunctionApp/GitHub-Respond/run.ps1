# Input bindings are passed in via param block.
param($QueueItem, $TriggerMetadata)

$url = $QueueItem.url
$message = $QueueItem.message
$reaction = $QueueItem.reaction

if ($message) {
    Write-Host "Posting message:`n$message"
    Write-Host "To URL: $url"

    $json = @{
        body = $message
    } | ConvertTo-Json -Compress

    try {
        Send-GitHubComment -Url $url -Body $json
    } catch {
        $_ | Out-String | Write-Error
    }
}
elseif ($reaction) {
    Write-Host "Posting reaction: $reaction"
    Write-Host "To URL: $url"

    try {
        Send-GitHubReaction -Url $url -Reaction $reaction
    } catch {
        $_ | Out-String | Write-Error
    }
}
else {
    Write-Error "Message and Reaction is missing"
}
