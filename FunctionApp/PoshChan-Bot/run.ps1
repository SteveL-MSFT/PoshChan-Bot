using namespace System.Net
using namespace System.Web

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PoshChan-Bot received a request"

$staging = $false

function Write-Trace($message) {
    if ($staging) {
        Write-Host $message
    }
}

function Send-Ok {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
    })
}

$body = $Request.Body

$name = $Request.Query.Name
if ($null -ne $name) {
    $poshchanMention = $name
}
else {
    $poshchanMention = "@PoshChan "
}

$commentBody = $body.comment.body
if (!($commentBody.StartsWith($poshchanMention)) -and !($commentBody.StartsWith($poshchanStagingMention))) {
    Write-Trace "Skipping message not sent to @PoshChan"
    Send-Ok
    return
}
elseif ($commentBody.StartsWith($poshchanStagingMention)) {
    $staging = $true
}

# Don't act on edited comments
if ($body.action -ne "created") {
    Write-Trace "Skipping message with action '$($body.action)'"
    Send-Ok
    return
}

$organization = $body.repository.owner.login
$project = $body.repository.name
if ($null -eq $organization -or $null -eq $project) {
    Write-Error "Organization or Project was null"
    Send-Ok
    return
}

$settings = Get-Settings -organization $organization -project $project

$user = $body.comment.user.login
$pr = $body.issue.pull_request.url
if ($null -eq $pr) {
    Write-Warning "Ignoring non-PR comment"
    Send-Ok
    return
}

$command = $commentBody.SubString($poshchanMention.Length)

switch -regex ($command.TrimEnd()) {
    "Please rebuild (?<target>.+)" {

        if ($null -eq $settings.azdevops -or $null -eq $settings.azdevops.authorized_users) {
            $message = "@$user, rebuilds are not enabled for this repo."
            Push-OutputBinding -Name githubrespond -Value @{ url = $body.issue.comments_url; message = $message }
        }

        $authorized_users = $settings.azdevops.authorized_users
        if ($authorized_users -ne "*" -and $user -notin $authorized_users) {
            $message = "@$user, you are not authorized to request a rebuild"
            Push-OutputBinding -Name githubrespond -Value @{ url = $body.issue.comments_url; message = $message }
            break
        }
        elseif ($null -eq $authorized_users) {
            $message = "@$user, authorized users for ``Build Targets`` hasn't been set, so this action is not allowed."
            Push-OutputBinding -Name githubrespond -Value @{ url = $body.issue.comments_url; message = $message }
            break
        }

        $targets = $matches.target.Split(",").Trim()
        $build_targets = @($settings.azdevops.build_targets.Keys)
        Write-Host "Found build_targets: $([string]::Join(',',$build_targets))"
        $invalid = $targets | Where-Object { $build_targets -notcontains $_ }
        if ($invalid) {
            $supported = [string]::Join(", ", ($build_targets | ForEach-Object { "``$_``" }))
            $message = "@$user, I do not understand the build target(s) ``$([string]::Join(", ",$invalid))``; I only allow $supported"
            Push-OutputBinding -Name githubrespond -Value @{ url = $body.issue.comments_url; message = $message }
            break
        }

        $resolvedTargets = [System.Collections.ArrayList]::new()
        foreach ($target in $targets) {
            $context = $settings.azdevops.build_targets.$target
            if ($context.Count -gt 1) {
                foreach ($subTarget in $context) {
                    $resolvedTargets += $subTarget
                }
            }
            else {
                $resolvedTargets += $context
            }
        }

        $context = $resolvedTargets | Select-Object -Unique
        if ($null -eq $context) {
            $message = "@$user, could not find a matching build target"
            Push-OutputBinding -Name githubrespond -Value @{ url = $body.issue.comments_url; message = $message }
            break
        }

        $queueItem = @{
            context = $context
            pr = $pr
            commentsUrl = $body.issue.comments_url
            user = $user
            organization = $organization
            project = $project
        }

        Write-Host "Queuing rebuild for '$([string]::Join(", ",$context))'"
        Push-Queue -Queue azdevops-rebuild -Object $queueItem

        break
    }

    "Please remind me in (?<time>\d+) (?<units>.+)" {

        if ($null -eq $settings.reminders -or $null -eq $settings.reminders.authorized_users) {
            $message = "@$user, reminders are not enabled for this repo."
            Push-OutputBinding -Name githubrespond -Value @{ url = $body.issue.comments_url; message = $message }
        }

        $authorized_users = $settings.reminders.authorized_users
        if ($authorized_users -ne "*" -and $user -notin $authorized_users) {
            $message = "@$user, you are not authorized to request a reminder"
            Push-OutputBinding -Name githubrespond -Value @{ url = $body.issue.comments_url; message = $message }
            break
        }
        elseif ($null -eq $authorized_users) {
            $message = "@$user, authorized users for ``Reminders`` hasn't been set, so this action is not allowed."
            Push-OutputBinding -Name githubrespond -Value @{ url = $body.issue.comments_url; message = $message }
            break
        }

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
