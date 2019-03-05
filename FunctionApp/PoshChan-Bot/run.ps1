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

function Send-Ok {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
    })
}

$body = $Request.Body
$poshchanMention = "@PoshChan "

# Don't act on edited comments
if ($body.action -ne "created") {
    Write-Warning "Ignoring action $($body.action)"
    Send-Ok
    return
}

$user = $body.comment.user.login
if (!Test-User $user) {
    Write-Warning "Unauthorized User: $user"
    Send-Ok
    return
}

$commentBody = $body.comment.body
if (!$commentBody.StartsWith($poshchanMention)) {
    Write-Warning "Ignoring comment not directed @PoshChan"
    Send-Ok
    return
}

$pr = $body.issue.pull_request.url
if ($null -eq $pr) {
    Write-Warning "Ignoring non-PR comment"
    Send-Ok
    return
}

$command = $commentBody.SubString($poshchanMention.Length)

switch -regex ($command.TrimEnd()) {
    "Please rebuild (?<context>.*)" {
        $queueItem = @{
            context = $matches.context
            pr = $pr
            commentsUrl = $body.issue.comments_url
        }

        Push-OutputBinding -Name azdevops-rebuild -Value $queueItem
        break
    }

    default {
        $message = "I do not understand the command: $command"
        Push-OutputBinding -Name github-respond -Value @{ url = $body.issue.comments_url; message = $message }
        break
    }
}

Send-Ok
