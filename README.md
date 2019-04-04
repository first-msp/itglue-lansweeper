# itglue-lansweeper
Create/Update IT-Glue configuration items using lan sweeper CMDB

## It Glue Setup

Create a new flexible asset type in It glue:

Name: Lansweeper Import
Fields:
  - scanserver (Text)
  - last_import_timestamp (Date)

Now create an asset based on this type for the organisation you want to import assets to.

`scanserver` is the name of the lansweeper probe gathering the data.

We assume each of yoru customers has a unique probe name.

## Import assets

Open a powershell window:

```
itglue-lansweeper.ps1 -itglueapikey jkkjlkjl45O24453 -lansweeperflexid 891034229293273 -datasource myserver.local -database lansweeperdb -user myuser -password mypassword

```
Parameters:

| Parameter        | Mandatory | Default Value             | Description                                                                         |
|------------------|-----------|---------------------------|-------------------------------------------------------------------------------------|
| force            | No        | FALSE                     | Ignores the `last_import_timestamp` field and processes all assets in lansweeper DB |
| itgluebaseapi    | No        | https://api.eu.itglue.com | IT Glue API base URL                                                                |
| itglueapikey     | Yes       |                           | IT Glue API key                                                                     |
| lansweeperflexid | Yes       |                           | flexible asset type id for "lansweeper import" flexible assettype                   |
| datasource       | Yes       |                           | MS SQL server host                                                                  |
| database         | No        | lansweeperdb              | lansweeper database name                                                            |
| user             | Yes       |                           | lansweeper database user                                                            |
| password         | Yes       |                           | lansweeper database password                                                        |
 
