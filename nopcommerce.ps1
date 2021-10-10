#Refer : https://davidcarboni.medium.com/securing-your-private-parts-in-azure-535cd743a9ff
#Refer : https://www.fearofoblivion.com/Azure-Private-Endpoints-Service-Endpoints-etc
az login

$subscription = Read-Host -Prompt 'Enter subscription name'

az account set -s $subscription
$rg = "rg-nop"
$location = "southeastasia"
Write-Host("Creating... Azure resource group")
az group create -l $location -n $rg
Write-Host("Creating... virtual network")
az network vnet create -g $rg -n vnet-nopcommerce --address-prefix 10.1.0.0/16
Write-Host("Creating... subnet network")
az network vnet subnet create --address-prefixes 10.1.1.0/24 -n private-link-subnet -g $rg --vnet-name vnet-nopcommerce
az network vnet subnet create --address-prefixes 10.1.2.0/24 -n app-svc-subnet -g $rg --vnet-name vnet-nopcommerce --delegations Microsoft.Web/serverFarms
az network vnet subnet update -n private-link-subnet --vnet-name vnet-nopcommerce --disable-private-endpoint-network-policies true -g $rg
Write-Host("Creating... private dns zone")
az network private-dns zone create --name "privatelink.blob.core.windows.net" -g $rg
az network private-dns zone create --name "privatelink.database.windows.net" -g $rg
Write-Host("Creating... private dns link")
az network private-dns link vnet create -n app-service-dns `
    --zone-name "privatelink.database.windows.net" `
    --registration-enabled false `
    --virtual-network vnet-nopcommerce `
    -g $rg
az network private-dns link vnet create -n app-service-dns `
    --zone-name "privatelink.blob.core.windows.net" `
    --registration-enabled false `
    --virtual-network vnet-nopcommerce `
    -g $rg
Write-Host("Creating... Azure blob storage")
az storage account create `
    --name stblobnop `
    --sku Standard_LRS `
    --https-only true `
    --allow-blob-public-access false `
    --encryption-services blob `
    -g $rg
$storage_id=az storage account show --name stblobnop --query "id" -o tsv -g $rg
az network private-endpoint create `
    --name private-blob-endpoint `
    --vnet-name vnet-nopcommerce `
    --subnet private-link-subnet `
    --private-connection-resource-id "$storage_id" `
    --group-id blob `
    --connection-name blob-connection `
    -g $rg
$interface_id=az network private-endpoint show --name private-blob-endpoint --query 'networkInterfaces[0].id' -o tsv -g $rg
$interface_ip=az resource show --ids "$interface_id" --query "properties.ipConfigurations[0].properties.privateIPAddress" -o tsv -g $rg
az network private-dns record-set a create `
    --name stblobnop `
    --zone-name "privatelink.blob.core.windows.net" `
    -g $rg
az network private-dns record-set a add-record `
    --record-set-name stblobnop `
    --zone-name "privatelink.blob.core.windows.net" `
    --ipv4-address $interface_ip `
    -g $rg
Write-Host("Creating... Azure SQL database server")
az sql server create -l southeastasia `
    -g $rg `
    -n sql-nopcommerce-demo `
    -u batman `
    -p forever100% `
    -e false
az sql db create -g $rg `
    -s sql-nopcommerce-demo `
    -n sqldb-nopcommerce-demo `
    --service-objective Basic `
    --backup-storage-redundancy Local

$sqlserver_id=az sql server show --name sql-nopcommerce-demo --query "id" -o tsv -g $rg

Write-Host "Creating... private endpoint for Azure SQL"
az network private-endpoint create `
    --name private-sqlserver-endpoint `
    --vnet-name vnet-nopcommerce `
    --subnet private-link-subnet `
    --private-connection-resource-id "$sqlserver_id" `
    --group-id sqlServer `
    --connection-name sqlserver-connection `
    -g $rg

az network private-dns record-set a create `
    --name sqlserver-dns `
    --zone-name "privatelink.database.windows.net" `
    -g $rg

$interface_id=az network private-endpoint show --name private-sqlserver-endpoint --query 'networkInterfaces[0].id' -o tsv -g $rg
$interface_ip=az resource show --ids "$interface_id" --query "properties.ipConfigurations[0].properties.privateIPAddress" -o tsv -g $rg

az network private-dns record-set a add-record `
    --record-set-name sqlserver-dns `
    --zone-name "privatelink.database.windows.net" `
    --ipv4-address $interface_ip `
    -g $rg
Write-Host "Creating... Azure app serivce plan"
az appservice plan create -g $rg -n asp-nopcommerce-demo --sku S1 -l $location