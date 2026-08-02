USE [DBA]
GO

IF OBJECT_ID('Maintenance.IndexMaintenanceLog', 'U') IS NULL
BEGIN
    CREATE TABLE [Maintenance].[IndexMaintenanceLog](
    [Id] INT  IDENTITY CONSTRAINT PK_IndexMaintenanceLog PRIMARY KEY,
    [DbName] SYSNAME NOT NULL,
    [SchemaName] SYSNAME NOT NULL,
    [TableName] SYSNAME NOT NULL,
    [IndexName] SYSNAME NOT NULL,
    [StartTime] DATETIME2(7) NOT NULL CONSTRAINT DF_IndexMaintenanceLog_StartTime DEFAULT SYSUTCDATETIME(),
    [EndTime] DATETIME2(7) NULL,
    [Status] VARCHAR(10) CONSTRAINT CK_IndexMaintenanceLog_Status CHECK ([Status] IN ('Started', 'Completed', 'Error')) NOT NULL CONSTRAINT DF_IndexMaintenanceLog_Status DEFAULT 'Started',
    [FragmentationPercent] TINYINT NOT NULL, -- Procenta v celem cisle
    [PageCount] BIGINT,
    [Operation] VARCHAR(10) CONSTRAINT CK_IndexMaintenanceLog_Operation CHECK ([Operation] IN ('Rebuild', 'Reorganize')) NOT NULL,
    [WasRebuildOffline] BIT NULL, 
    [ErrorMsg] NVARCHAR(MAX) NULL,
    CONSTRAINT CK_IndexMaintenanceLog_WasRebuildOffline CHECK ((Operation = 'Reorganize' AND WasRebuildOffline IS NULL) OR (Operation = 'Rebuild' AND WasRebuildOffline IS NOT NULL))
    );
END
ELSE
BEGIN 
    PRINT ('Table Already Exists!')
END