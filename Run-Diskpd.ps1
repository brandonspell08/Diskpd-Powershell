<#
.Synopsis
   Short description
.DESCRIPTION
   Long description
.EXAMPLE
   Example of how to use this cmdlet
.EXAMPLE
   Another example of how to use this cmdlet
.INPUTS
   Inputs to this cmdlet (if any)
.OUTPUTS
   Output from this cmdlet (if any)
.NOTES
   General notes
.COMPONENT
   The component this cmdlet belongs to
.ROLE
   The role this cmdlet belongs to
.FUNCTIONALITY
   The functionality that best describes this cmdlet
#>
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='Medium')]
    [Alias()]
    Param
    (
        # Provide the computer Target(s) to run tests on
        [Parameter(Mandatory=$true, 
                   ValueFromPipeline=$true,
                   Position=0)]
        [Alias("ComputerName")] 
        $Computer='localhost',

        # Drive that you want to test.
        [Parameter()]
        [AllowNull()]
        [ValidatePattern('^[D-Zd-z]{1}(:|:\\|$)$')]
        [string[]]
        $DriveLetter,

        # the Script utilizes a test data file. This allows you to limit the size of this file.
        [ValidateSet('5G','10G','20G','MaxAllowed')]
        [string]$TestFileSize,

        [ValidateSet('Standard','Read','Write','Full','Deep')]
        [string]$TestType,

        # Param3 help description
        [String]
        $SavePath = $PSScriptRoot
    )

    Begin
    {

        # Reset test counter
        $counter = 0

        # Set time in seconds for each run
        # 10-120s is fine
        [string]$Time = "-d1"

        # Outstanding IOs
        # Should be 2 times the number of disks in the RAID
        # Between  8 and 16 is generally fine
        $OutstandingIO = "-o16"

            Function Test-DiskSpace($DLetter,$Computer,$SpaceNeededGB){
                $filter = "DeviceID = '{0}:'" -f $DLetter
                $FreeSpaceGB = [math]::Round((Get-WmiObject win32_Logicaldisk -ComputerName $Computer -Filter $filter).freespace/[math]::Pow(2,30))
                if($SpaceNeededGB -eq '0')
                {
                     $testsize = $FreeSpaceGB - 5 #leave 5GB free space during testing
                } else {$testsize = $SpaceNeededGB}
            

                if($freespaceGB -ge $testsize){
                    $status = $true
                } else {
                    $status = $false
                }

                $tmp = "" | select Computer,Status,TestSize
                $tmp.Computer = $Computer
                $tmp.Status = $status
                $tmp.TestSize = $testsize

                return $tmp

            }#Function Test-DiskSpace

        }#Begin


   
    Process
    {
        #Parse through disk letters
        if(!$DriveLetter)
        {
            $targetdisks = ((Get-WmiObject win32_logicaldisk -Filter "DriveType = '3'" -ComputerName $Computer).deviceid | where {$_ -notmatch "^[Cc](:|$)$"}).trimend(':\\').toupper()
        } else { 
            $targetdisks = $DriveLetter | foreach{$_.TrimEnd(':\\').ToUpper()}
        }#end Disk Letter Parsing

        [int]$filesize = switch -Regex ($TestFileSize)
        {
            "\d{1,2}" {$TestFileSize.TrimEnd('G')}
            "^MaxAllowed$" {0}
            "Default" {0}
        }

        foreach($letter in $targetdisks)
        {
            #define path to temp data file and ensure it does not already exist.
            $datfile = "{0}:\diskpd_test.dat" -f $letter
            if(Test-Path $datfile){Remove-Item $datfile -Force}

            #Parse TestFileSize Parameter
            
            #Check disk space
            $diskcheck = Test-DiskSpace -DLetter $letter -Computer $Computer -SpaceNeededGB $filesize

            if($diskcheck.Status)
            {
                $capacityparam = "-c{0}G" -f $diskcheck.TestSize
            }
            else
            {
                Write-Warning ( "{0}: Drive {1}: Not enough free disk space to continue." -f $Computer,$letter )
                break
            }

            #Define Thread Param
            #Use 1 thread / core
            [string]$Thread = "-t"+(Get-WmiObject win32_processor -ComputerName $Computer).NumberofCores
            
            #Build full string




        }

        if ($pscmdlet.ShouldProcess("Target", "Operation"))
        {
        }
    }
    End
    {
    }