using namespace System.Net
using namespace System.Web

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PoshChan-Bot received a request"

# Change to get list of authorized users from specific repo
function Test-User([string] $user) {
    return $user -in @(
        "SteveL-MSFT"
    )
}

$body = $Request.Body
$poshchanMention = "@PoshChan "

# Change to get list of action verbs mapped to webhooks
if ($body.action -eq "created") {
    $user = $body.comment.user.login
    if (Test-User $user) {
        $commentBody = $body.comment.body
        if ($commentBody.StartsWith($poshchanMention)) {
            $command = $commentBody.SubString($poshchanMention.Length)
            $pr = $body.issue.pull_request.url
            if ($null -ne $pr) {
                $output = @(
                    "Authorized User: $user"
                    "Command: $command"
                    "PR: $($body.issue.pull_request.url)"
                )
                $output = [string]::Join("`n", $output)
                $output | Write-Host
                $output = [HttpUtility]::JavaScriptStringEncode($output)

                try {
                    Invoke-RestMethod -Headers @{Authorization = "token $($env:GITHUB_PERSONAL_ACCESS_TOKEN)"} $body.issue.comments_url -Method Post -Body "{ ""body"": ""$output"" }"
                } catch {
                    $_ | Out-String | Write-Host
                }
            } else {
                Write-Host "Ignoring non-PR comment"
            }
        } else {
            Write-Host "Ignoring comment not directed @PoshChan"
        }
    } else {
        Write-Warning "Unauthorized User: $user"
    }
} else {
    Write-Host "Ignoring action $($body.action)"
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
})
