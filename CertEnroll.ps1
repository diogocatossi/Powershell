<#
    .SYNOPSIS
        Performs the 802.1x machine cert enrollment to the targeted domain.

    .DESCRIPTION
        Port from BATCH script version adding more robust code with resiliency and active monitoring for the workstation cert enrollment.

    .INPUTS
        [N/A] No parameter required as issuing CA is per forest.

    .OUTPUTS
        n/a

    .EXAMPLE
        .\certenroll.ps1

	.ISSUES
		1) AD Replication must have been completed to the certificate server (hence 1 min retry loop for 30 min)
		2) The certificate template name is hard coded
		3) Dependency from external tool NTRights.exe that grants logon rights to 'Network Service'. Needs to be replaced by PowerShell equivalent.

	.NOTES
		- Name: CertEnroll
		- Author: Diogo Catossi 
		- Version: 1.0
#>


Import-Module ActiveDirectory

$ErrorActionPreference = "SilentlyContinue"
#Set-PSDebug -Debug $true -Trace 2

###### Global Variables ######
$sScriptName = "CertEnroll"
$sScriptVersion = "1.0"
$scriptDir = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
$iEnrollAttempts = 20
$waitTime = 1 #minutes
[ADSI]$EnrollSvcs = ""

#### Log #####
$Date = Get-Date -Format yyyyMMdd-hhmm
$sLogPath = (Get-Location).Path
$sLogFileName = "$sScriptName-$Date.log"
$sLogFile = Join-Path -path $slogpath -childpath $sLogFileName
$sHeader = ""
$iLogFileSize = 1024000 #1 MB
$sComputerName = $env:computername

###### Setting Error State Variables ######
$ErrorState = 0
$Error.Clear()

##################################################
# Begin Functions
##################################################

Function Write-Log()
{
    <#
    .SYNOPSIS
        Writes A Given Message To The Specified Log File

    .DESCRIPTION
        Writes a message to the specified log file
        Return: What was written to the log

    .PARAMETER sMessage
        Message to write to the log file

    .PARAMETER iTabs
        Number of tabs to indent text

    .PARAMETER sFileName
        Name of the log file

    .INPUTS
        [-sLogPath] <String> Path of the log file to write
        [-sLogFileName] <String> Filename of log to write
        [-sMessage] <String> Content to write to the log file
        [-iTabs] <Int32> Number of tabs to append at the beginning of the line

    .OUTPUTS
        <String> What was written to the log

    .EXAMPLE
        Write-Log -sLogPath "C:\XOM\EMGLogs" -sLogFileName "test_task2.log" -sMessage "The message is ....." -iTabs 0 

	.NOTES
    #>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $true, HelpMessage = "Log Path")]
		[Alias("LogPath")]
		[String]$sLogPath,
		[Parameter(Mandatory = $true, HelpMessage = "Log File Name")]
		[Alias("LogName")]
		[String]$sLogFileName,
		[Parameter(Mandatory = $true, HelpMessage = "Log Text")]
		[Alias("LogText", "LogMessage")]
		[String]$sMessage,
		[Parameter(Mandatory = $false, HelpMessage = "Tabs at left")]
		[Alias("Tabs")]
		[Int]$iTabs = 0
	)
	
	#Function's main 'Try'
	Try
	{
		#Loop through tabs provided to see If text should be indented within file
		$sTabs = ""
		For ($a = 1; $a -le $iTabs; $a++) { $sTabs = $sTabs + "`t" }
		
		#Populated content with tabs and message
		$sContent = $sTabs + $sMessage
		#Define $sLogFile with the full file name
		$sLogFile = Join-Path -Path $sLogPath -Childpath $sLogFileName
		
		#Write contect to the file and If debug is on, to the console for troubleshooting
		Try
		{
			$sContent | Out-File $sLogFile -Append
		}
		Catch
		{
			$sContent = "ERROR: Log File '$sLogFile' could NOT be appended."
		}
		
		#Write to host when $global:bDebug is $true
		If ($global:bDebug) { Write-host $sContent }
		
	}
	Catch { throw "Major failure. Error`: $($Error[0].Exception)" }
} #End Of Write-Log
#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-#


