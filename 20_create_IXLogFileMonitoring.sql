USE [DBA];
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes 
              WHERE name = 'IX_LogSpaceLog_CreatedAt' 
                AND object_id = OBJECT_ID('Maintenance.LogSpaceLog'))
    CREATE INDEX IX_LogSpaceLog_CreatedAt ON Maintenance.LogSpaceLog (CreatedAt);