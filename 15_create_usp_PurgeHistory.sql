USE [DBA]
GO

CREATE OR ALTER PROCEDURE [Maintenance].[usp_PurgeHistory]
    @jobHistoryDays INT = 60,
    @backupHistoryDays INT = 60
AS
BEGIN
    
    SET NOCOUNT ON;
    DECLARE @jobCut DATETIME = DATEADD(DAY, -@jobHistoryDays, GETDATE());
    DECLARE @backupCut DATETIME = DATEADD(DAY, -@backupHistoryDays, GETDATE());
    DECLARE @ErrorMessage NVARCHAR(MAX);

    BEGIN TRY
        -- Purge Job History
        EXEC msdb.dbo.sp_purge_jobhistory @oldest_date = @jobCut;

        -- Purge Backup History
        EXEC msdb.dbo.sp_delete_backuphistory @oldest_date = @backupCut;
    END TRY
    BEGIN CATCH
        SET @ErrorMessage = ERROR_MESSAGE();
        EXEC msdb.dbo.sp_send_dbmail
            @profile_name = 'HomeMonitoringAlerts',
            @recipients = 'zancroweq@gmail.com',
            @subject = 'Purge History Failed',
            @body =  @ErrorMessage;                     

        THROW;
    END CATCH
END
