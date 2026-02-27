# KQL Queries for Lab Monitoring

Copy-paste these queries into the Log Analytics workspace query editor to investigate common scenarios.

## AD Replication Errors

Event IDs 1084, 1308, and 2042 indicate replication problems between domain controllers.

```kql
Event
| where EventLog == "Directory Service"
| where EventID in (1084, 1308, 2042, 1925, 1926, 1988)
| project TimeGenerated, Computer, EventID, RenderedDescription
| order by TimeGenerated desc
| take 50
```

## Account Lockout Investigation

Event 4740 logs each account lockout with the calling computer name.

```kql
Event
| where EventLog == "Security" and EventID == 4740
| extend LockedAccount = extract("Account Name:\\s+(\\S+)", 1, RenderedDescription)
| extend CallerComputer = extract("Caller Computer Name:\\s+(\\S+)", 1, RenderedDescription)
| project TimeGenerated, Computer, LockedAccount, CallerComputer
| order by TimeGenerated desc
```

## Failed Logon Attempts

Event 4625 captures failed interactive and network logons.

```kql
Event
| where EventLog == "Security" and EventID == 4625
| extend TargetAccount = extract("Account Name:\\s+(\\S+)", 1, RenderedDescription)
| extend SourceIP = extract("Source Network Address:\\s+(\\S+)", 1, RenderedDescription)
| extend FailureReason = extract("Failure Reason:\\s+(.+)", 1, RenderedDescription)
| project TimeGenerated, Computer, TargetAccount, SourceIP, FailureReason
| order by TimeGenerated desc
| take 100
```

## DC Heartbeat Monitoring

Shows the last heartbeat from each computer reporting to the workspace.

```kql
Heartbeat
| summarize LastHeartbeat = max(TimeGenerated) by Computer
| extend MinutesAgo = datetime_diff('minute', now(), LastHeartbeat)
| order by MinutesAgo desc
```

## GPO Application Failures

Event 1085 in GroupPolicy operational log indicates GPO processing failures.

```kql
Event
| where EventLog == "System"
| where Source == "GroupPolicy" or Source == "Microsoft-Windows-GroupPolicy"
| where Level <= 3
| project TimeGenerated, Computer, EventID, RenderedDescription
| order by TimeGenerated desc
| take 50
```

## CPU Trend (Last 24 Hours)

```kql
Perf
| where ObjectName == "Processor Information"
| where CounterName == "% Processor Time"
| where InstanceName == "_Total"
| summarize AvgCPU = avg(CounterValue), MaxCPU = max(CounterValue) by Computer, bin(TimeGenerated, 15m)
| order by TimeGenerated desc
```

## Memory Trend (Last 24 Hours)

```kql
Perf
| where ObjectName == "Memory"
| where CounterName == "% Committed Bytes In Use"
| summarize AvgMemory = avg(CounterValue), MaxMemory = max(CounterValue) by Computer, bin(TimeGenerated, 15m)
| order by TimeGenerated desc
```

## Disk Space Trend

```kql
Perf
| where ObjectName == "LogicalDisk"
| where CounterName == "% Free Space"
| where InstanceName == "_Total"
| summarize MinFree = min(CounterValue), AvgFree = avg(CounterValue) by Computer, bin(TimeGenerated, 1h)
| order by TimeGenerated desc
```

## Security Event Summary

Top event IDs from the Security log to identify audit activity hotspots.

```kql
Event
| where EventLog == "Security"
| summarize Count = count() by EventID
| order by Count desc
| take 20
```

## Windows Service Crashes

Event 7034 logs each unexpected service termination.

```kql
Event
| where EventLog == "System" and EventID == 7034
| project TimeGenerated, Computer, RenderedDescription
| order by TimeGenerated desc
| take 25
```
