############################################################################################
###
### Script Title: AzurePowershell-CreateSimpleVM.ps1
### Script Function:  Create and Azure VM using specified template and validating errors in case of failure, providing the specific error message.
###
### Revision history:
###          Version 1.0 - 2020/06/09
###          Diogo C Catossi
###                 - Initial Version
############################################################################################a

param
(
	[parameter(Mandatory = $true)]
	[String]$resGroupName
)

Import-Module Az


#Variables
$deploymentName = "$resGroupName-Deployment-$(get-date -Format yyyyMMdd-HHmm)"

$templateUri = 'https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/101-vm-simple-windows/azuredeploy.json'

$result = New-AzResourceGroupDeployment -name $deploymentName -ResourceGroupName $resGroupName -TemplateUri $templateUri

if ($result.ProvisioningState -eq 'Succeeded')
{
	Write-Host "Deployment successful."
}
else
{
	$operations = Get-AzResourceGroupDeploymentOperation -ResourceGroupName $resGroupName -DeploymentName $deploymentName
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

