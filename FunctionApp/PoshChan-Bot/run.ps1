using namespace System.Net
using namespace System.Web

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PoshChan-Bot received a request"

$debugTrace = $false
$body = $Request.Body

function Write-Trace($message) {
    if ($debugTrace) {
        Write-Host $message
    }
}

function Push-GitHubComment($message, $url) {
    if ($null -eq $url) {
        $url = $body.issue.comments_url
    }

    Push-Queue -Queue github-respond -Object @{ url = $url; message = $message }
    #Push-OutputBinding -Name githubrespond -Value @{ url = $url; message = $message }
}

function Send-Ok {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
    })
}

$githubEvent = $Request.Headers."X-GitHub-Event"
Write-Host "Received a '$githubEvent' event"

switch ($githubEvent) {

    "issue_comment" {
        $name = $Request.Query.Name
        if ($null -ne $name) {
            $poshchanMention = "@$name "
        }
        else {
            $poshchanMention = "@PoshChan "
        }

        if ($null -ne $Request.Query.DebugTrace) {
            $debugTrace = $true
        }

        $commentBody = $body.comment.body
        if (!($commentBody.StartsWith($poshchanMention, $true, $null))) {
            Write-Trace "Skipping message not sent to @PoshChan"
            Send-Ok
            return
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

        if (-not $command.StartsWith("Please ", $true, $null)) {
            $message = "@$user, all requests start with the magic word ``Please``."
            Push-GitHubComment -message $message
            Send-Ok
            return
        }

        switch -regex ($command.TrimEnd()) {
            "Please get (last )?(test )?failures" {
                if (Test-User -User $user -Settings $settings -Setting failures) {
                    $message = "@$user, you are not authorized to request test failures"
                    Push-GitHubComment -message $message
                    break
                }

                $githubPr = Get-GitHubPullRequest -PullRequestUrl $pr
                Write-Host "Using statuses url: $($githubPr.statuses_url)"

                $statuses = Get-GitHubPullRequestStatuses -PullRequestStatusesUrl $githubPr.statuses_url -Organization $organization
                Write-Host "Got '$($statuses.count)' statuses returned"

                foreach ($status in $statuses) {
                    if ($status.target_url -match "^.*?\?buildId=(?<buildId>[0-9]+)") {
                        $buildId = $matches.buildId
                    }
                    else {
                        Write-Error "Could not extract buildId from '$($status.Body.target_url)'"
                        break
                    }

                    $devOpsOrganization, $devOpsProject = Get-DevOpsOrgAndProject -Settings $settings -DefaultOrganization $organization -DefaultProject $project
                    $message = Get-DevOpsTestFailuresMessage -User $user -Organization $devOpsOrganization -Project $devOpsProject -BuildId $buildId
                    if ($message) {
                        Push-GitHubComment -message $message -url $githubPr.comments_url
                    }
                }
            }

            "Please (?<action>rebuild|rerun|retry) (?<target>.+)" {
                if (Test-User -User $user -Settings $settings -Setting azdevops) {
                    $message = "@$user, you are not authorized to request a rebuild"
                    Push-GitHubComment -message $message
                    break
                }

                $action = $matches.action.ToLower()
                # rerun == rebuild
                if ($action -eq "rerun") {
                    $action = "rebuild"
                }

                $targets = $matches.target.Split(",").Trim()
                $build_targets = @($settings.azdevops.build_targets.psobject.properties.name)
                Write-Host "Found build_targets: $([string]::Join(',',$build_targets))"
                $invalid = $targets | Where-Object { $build_targets -notcontains $_ }
                if ($invalid) {
                    $supported = [string]::Join(", ", ($build_targets | ForEach-Object { "``$_``" }))
                    $message = "@$user, I do not understand the build target(s) ``$([string]::Join(", ",$invalid))``; I only allow $supported"
                    Push-GitHubComment -message $message
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
                    Push-GitHubComment -message $message
                    break
                }

                $queueItem = @{
                    context = $context
                    action = $action
                    pr = $pr
                    commentsUrl = $body.issue.comments_url
                    user = $user
                    organization = $organization
                    project = $project
                }

                Write-Host "Queuing $action for '$([string]::Join(", ",$context))'"
                Push-Queue -Queue azdevops-rebuild -Object $queueItem
                break
            }

            "Please remind me in (?<time>\d+) (?<units>.+)" {
                if (Test-User -User $user -Settings $settings -Setting reminders) {
                    $message = "@$user, you are not authorized to request reminders"
                    Push-GitHubComment -message $message
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
                        Push-GitHubComment -message $message
                        break
                    }
                }

                $message = "@$user, will remind you in $time $units"
                Push-GitHubComment -message $message

                $message = "@$user, this is the reminder you requested $time $units ago"
                Push-Queue -Queue github-respond -Object @{ url = $body.issue.comments_url; message = $message } -VisibilitySeconds $timeSeconds
                break
            }

            default {
                $message = "@$user, I do not understand: $command"
                Push-GitHubComment -message $message
                break
            }
        }
    }

    "status" {
        if ($Request.Body.state -eq "failure") {
            $githubOrganization, $githubProject = $Request.Body.name.Split("/")
            Write-Host "GitHub org: $githubOrganization, project: $githubProject"

            $committer = $request.body.commit.committer.login
            if (Test-User -User $committer -Settings $settings -Setting failures) {
                Write-Error "@$committer is not authorized for automatic test failures"
                break
            }

            if ($Request.Body.target_url -match "^.*?\?buildId=(?<buildId>[0-9]+)") {
                $buildId = $matches.buildId
            }
            else {
                Write-Error "Could not extract buildId from '$($Request.Body.target_url)'"
                break
            }

            $devOpsOrganization, $devOpsProject = Get-DevOpsOrgAndProject -Settings $settings -DefaultOrganization $githubOrganization -DefaultProject $githubProject
            $message = Get-DevOpsTestFailuresMessage -User $committer -Organization $devOpsOrganization -Project $devOpsProject -BuildId $buildId
            $build = Get-DevOpsBuild -Organization $devOpsOrganization -Project $devOpsProject -BuildId $buildId
            $prId = $build.triggerInfo."pr.number"
            Write-Host "Found GitHub PR: $prId"
            $prUrl = "https://api.github.com/repos/$githubOrganization/$githubProject/issues/$prId"
            Write-Host "Getting GitHub PR from: $prUrl"
            $githubPr = Get-GitHubPullRequest -PullRequestUrl $prUrl
            Push-GitHubComment -message $message -url $githubPr.comments_url
            break
        }
    }

    default {
        Write-Error "Unknown event type: $githubEvent"
    }
}

Send-Ok
