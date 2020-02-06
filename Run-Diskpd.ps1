<#
.Synopsis
   Performs Disk I/O Testing on Computer Partitions
.DESCRIPTION
  This script is meant to be used in conjuction with Diskspd (https://github.com/microsoft/diskspd)
  This script performs disk performance I/O testing in 3 formats: Read Testing, Write Testing, or Standard Read/Write Testing(77:25 read/write ratio)
  After tests, it returns results and optionally outputs to file. 

.PARAMETER DISK
.EXAMPLE
   .\Run-Diskpd.ps1 -Drive C:\ -TestType All -Seconds 5

   This example will test the C: Drive with all three test types, running disk I/O testing for 5 Seconds per type.
.EXAMPLE
   .\Run-Diskpd.ps1 -Drive C:\ -TestType Standard -Seconds 10

   This example will test drive C: with the Standard test type, running disk I/O for 10 seconds.
.EXAMPLE
   .\Run-Diskpd.ps1 -AllDrives -TestType Read -OutFile -Seconds 10

   This example will test all drives on the server with the Read type and output to a file. The test will run for 10 seconds per test.
   (for instance, if the server has 5 total Drives, the test will run 10 seconds per drive)
.EXAMPLE
   .\Run-Diskpd.ps1 -AllDrives -TestType Read,Write -OutFile -Seconds 10

   This example will test all drives on the server with Read and Write test types and output each test to a file.
   The test will run 10 seconds per test
   (for instance, if the server has 5 total drives, the test will run 20 seconds per drive. 10 seconds for read, then 10 seconds for write. NOTE: each test has a separate warmup and cooldown time)
#>
    [CmdletBinding(DefaultParameterSetName='-AllDrives')]
    Param
    (
        # Performs a disk I/O Test on all drives on the server
        [Parameter(Position=0,ParameterSetName='-AllDrives')]
        [switch]$AllDrives,

        # Performs Read-Only, Write-Only, Or a mix of read/write(75/25) tests. Selecting all will perform all 3 tests. Note that you can combine tests. ex: -Testtype Read,Write
        [ValidateSet('Read','Write','Standard','All')]
        [string[]]$TestType = 'both',

        # Outputs the results to the root directory of the script as a text file.
        [switch]$OutFile = $false,

        # Time (in seconds) to run the test. default is 30 seconds. Note: there is a Warm-up and Cooldown period added to the test time.
        [int]$Seconds = 30
    )

        DynamicParam
        {
            if(!$AllDrives)
            {
                # Set the dynamic parameters' name
                $ParameterName = 'Drive'
            
                # Create the dictionary 
                $RuntimeParameterDictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary

                # Create the collection of attributes
                $AttributeCollection = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
            
                # Create and set the parameters' attributes
                $ParameterAttribute = New-Object System.Management.Automation.ParameterAttribute
                $ParameterAttribute.Mandatory = $true
                $ParameterAttribute.Position = 0
                $ParameterAttribute.HelpMessage = "Dynamically Iterates through available drives to test I/O."
                $ParameterAttribute.ParameterSetName = 'Drive'
                $ParameterAttribute.DontShow = $false

                # Add the attributes to the attributes collection
                $AttributeCollection.Add($ParameterAttribute)

                # Generate and set the ValidateSet 
                $drives = Get-WmiObject -Class win32_logicaldisk -Filter "DriveType='3'" | Select-Object -ExpandProperty DeviceID | ForEach-Object {$drive = -join ( $_,"\");if(Test-Path -Path $drive){$drive}}

                # Add the ValidateSet to the attributes collection
                $ValidateSetAttribute = New-Object System.Management.Automation.ValidateSetAttribute($drives)

                # Add the ValidateSet to the attributes collection
                $AttributeCollection.Add($ValidateSetAttribute)

                # Create and return the dynamic parameter
                $RuntimeParameter = New-Object System.Management.Automation.RuntimeDefinedParameter($ParameterName, [string[]], $AttributeCollection)
                $RuntimeParameterDictionary.Add($ParameterName, $RuntimeParameter)
                return $RuntimeParameterDictionary
            }
        }


    Begin
    {
        #Priviledge Check
        $user = [Security.Principal.WindowsIdentity]::GetCurrent();
        if((New-Object Security.Principal.WindowsPrincipal $user).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator) -eq $False) {
	        throw ("Administrators privilege is required!")
	          
        }
        $path = $PSScriptRoot
        Write-Verbose "Path is $path"
        #Check for diskpd utility and stop if it does not exist.
        if(!(Test-Path "$path\diskspd.exe"))
        {
            $dir = Get-ChildItem $PSScriptRoot | select -ExpandProperty FullName -First 10 | Out-String
            throw "Diskpd.exe not found in directory: $PSScriptRoot`nPlease ensure that the script is run from the same directory as diskpd.exe!!!`n DIRECTORY CONTENTS:`n$dir"
        }
        $global:boundparams = $PSBoundParameters
        # use 1 thread per core
        $thread = "-t" + ((Get-WmiObject win32_processor).NumberofCores | Measure-Object -Sum | Select-Object -ExpandProperty sum)

        $ServerDisks = Get-WmiObject -Class win32_logicaldisk -Filter "DriveType='3'"
        Write-Verbose $($ServerDisks | select DeviceID,DriveType,VolumeName | Out-String)

        # Helper Functions
        Function Test-Disk($path,$thread,$Size,$file,$type,$seconds){
            $IO = @{Read=0;Write=100;Stardard=25}
            $time = "-d{0}" -f $seconds
            $strIEX = switch ( $type )
            {
                'Standard' 
                {
                    ( "& '{0}\diskspd.exe' -b8k {4} -o4 {1} -r -Sh -w25 -L -Z1G {2} {3}" -f $path, $thread,$Capacityparam,$iofile,$time )
                }
                'Read' 
                {
                    ( "& '{0}\diskspd.exe' -b64k {4} -o1 {1} -r -Sh -w0 -L -Z1G {2} {3}" -f $path, $thread,$Capacityparam, $iofile,$time )
                }
                'Write' 
                {
                    ( "& '{0}\diskspd.exe' -b512k {4} -o32 {1} -r -Sh -w100 -L -Z1G {2} {3}" -f $path, $thread,$Capacityparam, $iofile,$time )
                }
            }

            Write-Verbose ( "Running {0} Test:`nCOMMAND: {1}" -f $type,$strIEX )

            Start-Job -OutVariable DiskTest -ScriptBlock {Invoke-Expression $args[0]} -ArgumentList $strIEX -Verbose:$false| Out-Null
            $seconds = $seconds + 16
            Write-Verbose "Waiting $seconds Seconds for Test"
            $doneDT = (Get-Date).AddSeconds( $seconds )
            while($doneDT -gt (Get-Date)) 
            {
                $secondsLeft = $doneDT.Subtract((Get-Date)).TotalSeconds
                $percent = ($seconds - $secondsLeft) / $seconds * 100
                Write-Progress -Activity "Running $type test" -Status "Waiting for Test..." -SecondsRemaining $secondsLeft -PercentComplete $percent
                [System.Threading.Thread]::Sleep(500)
            }
            Write-Progress -Activity "$type Test Completed" -Completed
            Write-Verbose "Retrieving $type test results."
            Receive-Job $DiskTest -Wait -AutoRemoveJob
        }#Function Test-Disk

        Function Format-Results($InputData,$Export,$type){
            if($Export)
            {
                $filename = ( "{0}\{1}_Drive_{2}_Test_{3}.txt" -f $path,$($disk.split(':')[0]),$type,$( (get-date).tostring( "ddmmyyyyhhmm" ) ) )
                Write-Verbose ( "Exporting results to: {0}" -f $filename)
                if(!(Test-Path $filename)){
                    New-Item -Path $filename -Force | Out-Null
                }
                Write-Host -ForegroundColor Yellow "$($type.toupper()) EXPORT: $filename"
                $InputData | Add-Content -Path $filename -Force
            }
            
                $InputData | ForEach-Object {
                    if( $_ -match "^(Total IO|Read IO|Write IO|thread.\||total:|  %)" ) {
                        Write-Host -ForegroundColor Magenta $_
                    } elseif($_ -match "[0-9].\|" -and $_ -notmatch "N/A.\|") {
                        Write-Host -ForegroundColor Yellow $_
                    } else {
                        Write-Host $_
                    }
                }
        }#Function Format-Results
    }

    Process
    {
        if($PSBoundParameters.ContainsKey('AllDrives')){
            [string[]]$disks = $ServerDisks.DeviceID | foreach{-join ($_,"\")}
        }
        if($PSBoundParameters.ContainsKey('Drive')){
            [string[]]$disks = $PSBoundParameters.Drive
        }
        Write-Verbose "Testing drives $($disks | Out-String)"
        foreach($Disk in $disks)
        {
            #Create IO Folder and File paths
            $iopath = New-Item -Path "$Disk\IOTest" -ItemType Directory -Force
            $iofile = -join ($iopath.FullName,'\IOtestfile.dat')

            #Check space on disk and 
            $logicaldisk = $ServerDisks | Where-Object {$_.deviceid -match $disk.trimend('\')}
            $FreespaceGB = [math]::Round($LogicalDisk.freespace/1024/1024/1024)
            $capacityGB = [math]::Round($LogicalDisk.size/1024/1024/1024)
            if($FreespaceGB -le 40)
            {
                if($FreespaceGB -le 20)
                {
                    if($FreespaceGB -le 10)
                    {
                        throw "Not enough free space to peform test on $Disk.`n`tFreespace: $FreespaceGB`n`tCapacity: $capacityGB"
                    } else {$Capacityparam = '-c5G'}
                } else{$Capacityparam = '-c10G'}
                
            } else { $Capacityparam = '-c20G'}



            Switch ( $PSBoundParameters.TestType )
            {
                'Write'
                {
                    $WriteTestResult = Test-Disk -path $path -thread $thread -Size $capacityGB -file $iofile -type 'Write' -seconds $Seconds
                    Format-Results -InputData $WriteTestResult -Export $OutFile -type 'Write'
                }

                'Read'
                {
                    $ReadTestResult = Test-Disk -path $path -thread $thread -Size $capacityGB -file $iofile -type 'Read' -seconds $Seconds
                    Format-Results -InputData $ReadTestResult -Export $OutFile -type 'Read'
                }

                'Standard'
                {
                    $StandardTestResult = Test-Disk -path $path -thread $thread -Size $capacityGB -file $iofile -type 'Standard' -seconds $Seconds
                    Format-Results -InputData $StandardTestResult -Export $OutFile -type 'Standard'
                }

                'All'
                {
                    $ReadTestResult = Test-Disk $path $thread $Capacityparam $iofile 'Read' $Seconds
                    Format-Results -InputData $ReadTestResult -Export $OutFile -type 'Read'
                    $WriteTestResult = Test-Disk $path $thread $Capacityparam $iofile 'Write' $Seconds
                    Format-Results -InputData $WriteTestResult -Export $OutFile -type 'Write'
                    $StandardTestResult = Test-Disk $path $thread $Capacityparam $iofile 'Standard' $Seconds
                    Format-Results -InputData $StandardTestResult -Export $OutFile -type 'Standard'
                }
            }#Switch TestType
        }#Foreach Drive
    }#Process

    End
    {
        if(Test-Path $iofile){
            Remove-Item $(Split-Path $iofile) -Force -Recurse
        }
    }
