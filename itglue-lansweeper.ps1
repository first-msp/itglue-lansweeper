[cmdletbinding()]

Param (

  [switch]$force = $false,
  [string]$itgluebaseapi = "https://api.eu.itglue.com",
  [string]$itglueapikey = $(throw "-itglueapikey is required."),
  [string]$lansweeperflexid = "891034229293273"
  [string]$datasource = $(throw "-datasource is required."),
  [string]$database = "lansweeperdb",
  [string]$user = $(throw "-user is required."),
  [string]$password = $(throw "-password is required."),

)

Install-Module -Name ITGlueAPI
Import-Module ITGlueAPI
Add-ITGlueBaseURI $itgluebaseapi
Add-ITGlueAPIKey $itglueapikey
Export-ITGlueModuleSettings

$lansweeper_import_flex_type_id = $lansweeperflexid

function Invoke-SQL
{

  Param ($scanserver, $changes_from)
 # This is the connection string and query for lansweeper. You can head into lansweeper - Reports and refine this query as needed.
 # note: for testing, this only grabs the top 10 assets, change this number to pull more / everything.
 # Domain / Organization is very important here, this will map the assets to the correct organization when calling a multi org import.

    $sqlCommand = "Select tblAssets.AssetID,
  tblAssets.AssetName As name,
  tblState.StateName,
  tsysAssetTypes.AssetTypename As configuration_type,
  tblAssets.Domain As Organization,
  tsysOS.OSname As [OS name],
  tblAssetCustom.Model,
  tblAssetCustom.Manufacturer,
  tblAssets.IPAddress As [IP address],
  tsysIPLocations.IPLocation As ip_localation,
  tblAssets.Mac As [MAC address],
  tblAssets.Firstseen,
  tblAssets.Lastseen,
  tblAssets.Lasttried,
  tblAssets.Description,
  Convert(char(10),tblAssetCustom.PurchaseDate,126) As purchase_date,
  Convert(char(10),tblAssetCustom.Warrantydate,126) As warranty_date,
  tblAssets.FQDN,
  tblAssetCustom.DNSName As [DNS name],
  tblAssetCustom.Location,
  tblAssetCustom.BarCode,
  tblAssetCustom.Contact,
  tblAssetCustom.Serialnumber,
  tblAssetCustom.systemsku,
  tblAssets.Assettype,
  tblAssets.Memory,
  tblAssets.NrProcessors,
  tblAssets.Processor,
  tblOperatingsystem.caption as os_caption
From
  tblAssets Inner Join
  tblComputersystem On tblComputersystem.AssetID = tblAssets.AssetID
  tblAssetCustom On tblAssets.AssetID = tblAssetCustom.AssetID Inner Join
  tblState On tblAssetCustom.State = tblState.State Inner Join
  tsysAssetTypes On tsysAssetTypes.AssetType = tblAssets.Assettype Left Join tsysOS On tblAssets.OScode = tsysOS.OScode Left Join
  tsysIPLocations On tblAssets.IPNumeric Between tsysIPLocations.StartIP And tsysIPLocations.EndIP Left Join
  tblADComputers On tblAssets.AssetID = tblADComputers.AssetID left outer Join
  tblOperatingsystem on tblAssets.AssetID = tblOperatingsystem.AssetID
Where
  tblComputersystem.PartOfDomain = 1 And
  tblAssetCustom.State = 1 And
  tblAssets.lastchanged > '"+$changes_from+ "'  And
  tblAssets.scanserver = '" + $scanserver + "'"


    $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
    $securePassword.MakeReadOnly()
    $credentials = New-Object system.data.SqlClient.SqlCredential($user, $securePassword)
    $connectionString = "Data Source=$datasource; Initial Catalog=$database"

    $connection = new-object system.data.SqlClient.SQLConnection($connectionString)
    $connection.Credential = $credentials
    $command = new-object system.data.sqlclient.sqlcommand($sqlCommand,$connection)
    $connection.Open()

    $adapter = New-Object System.Data.sqlclient.sqlDataAdapter $command
    $dataset = New-Object System.Data.DataSet
    $adapter.Fill($dataSet) | Out-Null

    $connection.Close()
    return $dataSet.Tables
}

$mylist = @('AssetID','Name','configuration_type','Organization','OS name', 'Model', 'Manufacturer', 
'IP address', 'IP location', 'MAC address', 'Firstseen','Lastseen','Lasttried','Description','Purchase Date',
'Warranty Date','FQDN','DNS name','Location','BarCode','Contact','Serialnumber','Custom1','Assettype','Memory',
'NrProcessors','Processor')

