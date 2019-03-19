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
        "TravisEz13"
        "anmenaga"
        "daxian-dbw"
        "adityapatwardhan"
        "iSazonov"
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
    Send-Ok
    return
}

$commentBody = $body.comment.body
if (!($commentBody.StartsWith($poshchanMention))) {
    Send-Ok
    return
}

$user = $body.comment.user.login
if (!(Test-User $user)) {
    Write-Warning "Unauthorized User: $user"
    Send-Ok
    return
}

$pr = $body.issue.pull_request.url
if ($null -eq $pr) {
    Write-Warning "Ignoring non-PR comment"
    Send-Ok
    return
}

$organization = $body.repository.owner.login
$project = $body.repository.name

Get-Config -organization $organization -project $project

$command = $commentBody.SubString($poshchanMention.Length)

switch -regex ($command.TrimEnd()) {
    "Please rebuild (?<target>.+)" {

        $targets = $matches.target.Split(",")

        $invalid = $target | Where-Object { $global:PoshChan_Settings.build_targets.Keys -notcontains $_ }
        if ($invalid) {
            $supported = [string]::Join(",", ($global:PoshChan_Settings.build_targets.Keys | ForEach-Object { "``$_``" }))
            $message = "@$user, I do not understand the build target(s) '$([string]::Join(",",$invalid))'; I only allow $supported"
            Push-OutputBinding -Name githubrespond -Value @{ url = $body.issue.comments_url; message = $message }
            break
        }

        $resolvedTargets = [System.Collections.ArrayList]::new()
        foreach ($target in $targets) {
            if ($target.Count -gt 1) {
                foreach ($subTarget in $target) {
                    $null = $resolvedTargets.Add($subTarget)
                }
            }
            else {
                $null = $resolvedTargets.Add($target)
            }
        }

        foreach ($target in ($resolvedTargets | Select-Object -Unique)) {
            $queueItem = @{
                context = $global:PoshChan_Settings.build_targets.$target
                pr = $pr
                commentsUrl = $body.issue.comments_url
                user = $user
                organization = $organization
                project= $project
            }

            Write-Host "Queuing rebuild for '$($queueItem.context)'"
            Push-Queue -Queue azdevops-rebuild -Object $queueItem
        }

        break
    }

    "Please remind me in (?<time>\d+) (?<units>.+)" {
        [int]$time = $matches.time
        $units = $matches.units

        switch -regex ($units.ToLower()) {
            "minute(s?)" {
                $timeSeconds = $time * 60
                break
            }

            "hour(s?)" {
                $timeSeconds = $time * 60 * 60
                break
            }

            "day(s?)" {
                $timeSeconds = $time * 60 * 60 * 24
                break
            }

            default {
                $message = "@$user, I do not understand '$units'; I only allow ``minutes``,``hours``, and ``days``"
                Push-OutputBinding -Name githubrespond -Value @{ url = $body.issue.comments_url; message = $message }
                break
            }
        }

        $message = "@$user, will remind you in $time $units"
        Push-Queue -Queue github-respond -Object @{ url = $body.issue.comments_url; message = $message }

        $message = "@$user, this is the reminder you requested $time $units ago"
        Push-Queue -Queue github-respond -Object @{ url = $body.issue.comments_url; message = $message } -VisibilitySeconds $timeSeconds
    }

    default {
        $message = "@$user, I do not understand: $command"
        Push-OutputBinding -Name githubrespond -Value @{ url = $body.issue.comments_url; message = $message }
        break
    }
}

Send-Ok
