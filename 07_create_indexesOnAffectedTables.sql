CREATE INDEX IX_DnsQueries_seentAt ON [HomeMonitoring].[PiHole].[DnsQueries]([seen_at]);

CREATE INDEX IX_LogFileMonitoring_createdAt ON [HomeMonitoring].[Pihole].[LogFileMonitoring]([createdAt]);

CREATE INDEX IX_WifiMonDevices_LastSeen ON [HomeMonitoring].[WifiMonitoring].[Devices]([LastSeen]);
