<#
    .SYNOPSIS
        Create and Azure VM using specified template.
    .DESCRIPTION
        Create and Azure VM using specified template and validating errors in case of failure, providing the specific error message.
	The desired template URI should be provided as parameter
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


#Variables
$deploymentName = "$ResourceGroupName-Deployment-$(get-date -Format yyyyMMdd-HHmm)"

try
{
	Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction Stop
	
}
catch
{
	$list = @()
	$locations = Get-AzLocation | Select-Object -Property Location
	foreach ($l in $locations) { $list += "`t$($l.location)`n`r" }
	
	Write-Host "The resource group name provided doesn't exist. A new one must be created. `nFollows the list of the $($locations.count) available Locations: `n$list"
	
	$location = Read-Host -Prompt "Provide location for the Resource creation"
	
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

