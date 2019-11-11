#!/bin/bash

set -euo pipefail

az extension add --name log-analytics

analytics_ws_id=$(az resource show -g $RESOURCE_GROUP -n $LOG_ANALYTICS_WORKSPACE --resource-type Microsoft.OperationalInsights/workspaces --query properties.customerId -o tsv)

REPORT_THROUGHPUT_MINUTES=${REPORT_THROUGHPUT_MINUTES:-30}

fmt="%28s%20.f%20.f%20.f\n"

echo "Reporting aggregate metrics per minute, for $REPORT_THROUGHPUT_MINUTES minutes."
printf "${fmt//.f/s}" "" IncomingMessages IncomingBytes OutgoingBytes
printf "${fmt//.f/s}" "" ---------------- ------------- -------------
for i in $(seq 1 $REPORT_THROUGHPUT_MINUTES) ; do
  stats=$(
  az monitor log-analytics query -w "$analytics_ws_id" --analytics-query "
  InsightsMetrics 
  | where Namespace == 'prometheus'
  | extend tags = parse_json(Tags)
  | filter tags.topic == '$KAFKA_TOPIC'
  | partition by Name (
   sort by TimeGenerated 
  | project 
    Name,
    latest_timestamp = TimeGenerated,
    previous_timestamp = next(TimeGenerated),
    latest_value = Val,
    previous_value = next(Val),
    increment_per_second = (Val - next(Val)) / datetime_diff('Millisecond', TimeGenerated, next(TimeGenerated)) * 60000
  | limit 1
  )
  | sort by Name
  ")
  ts=$(jq -r '.[] | select(.Name == "kafka_server_brokertopicmetrics_messagesin_total").latest_timestamp' <<< "$stats")
  messagesIn=$(jq -r '.[] | select(.Name == "kafka_server_brokertopicmetrics_messagesin_total").increment_per_second | tonumber | floor' <<< "$stats")
  bytesIn=$(jq -r '.[] | select(.Name == "kafka_server_brokertopicmetrics_bytesin_total").increment_per_second | tonumber | floor' <<< "$stats")
  bytesOut=$(jq -r '.[] | select(.Name == "kafka_server_brokertopicmetrics_bytesout_total").increment_per_second | tonumber | floor' <<< "$stats")

  printf "$fmt" "$ts" "$messagesIn" "$bytesIn" "$bytesOut"

  # sleep until next full minute. "10#" is to force base 10 if string is e.g. "09"
  sleep "$((60 - 10#$(date +%S) ))"
done
