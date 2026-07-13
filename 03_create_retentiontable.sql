USE [DBA];
GO
-- U = USerTable
IF OBJECT_ID('Maintenance.RetentionConfig', 'U') IS NULL
BEGIN
    CREATE TABLE [Maintenance].[RetentionConfig](
    [ConfigId] [int] IDENTITY CONSTRAINT PK_RetentionConfig PRIMARY KEY NOT NULL,
    [DBName] SYSNAME NOT NULL,
    [SchemaName] SYSNAME NOT NULL,
    [TableName] SYSNAME NOT NULL,
    [RetentionPeriodInDays] [int] NOT NULL,
    [DateColumn] SYSNAME NOT NULL,
    [BatchSize] [int] NOT NULL CONSTRAINT DF_RetentionConfig_BatchSize DEFAULT 10000,    
    [IsEnabled] [bit] NOT NULL CONSTRAINT DF_RetentionConfig_IsEnabled DEFAULT 1,
    CONSTRAINT UQ_RetentionConfig UNIQUE ([DBName], [SchemaName], [TableName])
);
END
ELSE
BEGIN
    PRINT ('Table Already exist');
END;