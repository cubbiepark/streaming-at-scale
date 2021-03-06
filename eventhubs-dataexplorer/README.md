---
topic: sample
languages:
  - azurecli
  - json
  - sql
  - scala
products:
  - azure
  - azure-container-instances
  - azure-data-explorer
  - azure-event-hubs
statusNotificationTargets:
  - algattik@microsoft.com
---

# Streaming at Scale with Azure Event Hubs and Azure Data Explorer

This sample uses Azure Data Explorer as database to store JSON data.

The provided scripts will create an end-to-end solution complete with load test client.

## Running the Scripts

Please note that the scripts have been tested on [Ubuntu 18 LTS](http://releases.ubuntu.com/18.04/), so make sure to use that environment to run the scripts. You can run it using Docker, WSL or a VM:

- [Ubuntu Docker Image](https://hub.docker.com/_/ubuntu/)
- [WSL Ubuntu 18.04 LTS](https://www.microsoft.com/en-us/p/ubuntu-1804-lts/9n9tngvndl3q?activetab=pivot:overviewtab)
- [Ubuntu 18.04 LTS Azure VM](https://azuremarketplace.microsoft.com/en-us/marketplace/apps/Canonical.UbuntuServer1804LTS)

The following tools are also needed:

- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli-apt?view=azure-cli-latest)
  - Install: `sudo apt install azure-cli`
- [jq](https://stedolan.github.io/jq/download/)
  - Install: `sudo apt install jq`

## Setup Solution

Make sure you are logged into your Azure account:

    az login

and also make sure you have the subscription you want to use selected

    az account list

if you want to select a specific subscription use the following command

    az account set --subscription <subscription_name>

once you have selected the subscription you want to use just execute the following command

    ./create-solution.sh -d <solution_name>

then `solution_name` value will be used to create a resource group that will contain all resources created by the script. It will also be used as a prefix for all resource create so, in order to help to avoid name duplicates that will break the script, you may want to generate a name using a unique prefix. **Please also use only lowercase letters and numbers only**, since the `solution_name` is also used to create a storage account, which has several constraints on characters usage:

[Storage Naming Conventions and Limits](https://docs.microsoft.com/en-us/azure/architecture/best-practices/naming-conventions#storage)

to have an overview of all the supported arguments just run

    ./create-solution.sh

**Note**
To make sure that name collisions will be unlikely, you should use a random string to give name to your solution. The following script will generated a 7 random lowercase letter name for you:

    ./_common/generate-solution-name.sh

## Created resources

The script will create the following resources:

- **Azure Container Instances** to host Spark Load Test Clients: by default one client will be created, generating a load of 1000 events/second
- **Event Hubs** Namespace, Hub and Consumer Group: to ingest data incoming from test clients
- **Azure Data Explorer**: to process data incoming from Event Hubs as a stream, and store and serve processed data. Cluster, database, table, table mapping and Event Hub connection will be created

## Streamed Data

Streamed data simulates an IoT device sending the following JSON data:

```json
{
    "eventId": "b81d241f-5187-40b0-ab2a-940faf9757c0",
    "complexData": {
        "moreData0": 57.739726013343247,
        "moreData1": 52.230732688620829,
        "moreData2": 57.497518587807189,
        "moreData3": 81.32211656749469,
        "moreData4": 54.412361539409427,
        "moreData5": 75.36416309399911,
        "moreData6": 71.53407865773488,
        "moreData7": 45.34076957651598,
        "moreData8": 51.3068118685458,
        "moreData9": 44.44672606436184,
        [...]
    },
    "value": 49.02278128887753,
    "deviceId": "contoso://device-id-154",
    "deviceSequenceNumber": 0,
    "type": "CO2",
    "createdAt": "2019-05-16T17:16:40.000003Z"
}
```
## Duplicate event handling

Azure Data Explorer does not perform event deduplication. In order to illustrate the effect of this, the event simulator is configured to randomly duplicate a small fraction of the messages (0.1% on average). Those duplicate events will be present in Azure Data Explorer.

## Solution customization

If you want to change some setting of the solution, like number of load test clients, Data Explorer tier and so on, you can do it right in the `create-solution.sh` script, by changing any of these values:

    export EVENTHUB_PARTITIONS=2
    export EVENTHUB_CAPACITY=2
    export DATAEXPLORER_SKU=D11_v2
    export DATAEXPLORER_CAPACITY=2
    export SIMULATOR_INSTANCES=1 

The above settings have been chosen to sustain a 1,000 msg/s stream. The script also contains settings for 5,000 msg/s and 10,000 msg/s.

## Monitor performance

Performance will be monitored and displayed on the console for 30 minutes. More specifically Inputs and Outputs performance of Event Hub will be monitored. If everything is working correctly, the number of reported `IncomingMessages` and `OutgoingMessages` should be roughly the same. (Give couple of minutes for ramp-up)

![Console Performance Report](../_doc/_images/console-performance-monitor.png)

## Azure Data Explorer

Data Explorer is configured to ingest data from Event Hubs, with a simple mapping from JSON fields to table columns.

## Query Data

Data is available in the created Azure Data Explorer cluster. You can query it from the portal, for example:

```sql
EventTable
| where ['type'] == 'CO2'
| summarize count() by bin(createdAt, 5m)
| render timechart
```

## Clean up

To remove all the created resource, you can just delete the related resource group

```bash
az group delete -n <resource-group-name>
```

## Next steps

Retaining long-term data in Azure Data Explorer can drive up costs. You can set up [continuous data export](https://docs.microsoft.com/en-us/azure/data-explorer/kusto/management/data-export/continuous-data-export) to save derivations from ingested data into storage. In conjunction with a [retention policy](https://docs.microsoft.com/en-us/azure/data-explorer/kusto/management/retentionpolicy), this allows data tiering, serving hot data from Data Explorer's own storage, and colder data through the external table. 

The sample statements below use CSV files in storage blob for simplicity. Use Parquet instead to improve file size and access performance, especially if planning to query data from the external table. Use Azure Data Lake Storage Gen2 instead of blob for improved performance and to avoid the need for hard-coded credentials.


```kql
.create external table SummarizedEvents (deviceId: string, type: string, count:long, from:datetime, to:datetime)  
kind=blob 
dataformat=csv
(
h@'https://<SOLUTION_NAME>storage.blob.core.windows.net/export;<STORAGE_KEY>'
)

.create function 
EventSummary()
{
    EventTable
    | summarize count=count(), from=min(createdAt), to=max(createdAt) by deviceId, type
}

// Create the target table (if it doesn't already exist)
.set-or-append SummarizedEvents <| EventSummary() | limit 0

.create-or-alter continuous-export SummarizedEventsExport
to table SummarizedEvents
with
(intervalBetweenRuns=5m)
<|  EventSummary()

```
