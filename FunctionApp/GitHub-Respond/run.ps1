# Input bindings are passed in via param block.
param($QueueItem, $TriggerMetadata)

$url = $QueueItem.url
$message = $QueueItem.message
$reaction = $QueueItem.reaction

if ($message) {
    $filePath = $QueueItem.path

    if ($filePath) {
        $msgForm = "PR Review"
        $payload = @{
            body = ""
            event = "COMMENT"
            comments = ,@{ path = $filePath; position = 1; body = $message }
        }
    } else {
        $msgForm = "PR Comment"
        $payload = @{ body = $message }
    }

    Write-Host "Posting message as '$msgForm':`n$message"
    Write-Host "To URL: $url"

    try {
        $json = $payload | ConvertTo-Json -Compress
        Send-GitHubCommentOrReview -Url $url -Body $json
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
