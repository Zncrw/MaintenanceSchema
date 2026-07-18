USE DBA;
GO

CREATE OR ALTER VIEW [Maintenance].[vw_RetentionView]
AS
    SELECT 
        rc.[DBName] + '.' + rc.[SchemaName] + '.' + rc.[TableName] AS TARGET,
        rl.[Status],
        ISNULL(rl.[ErrorMessage], '-') AS ErrorMessage,
        rl.[RowsDeleted],
        rl.[StartTime], 
        rl.[EndTime] 

    FROM [Maintenance].[RetentionLog] AS rl
    JOIN [Maintenance].[RetentionConfig] AS rc ON rc.ConfigId = rl.ConfigId