function Row2JSON
{

    Param ($organization, $row)

    $manufacturer_id = ManufacturerToManufacturer $row.manufacturer

    $data = 
    @{
        type = 'configurations'
        attributes = 
        @{
            "configuration-type-id" = AssetTypeToConfigurationType $row.configuration_type
            name = $row.name
            "mac-address" = $row.'MAC address'
            "configuration-status-id" = StateNameToConfigurationState $row.statename
            "manufacturer-id" = $manufacturer_id
            serial_number = $row.serialnumber
            "model-id" = ModeltoModel $manufacturer_id $row.model
            purchased_at = $row.purchase_date
            warranty_expires_at = $row.warranty_date
            asset_tag = $row.systemsku
            "operating-system-id" = OSToOS($row.os_caption)

        }

    }

    return $data

}

function OSToOS
{

  Param ($os)

  if ($os -ne [DBNull]::Value )
  {
      if (($os.Trim()).length -ne 0) {

        # check if it glue os name is part of lan sweeper os string
        
        foreach ($itglue_os in $itglue_oss.data)
        {

          $exists = $os.IndexOf($itglue_os.attributes.name)

          if ($exists -gt 0) {
            Write-Host $itglue_os.attributes

            return $itglue_os.id
              
          }

        }
      }
    }
}

function ModeltoModel 
{

    Param ($manufacturer_id, $model_name) 


    if ($model_name -ne [DBNull]::Value -or $manufacturer_id -ne $null -or $manufacturer_id -ne "")
    {

      if (($model_name.Trim()).length -ne 0) {
        
        #Write-Host "Model" $model_name, length $model_name.length, trimmed $model_name.Trim(), trimmed length ($model_name.Trim()).length
   
        $models = Get-ITGlueModels -manufacturer_id $manufacturer_id

        foreach ($model in $models.data)
        {
            if ($model.attributes.name -eq $model_name) {       
                return $model.id
            } 
        }
        
        $jsonData =  @{
            type = 'models'
            attributes = @{
                name = $model_name
                "manufacturer-id" = $manufacturer_id
            }

        }

        Write-Host "Making new model for" $model_name.length  "manufacturer" $manufacturer_id  

        $model = New-ITGlueModels -data $jsonData
       
        Write-Host "Created new model" $model_name
      
        return $model.data.id
        
      }
    }

}

function AssetTypeToConfigurationType 
{

    Param ($configuration_type) 

    $type = Get-ITGlueConfigurationTypes -filter_name $configuration_type
    
    $pages = $type.meta."total-pages"

    if ($type.meta."total-pages" -eq 0) # type doesn't exist
    {
            $jsonData =  @{
                type = 'configuration_types'
                attributes = @{
                    name = $configuration_type
           
                }

           }
           $type = New-ITGlueConfigurationTypes -data $jsonData
           Write-Host "Created new Configuration type " $configuration_type
    }


    return $type.data.id
}

function StateNameToConfigurationState 
{

    Param ($status) 

    $type = Get-ITGlueConfigurationStatuses -filter_name $status
    
    $pages = $type.meta."total-pages"

    if ($type.meta."total-pages" -eq 0) # type doesn't exist
    {
            $jsonData =  @{
                type = 'configuration-statuses'
                attributes = @{
                    name = $status
           
                }

           }
           $type = New-ITGlueConfigurationStatuses -data $jsonData
           Write-Host "Created new Configuration type " $status
    }


    return $type.data.id
}

function ManufacturerToManufacturer 
{

    Param ($manufacturer_name) 

    if ($manufacturer_name -ne [DBNull]::Value)
    {
      if (($manufacturer_name.Trim()).length -ne 0) 
      {
        $manufacturer = Get-ITGlueManufacturers -filter_name $manufacturer_name
            
        
        if ($manufacturer.meta."total-count" -gt 1) {
              Write-Error "this should not happen"
              Write-Error $manufacturer.data.attributes
              exit
        }

        if ($manufacturer.meta."total-pages" -eq 0) # type doesn't exist
        {
                $jsonData =  @{
                    type = 'manufacturers'
                    attributes = @{
                        name = $manufacturer_name
               
                    }

               }
               $manufacturer = New-ITGlueManufacturers -data $jsonData
               Write-Host "Created new Manufacturer" $manufacturer_name
        }


        return $manufacturer.data.id
      }
    }
}

