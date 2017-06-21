<#
.NOTES
    Copyright (c) Microsoft Corporation.  All rights reserved.

    Use of this sample source code is subject to the terms of the Microsoft
    license agreement under which you licensed this sample source code. If
    you did not accept the terms of the license agreement, you are not
    authorized to use this sample source code. For the terms of the license,
    please see the license agreement between you and Microsoft or, if applicable,
    see the LICENSE.RTF on your install media or the root of your tools installation.
    THE SAMPLE SOURCE CODE IS PROVIDED "AS IS", WITH NO WARRANTIES.

    .SYNOPSIS
		Launch different runs. 
		
	.DESCRIPTION
		Launch different runs. 
	
    .PARAMETER RootDir
		Root directory where logs will be stored.

	.PARAMETER FullConfigFilePath
		Config file which has all the details related to the set of scenario needs to be executed using Wtt.
#>

Param(
        [string]
        $RootDir,
        [string]
        $FullConfigFilePath
    )
    <#
    .Synopsis
        Print the log message.

    .Description
        Print the log message.

    .Example
        Get-HostEdition
    #>
    function
    Log-Message(
        [string]
        $LogFilePath,
        [string]
        $Message
    )
    {
        if (Test-Path $LogFilePath)
        {
            "$(get-date -Format 'yyyy-MM-dd HH:mm:ss') $Message" | tee -FilePath $LogFilePath -Append
        }
        else
        {
            "$(get-date -Format 'yyyy-MM-dd HH:mm:ss') $Message" | Out-File -FilePath $LogFilePath -Append -Force
        }
    }

    ######################################## Script Block ######################################################
    $ScenarioExecutionBlock = {
	    Param 
	    (
            [string]
            $ConfigFile,
            [string]
            $ScenarioId,
            [string]
            $LogFolder,
            [string]
            $LogFileName
	    )

        function
        Log-Message(
            [string]
            $LogFilePath,
            [string]
            $Message
            )
        {
            if (Test-Path $LogFilePath)
            {
                "$(get-date -Format 'yyyy-MM-dd HH:mm:ss') $Message" | tee -FilePath $LogFilePath -Append
            }
            else
            {
                "$(get-date -Format 'yyyy-MM-dd HH:mm:ss') $Message" | Out-File -FilePath $LogFilePath -Append -Force
            }
        }

        [xml]$config = Get-Content $ConfigFile
        $dataStore = $config.WTTConfig.GlobalConfiguration.DataStore.Value
        $sourceDataStore = $config.WTTConfig.GlobalConfiguration.SourceDataStore.Value
        $destinationDataStore = $config.WTTConfig.GlobalConfiguration.DestinationDataStore.Value
        $scenarioTests = $config.WTTConfig.ScenarioTest

        Log-Message -LogFilePath $LogFileName -Message "Global Parameters are: "
        Log-Message -LogFilePath $LogFileName -Message "dataStore = $dataStore, sourceDataStore = $sourceDataStore "
        Log-Message -LogFilePath $LogFileName -Message "destinationDataStore = $destinationDataStore "

        #Return object initialization.
        $result=@{}
        $result.TotalCount=0
        $result.PassCount=0
        $result.FailCount=0
	    $result.OverallResult=1
	    $result.OverallTime=0

        $baseCommand = "wttCl.exe schedulejob /DataStore:$dataStore /SourceDataStore:$sourceDataStore /DestinationDataStore:$destinationDataStore "
        ForEach ($scenarioTest in $scenarioTests)
        {
            if ($scenarioTest.Id -ne $ScenarioId)
            {
                continue
            }
            Log-Message -LogFilePath $LogFileName -Message "destinationDataStore = $destinationDataStore "
            $jobDetails = $scenarioTest.JobDetails
            $machineDetails = $scenarioTest.MachineDetails
            ForEach ($job in $jobDetails.Job)
            {
                $jobDetails = ""
                if ($job.Wait)
                {
                    $jobDetails = "/Wait:$($job.Wait) " 
                }
                else
                {
                    $jobDetails = "/Wait:false " 
                }

                $jobDetails = $jobDetails + " /Job { /Id:$($job.Id) " 
        
                ForEach ($parameter in $job.Parameters.Parameter)
                {
                    $jobDetails = $jobDetails + "/Parameter { /Name:`"$($parameter.Name)`" /Value:`"$($parameter.Value)`" } "
                }

                $jobDetails = $jobDetails + " } "

                ForEach ($machine in $machineDetails.Machine)
                {
                    $jobFileName = "$LogFolder\$($scenarioTest.Name)-$($machine.Name)-$($job.Id).log"
                    $machineDetail = "/MachinePool:`"$($machine.MachinePool)`" /MachineList:$($machine.Name) /Log:`"$jobFileName`" " 
                    $command = $baseCommand + $jobDetails + $machineDetail
                    Log-Message -LogFilePath $LogFileName -Message "$($scenarioTest.Name)-$($machine.Name)-$($job.Id) command: $command "
                    # Run the command
                    $returnValue = Invoke-Command -ScriptBlock { $(cmd /c $command) }
                    Log-Message -LogFilePath $LogFileName -Message "$($scenarioTest.Name)-$($machine.Name)-$($job.Id) Job ReturnValue: $returnValue"
                    $result.TotalCount=$result.TotalCount + 1
                    if ($returnValue -Like '*ERROR*')
                    {
                        Log-Message -LogFilePath $logFileName -Message "[ERROR] $($scenarioTest.Name)-$($machine.Name)-$($job.Id) Job schedule failed with error."
                        $result.FailCount=$result.FailCount + 1
                        if ($job.Reset)
                        {
                            $jobFileName = "$LogFolder\$($scenarioTest.Name)-$($machine.Name)-$($job.Id)-reset.log"
                            $command = "wttCl.exe setmachinestatus /DataStore:$DataStore /Status:Reset /MachineName:$($machine.Name)  /Log:`"$jobFileName`" "
                            Log-Message -LogFilePath $LogFileName -Message "$($scenarioTest.Name)-$($machine.Name)-$($job.Id) command: $command "
                            $returnValue = Invoke-Command -ScriptBlock { $(cmd /c $command) }
                            Log-Message -LogFilePath $LogFileName -Message "$($scenarioTest.Name)-$($machine.Name)-$($job.Id) Machine reset : $returnValue"
                        }
                    }
                    else
                    {
                        $result.PassCount=$result.PassCount + 1
                    }
                }
            }

            if ($result.FailCount -eq 0)
            {
                $result.OverallResult=0
                Log-Message -LogFilePath $LogFileName -Message "Job schedule for scenario $($scenarioTest.Name) passed."
            }
            else
            {
                throw "Failed to schedule the job"
            }
        }
        
        return $result
    }

    ######################################## Main code Block ######################################################
    [int]$passCount = 0
    [int]$failCount = 0
    [int]$totalCount = 0

    # Check if folder exist
    if (-not (Test-Path $RootDir))
    {
        exit 1
    }

    # Create the log folder
    $logFolder = "$RootDir\log$(get-date -Format 'yyyy-MM-dd-HHmmss')"
    if (-not (Test-Path $logFolder))
    {
        New-Item -Path $logFolder -Type Directory -Force | Out-Null
    }

    $logFileName = "$logFolder\masterlog.txt"
    Log-Message -LogFilePath $logFileName -Message "Starting execution with below params: "
    Log-Message -LogFilePath $logFileName -Message "RootDir:$RootDir, FullConfigFilePath: $FullConfigFilePath"

    # Check if config file is present
    if (-not (Test-Path $FullConfigFilePath))
    {
        Log-Message -LogFilePath $logFileName -Message "[ERROR] $FullConfigFilePath file not found."
        exit 1
    }

    # Read the XML file and global parameters
    Log-Message -LogFilePath $logFileName -Message "Reading Config xmlfile."
    try
    {
        [xml]$config = Get-Content $FullConfigFilePath
        $maxTimeOut = $config.WTTConfig.GlobalConfiguration.JobTimeout.Value
        $scenarioTests = $config.WTTConfig.ScenarioTest
    }
    catch
    {
        Log-Message -LogFilePath $logFileName -Message "[ERROR] Failed to parse $FullConfigFilePath file."
    }

    # Launch all wtt scenario execution jobs
    $jobIdList=@()
    ForEach ($scenarioTest in $scenarioTests)
    {
        $set    = "abcdefghijklmnopqrstuvwxyz0123456789".ToCharArray()
        $scenarioId = $scenarioTest.Id
        $jobName = "$($scenarioTest.Name)-$scenarioId"
        Log-Message -LogFilePath $logFileName -Message "Started Job: $jobName for Scenario :$($scenarioTest.Name), Id:$scenarioId ."
		$jobDetails = Start-Job -Name $jobName -ScriptBlock $ScenarioExecutionBlock -ArgumentList $FullConfigFilePath, $scenarioId, $logFolder, $logFileName
		$jobIdList += $jobDetails.Id
        Start-Sleep -s 1
    }

    # Below section is to handle the case where number of running threads is less than appcount.
    Log-Message -LogFilePath $logFileName -Message "Waiting on all the jobs to get completed."
    Wait-Job -TimeOut $maxTimeOut -Id $jobIdList | Out-Null
    ForEach($job in Get-Job)
    {
	    $name = $($job.name)
	    $id = $($job.Id)
	    if($jobIdList.Contains($id))
	    {
            Stop-Job -Job $job | Out-Null
            $totalCount = $totalCount + 1
            $state = $($job.State)
            if (($state -ieq "Failed") -or ($state -ieq "Stopped"))
            {
                $failCount = $failCount + 1
            }
            else
            {
                $passCount = $passCount + 1
            }
            
            Stop-Job -Job $job | Out-Null
            Remove-Job -Job $job -Force | Out-Null
	    }
    }

    Log-Message -LogFilePath $logFileName -Message "Script execution finished"
    Log-Message -LogFilePath $logFileName -Message "-----------------------------------------------------------------------------------------------------------------"
    $latestRunLogs = $RootDir + "\latestRunLogs\"

    Log-Message -LogFilePath $logFileName -Message "Log files can be found here: $logFolder or $latestRunLogs"
    Log-Message -LogFilePath $logFileName -Message "Totals scenario executed # $totalCount , Pass Count # $passCount, Fail Count # $failCount"
    Log-Message -LogFilePath $logFileName -Message "-----------------------------------------------------------------------------------------------------------------"

    if (Test-Path $latestRunLogs)
    {
        Remove-item -Path $latestRunLogs -Force -Recurse
    }

    Copy-Item -Path $logFolder -Destination $latestRunLogs -Force -Recurse

    if($totalCount -eq 0)
    {
        exit -1
    }
    elseif ($failCount -ne 0)
    {
        exit -1
    }
    else
    {
        exit 0
    }