########################################################################################################################
# Begin Main
########################################################################################################################
try
{
	Write-Log -sLogPath $sLogPath -sLogFileName $sLogFileName -sMessage "##########################################################################" -iTabs 0
	Write-Log -sLogPath $sLogPath -sLogFileName $sLogFileName -sMessage " Begin of $sScriptName`: $(Get-Date)" -iTabs 0
	Write-Log -sLogPath $sLogPath -sLogFileName $sLogFileName -sMessage "##########################################################################" -iTabs 0
	
	$Action = "Defining Template"
	Write-Log -sLogPath $sLogPath -sLogFileName $sLogFileName -sMessage " " -iTabs 0
	Write-Log -sLogPath $sLogPath -sLogFileName $sLogFileName -sMessage "#### Action: $Action" -iTabs 0
	
	#ATENTION: CertTemplate should have no spaces"
	[string]$sCertTemplate = ""
	$domain = (Get-ADDomain).DNSRoot
	#Validates Production domain(s)/Forest(s)
	if ($domain.ToUpper().Contains("MYFOREST.COM")) 
	{
		$sCertTemplate = "MYCERTTEMPLATE"
		[ADSI]$EnrollSvcs = "LDAP://CN=Enrollment Services,CN=Public Key Services,CN=Services,CN=Configuration,DC=MYFOREST,DC=com"
	}
	#Validates LAB domain(s)/Forest(s)
	elseif ($domain.ToUpper().Contains("MYLABFOREST.COM")) 
	{
		$sCertTemplate = "MYLABCERTTEMPLATE"
		[ADSI]$EnrollSvcs = "LDAP://CN=Enrollment Services,CN=Public Key Services,CN=Services,CN=Configuration,DC=MYLABFOREST,DC=com"
	}
	else
	{
		Write-Log -sLogPath $sLogPath -sLogFileName $sLogFileName -sMessage "Error in action: $Action. Computer is not member of a valid forest. Exiting" -iTabs 2
		$ErrorState = 3
	}
	
	Write-Log -sLogPath $sLogPath -sLogFileName $sLogFileName -sMessage "Domain: $env:MachDomain" -iTabs 1
	Write-Log -sLogPath $sLogPath -sLogFileName $sLogFileName -sMessage "Cert Template: $sCertTemplate" -iTabs 1
	
	$Action = "Getting network information"
	Write-Log -sLogPath $sLogPath -sLogFileName $sLogFileName -sMessage " " -iTabs 0
	Write-Log -sLogPath $sLogPath -sLogFileName $sLogFileName -sMessage "#### Action: $Action" -iTabs 0
	Get-NetIPConfiguration -Detailed | Out-File $sLogFile -Append
	
	$Action = "'NT Authority\Network Service' logon permission"
	Write-Log -sLogPath $sLogPath -sLogFileName $sLogFileName -sMessage " " -iTabs 0
	Write-Log -sLogPath $sLogPath -sLogFileName $sLogFileName -sMessage "#### Action: $Action" -iTabs 0
	try
	{
		#Adds Network service authority rights to logon locally and perform certificate enrollment during OSD build.
		#TODO: troubleshoot group not found error using powershell method.
		
		#$return = Add-LocalGroupMember -Group "Remote Support" -Member "NT Authority\Network Service" -ErrorAction Stop 
		
		Write-Log -sLogPath $sLogPath -sLogFileName $sLogFileName -sMessage "Full command: $scriptDir\ntrights.exe +r SeNetworkLogonRight -u `"NT AUTHORITY\NETWORK SERVICE`" 2>&1" -iTabs 0
        $result = & $scriptDir\ntrights.exe +r SeNetworkLogonRight -u "NT AUTHORITY\NETWORK SERVICE" 2>&1 #OLD METHOD
		If ($LASTEXITCODE -eq 0)
		{
			Write-Log -sLogPath $sLogPath -sLogFileName $sLogFileName -sMessage "$result" -iTabs 1
		}
		Else
		{
			Write-Log -sLogPath $sLogPath -sLogFileName $sLogFileName -sMessage "Error code: $LASTEXITCODE, Message: $result" -iTabs
			throw $result
		}
		
	}
	<#catch [Microsoft.PowerShell.Commands.MemberExistsException]
	{
		Write-Log -sLogPath $sLogPath -sLogFileName $sLogFileName -sMessage "NT Authority\Network Service is already member of Remote Support local group." -iTabs 1
	}#>
	catch
	{
		$message = "Could not add NT Authority\Network Service network logon rights. Aborting. Exception: $($Error[0].ToString())"
		Write-Log -sLogPath $sLogPath -sLogFileName $sLogFileName -sMessage $message -iTabs 2
		throw $message
	}
	
	try
	{
		:EnrollLoop for ($i = 0; $i -lt $iEnrollAttempts; $i++)
		{
			$Action = "Test AD"
			Write-Log -sLogPath $sLogPath -sLogFileName $sLogFileName -sMessage " " -iTabs 0
			Write-Log -sLogPath $sLogPath -sLogFileName $sLogFileName -sMessage "#### Action: $Action connectivity" -iTabs 0
			
			if ($EnrollSvcs.Children) #Checks if ADSI instance is reachable
			{
                Write-Log -sLogPath $sLogPath -sLogFileName $sLogFileName -sMessage "Enrollment services are reachable" -iTabs 1
				
				#Parse enrollment services from AD Forest for available CAs
				$Action = "Parse EnrollSvcs"
				Write-Log -sLogPath $sLogPath -sLogFileName $sLogFileName -sMessage " " -iTabs 0
				Write-Log -sLogPath $sLogPath -sLogFileName $sLogFileName -sMessage "#### Action: $Action for published CAs that contain required template." -iTabs 0
				
				foreach ($child in $EnrollSvcs.Children)
				{
					Write-Log -sLogPath $sLogPath -sLogFileName $sLogFileName -sMessage "Validating: $($child.displayName)" -iTabs 1
					
					#Verifies if the CA has equivalent cert template published
					if ($child.certificateTemplates.Contains($sCertTemplate))
					{
						$Action = "Enrollment"
						Write-Log -sLogPath $sLogPath -sLogFileName $sLogFileName -sMessage " " -iTabs 0
						Write-Log -sLogPath $sLogPath -sLogFileName $sLogFileName -sMessage "#### Action: Start $Action" -iTabs 0
						Write-Log -sLogPath $sLogPath -sLogFileName $sLogFileName -sMessage "CA: $($child.displayName)" -iTabs 1
						Write-Log -sLogPath $sLogPath -sLogFileName $sLogFileName -sMessage "DN: $($child.distinguishedName)" -iTabs 1
						Write-Log -sLogPath $sLogPath -sLogFileName $sLogFileName -sMessage "Templates: $($child.certificateTemplates)" -iTabs 1
						
						#Verifies if the CA is available.
						if (Test-Connection $child.dNSHostName)
						{
							Try
							{
								#Performs the enrollment
								Write-Log -sLogPath $sLogPath -sLogFileName $sLogFileName -sMessage "Requesting certificate..." -iTabs 1
								$result = Get-Certificate -Template $sCertTemplate -Url "ldap:///$($child.distinguishedName)" -CertStoreLocation "Cert:\LocalMachine\My\"
								Write-Log -sLogPath $sLogPath -sLogFileName $sLogFileName -sMessage "Enrollment Status: $($result.Status)" -iTabs 1
								$ErrorState = 0
								break EnrollLoop
							}
							catch
							{
								Write-Log -sLogPath $sLogPath -sLogFileName $sLogFileName -sMessage "Critical failure enrolling to Workstation certificate: $($Error[0].toString())" -iTabs 2
								$ErrorState = 1
							}
						}
						else
						{
							Write-Log -sLogPath $sLogPath -sLogFileName $sLogFileName -sMessage "CA $($ca.Server) unavailable." -iTabs 3
							$ErrorState = 1
						}
					}
				}
			}
			else
			{
				Write-Log -sLogPath $sLogPath -sLogFileName $sLogFileName -sMessage "Could not reach current AD forest." -iTabs 3
				$ErrorState = 1
			}
			
			Write-Log -sLogPath $sLogPath -sLogFileName $sLogFileName -sMessage "Retrying in $waitTime minute(s)." -iTabs 1
			Start-Sleep (60 * $waitTime)
		}
		
	}
	catch
	{
		Write-Log -sLogPath $sLogPath -sLogFileName $sLogFileName -sMessage "Certificate enrollment ERROR in action $Action`:  $($Error[0].toString())" -iTabs 3
		#[System.Windows.MessageBox]::Show("Certificate enrollment ERROR:  $($Error[0].toString())")
		$ErrorState = 1
	}
	
	return $ErrorState
}
catch
{
	Write-Log -sLogPath $sLogPath -sLogFileName $sLogFileName -sMessage "Certificate enrollment ERROR in action $Action`:  $($Error[0].toString())" -iTabs 3
	#[System.Windows.MessageBox]::Show("Certificate enrollment ERROR:  $($Error[0].toString())")
	return 1
}
finally
{
	Write-Log -sLogPath $sLogPath -sLogFileName $sLogFileName -sMessage "##########################################################################" -iTabs 0
	Write-Log -sLogPath $sLogPath -sLogFileName $sLogFileName -sMessage " End of $sScriptName`: $(Get-Date)" -iTabs 0
	Write-Log -sLogPath $sLogPath -sLogFileName $sLogFileName -sMessage "##########################################################################" -iTabs 0
}
