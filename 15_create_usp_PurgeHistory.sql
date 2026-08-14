USE [DBA]
GO

CREATE OR ALTER PROCEDURE [Maintenance].[usp_PurgeHistory]
    @jobHistoryDays INT = 30,
    @backupHistoryDays INT = 30
AS
BEGIN
    
    SET NOCOUNT ON;
    DECLARE @jobCut DATETIME = DATEADD(DAY, -@jobHistoryDays, GETDATE());
    DECLARE @backupCut DATETIME = DATEADD(DAY, -@backupHistoryDays, GETDATE());

    -- Purge Job History
    EXEC msdb.dbo.sp_purge_jobhistory @oldest_date = @jobCut;

    -- Purge Backup History
    EXEC msdb.dbo.sp_delete_backuphistory @oldest_date = @backupCut;
END