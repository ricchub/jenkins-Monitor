
[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [String]
    $Username,
    [Parameter(Mandatory=$true)]
    [String]
    $Token,
    [Parameter(Mandatory=$true)]
    [validateSet("PROD", "DEV")]
    [String]
    $Env,
    [switch]
    $CheckOnly
    
)

# Log Writer Function
function Write-Log 
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [String]
        $Message
    )
    
    $log = "$PSScriptRoot\JenkinsMonitor.log" 
    Add-Content -path $log "$(Get-Date): $Message"
}

# Jenkins API Call Function
function Get-JenkinsAgent
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [String]
        $endpoint,
        [Parameter(Mandatory=$true)]
        [String]
        $AgentName,
        [Parameter(Mandatory=$true)]
        [String]
        $UserName,
        [Parameter(Mandatory=$true)]
        [String]
        $Token
    )

    $request        = "$($endpoint)/computer/$($AgentName)/api/json?pretty=true"
    $pair           = "$($UserName):$Token"
    $encodedCreds   = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))
    $headers        = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Authorization", "Basic $encodedCreds")
    
    $response = Invoke-RestMethod $request -Method 'GET' -Headers $headers 
    
    Return $response
}   

# Invoke a Jenkins Service Restart
Function Invoke-ServiceRestart
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [String]
        $ComputerName,
        [Parameter(Mandatory=$true)]
        [String]
        $serviceName
    )
    
    write-log -Message "Invoking service restart on: $computerName"
    write-log -Message "Restarting service: $serviceName"

    Invoke-Command -computername $computername -Args $serviceName {
        
        Stop-Service -Name $args
        Start-Service -Name $args
    }

}

# Email sender function, If a Agent has gone down, send an email alert
function Send-StatusEmail
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [psObject]
        $Agent,
        [Parameter(Mandatory=$true)]
        [string]
        $from
    )
    
    $subject = "$title $($agent.displayName)"
    $body = "
    Agent: $($agent.displayName)
    Time: $(Get-Date)
    Description: $($agent.Description)
    Labels: $($agent.AssignedLabels | Select-object -ExpandProperty Name)
    OfflineCause: $($agent.OfflineCause)
    OfflineCauseReason: $($agent.offlineCauseReason)
    
    "
    write-log -Message "Sending Status Email to: email@domain.com"
    Send-MailMessage -From $from -To "email.domain.com" -Subject $subject -Body $body -SmtpServer imail.domain.COM
}

# Set environment variables
function Get-Environment 
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [String]
        $environment
    )

    $inputFile = "Agent-Input-$($environment).csv"

    switch($environment)
    {
        "PROD" { $endpoint = "https://endpoint.prod.domain.com";    $from = "Jenkins-Monitor@domain.com";    $title = "Jenkins Agent Offline:" }
        "DEV"  { $endpoint = "https://endpoint.dev.com"; 			$from = "Jenkins-MonitorLab@domain.com"; $title = "Service restart Invoked:" }
    }

    $envVars = @{
        inputFile   = $inputFile
        endpoint    = $endpoint
        from        = $from
        $title      = $title
    }

    return $envVars
}

# Set environment variables, import host data
$envVars    = Get-Environment -environment $env
$hostArray  = Import-csv -path "$PSScriptRoot\$($envVars.inputFile)"

# Loop hosts from array and check offline status - If Offline, Send to Invoke-ServiceRestart and send email notification
<##>
foreach($item in $hostArray)
{
    write-log "Retrieving Agent: $($item.AgentName)"

    $agent = Get-JenkinsAgent -AgentName $item.AgentName -UserName $userName -Token $token -endpoint $envVars.endpoint

    write-log "Description: $($agent.Description)"
    write-log "Labels: $($agent.AssignedLabels | Select-object -ExpandProperty Name)"
    write-log "Agent Offline: $($agent.Offline)"
    
    
    if($agent.offline -eq "True")
    {
        write-log "Offline Cause: $($agent.offlineCause)"
        write-log "Offline Cause Reason: $($agent.offlineCauseReason)"

        if(-not $checkOnly)
        {
            Invoke-ServiceRestart -computername $item.computerName -serviceName $item.ServiceName
        }

        Send-StatusEmail -Agent $agent -From $from -Title $title
    }

}