function AssetToItGlueConfiguration
{

    Param($organization, $row) 

    Write-Host $row

    $configuration = Get-ITGlueConfigurations -filter_name $row.name -filter_organization_id = $organization.id

    $pages = $configuration.meta."total-pages"

    $jsonData = Row2JSON($organization, $row)

    if ($configuration.meta."total-pages" -eq 0) # asset doesn't exist
    {
     

          $configurationID = New-ITGlueConfigurations -data $jsonData
          Write-Host "New Configuration created for " $row.name

          return $configurationID
    }

    
    $configurationID = Set-ITGlueConfigurations -data $jsonData -id $configuration.data[0].id

    Write-Host "Updated configuration " $row.name

        return $configurationID
}

function synceable
{

    Param ($organization)

    if ($organization.attributes."organization-status-name" -eq "Active" -and $organization.attributes."organization-type-name" -eq "Customer")
    {

        Write-Host $organization.attributes.name "is a valid organization to process"

    }

    $configs = Get-ITGlueFlexibleAssets -filter_flexible_asset_type_id $lansweeper_import_flex_type_id
 
    foreach ($config in $configs.data)
    {

        $asset =  Get-ITGlueFlexibleAssets -id $config.id

        Write-Host $asset.data.attributes.traits

    }

#    Write-Host Get-ITGlueFlexibleAssets

    return false

}

function syncAssets {

    Param($organization, $scanserver, $changes_from)

    $assets = Invoke-SQL $scanserver $changes_from


#foreach( $row in $assets.Rows)
#        {
#            foreach ( $column in $assets.Columns)
#            {
#                Write-Host $row[$column]
#            }
#        }


    foreach ( $row in $assets.Rows ) 
    {

        #Write-Host Organization: $organization.data.attributes.name
        #Write-Host Asset        : $row.name
        #Write-Host OS          : $row.os_name
        #Write-Host Location    : $row.location
        #Write-Host "-------------------------------------"
        
       

        UpsirtConfiguration $organization $row
        
    }

}

function UpsirtConfiguration
{

  Param($organization, $data)
  Write-Host "-------------------------------------------------------------------------"

  $configuration = Get-ITGlueConfigurations -filter_name $data.name -filter_organization_id $organization.id

  if ($configuration.meta."total-count" -eq 0) #configuration not found
  {

    Write-Host $data.name not found for organization, creating configuration -ForegroundColor Red

    CreateConfiguration $organization $data

    return

  }

  Write-Host $data.name found for organization, updating configuration -ForegroundColor Green

  UpdateConfiguration $organization $configuration $data


}

function CreateConfiguration
{
  Param($organization, $data)
 
  $jsonData = Row2JSON $organization $data
  
  Write-Host "Creating configuration for " $data.name "for Organization" $organization.data.id

  Try
  {
      $output = New-ITGlueConfigurations -organization_id $organization.data.id -data $jsonData

  }
  catch {
    
      Write-Error $_.Exception.Message

  }
}

function UpdateConfiguration
{

  Param($organization, $configuration, $data)
 
  $jsonData = Row2JSON $organization $data

  Write-Host "Updating configuration" $configuration.data.id "for Organization" $organization.data.id

  Try
  {
      $output = Set-ITGlueConfigurations -id $configuration.data.id -organization_id $organization.data.id -data $jsonData

  }
  catch {
    
      Write-Error $_.Exception.Message

  }


}

function updateLansweeperImportTimestamp
{

  Param($config, $new_query_timestamp)

  $jsonData =  @{
      type = 'flexible-assets'
      attributes = @{
        traits = @{
           scanserver = $config.attributes.traits.scanserver
           last_import_timestamp = $new_query_timestamp
        }
      }
  }
  Set-ITGlueFlexibleAssets -id $config.id -data $jsonData
   
} 

# start of main script
# --------------------

$configs = Get-ITGlueFlexibleAssets -filter_flexible_asset_type_id $lansweeper_import_flex_type_id

$itglue_oss = Get-ITGlueOperatingSystems

foreach ($config in $configs.data)
{

    $organization = Get-ITGlueOrganizations -filter_id $config.attributes."organization-id"

    Write-Host "Processing" $config.attributes."organization-name" "using scanner parameter" $config.attributes.traits.scanserver -ForegroundColor yellow

    $changes_from = $config.attributes.traits.last_import_timestamp

    if ($changes_from -eq $null -or $force) {

        $changes_from = "1970-01-01 00:00:00"
        
    }
    Write-Host "Checking for updated Assets since" $changes_from

    $new_query_timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    syncAssets $organization $config.attributes.traits.scanserver $changes_from

    updateLansweeperImportTimestamp $config $new_query_timestamp

}




