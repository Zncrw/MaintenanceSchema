USE [DBA];
GO

IF OBJECT_ID('Maintenance.RetentionLog', 'U') IS NULL
BEGIN
    CREATE TABLE [Maintenance].[RetentionLog](
    [LogId] [int] IDENTITY CONSTRAINT PK_RetentionLog PRIMARY KEY NOT NULL,
    [ConfigId] [int] NULL CONSTRAINT FK_RetentionLog_RetentionConfig REFERENCES [Maintenance].[RetentionConfig]([ConfigId]),
    [StartTime] [datetime2](7) NOT NULL CONSTRAINT DF_RetentionLog_StartTime DEFAULT SYSUTCDATETIME(),
    [EndTime] [datetime2](7) NULL,
    [Status] [varchar](20) NOT NULL CONSTRAINT CK_RetentionLog_Status CHECK ([Status] IN ('Running', 'Success', 'Error')),
    [RowsDeleted] [Bigint] NULL,
    [ErrorMessage] [nvarchar](max) NULL 
);
-- Index for StartTime to speed up queries filtering by start time as the procedure will delete also RetentionLog entries older than 30 days
CREATE INDEX IX_RetentionLog_StartTime ON [Maintenance].[RetentionLog]([StartTime]);
END

ELSE
BEGIN
    PRINT ('Table Already exist');
END;