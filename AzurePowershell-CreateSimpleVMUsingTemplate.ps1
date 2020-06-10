<#
    .SYNOPSIS
        Create and Azure VM using specified template.
    .DESCRIPTION
        Create and Azure VM using specified template and validating errors in case of failure, providing the specific error message of which deployment step failed. The desired template URI should be provided as parameter
    .INPUTS
        ResourceGroupName - Name of the resource group that will be used for the VM deployment. If none exist a new one will be created.
		TemplateURI - URI for the template desired. e.g.: 'https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/101-vm-simple-windows/azuredeploy.json' (used for this template initially)
    .OUTPUTS
        n/a
    .EXAMPLE
        .\AzurePowershell-CreateSimpleVMUsingTemplate.ps1 -ResourceGroupName RG01 -TemplateURI https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/101-vm-simple-windows/azuredeploy.json
	.ISSUES
		None
	.NOTES
		Version: 1.0 
		Date: 2020/06/09
		Author: Diogo Catossi 
		Comments: none
#>

param
(
	[parameter(Mandatory = $true)]
	[String]$ResourceGroupName,
	[parameter(Mandatory = $true)]
	[String]$TemplateURI
)

Import-Module Az

function isURI($address) {
	($address -as [System.URI]).AbsoluteURI -ne $null
}

function isURIWeb($address) {
	$uri = $address -as [System.URI]
	$uri.AbsoluteURI -ne $null -and $uri.Scheme -match '[http|https]'
}


###### Variables #######
$deploymentName = "$ResourceGroupName-Deployment-$(get-date -Format yyyyMMdd-HHmm)"
$tab0 = "`t" * 0
$tab1 = "`t" * 1
$tab2 = "`t" * 2
$tab3 = "`t" * 3

###### Validation ######
if (-Not (isURI($TemplateURI))) {
    write-host "$tab2 Please provide a valid URI for the template."
    return
}


# Validates there's a valid Azure connection for the current profile
if (-not (Get-AzContext)){
    Write-Host "$tab2 There's no active Azure Subscription context. Starting authentication process..."
    Connect-AzAccount
    if (Get-AzContext) {
        write-host "$tab1 Azure connection successful. Proceeding."
    }
}



## Verifies if provided RG exists
try
{
	Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction Stop
	
}
catch
{
	## If it doesn't exists will attempt to create it
	$list = @()
	
	#Retrieves all curretly available locations
	$locations = Get-AzLocation | Select-Object -Property Location
	foreach ($l in $locations) { $list += "`t$($l.location)`n`r" }
	
	Write-Host "The resource group name provided doesn't exist. A new one must be created. `nFollows the list of the $($locations.count) available Locations: `n$list"
	
	$location = Read-Host -Prompt "Provide location for the resource creation"
	
	#Attempts to create the RG
	$rg = New-AzResourceGroup -Name $ResourceGroupName -Location $location
	if (Get-AzResourceGroup -Name $ResourceGroupName)
	{
		write-host "Resource group created successfully."
	}
	else
	{
		write-host "Failed to create RG Error: $($Err[0].Exception).
                    Aborting!"
		return
	}
}

#Executes the remote command based on the parameters provided
$result = New-AzResourceGroupDeployment -name $deploymentName -ResourceGroupName $ResourceGroupName -TemplateUri $TemplateURI

if ($result.ProvisioningState -eq 'Succeeded')
{
	Write-Host "Deployment successful."
}
else
{
	$operations = Get-AzResourceGroupDeploymentOperation -ResourceGroupName $ResourceGroupName -DeploymentName $deploymentName
	foreach ($op in $operations)
	{
		if ($op.properties.provisioningState -eq 'Failed')
		{
			write-host "Operation $($op.properties.provisioningOperation) ID $($op.OperationId) for resource $($op.properties.targetResource.resourceName) failed: `r
            Status Code: $($op.properties.statusCode) `r 
            Error message:  $(if ($op.properties.statusMessage.error) { $op.properties.statusMessage.error.message }
				else { $op.properties.statusMessage }) `n`r"
		}
	}
}


