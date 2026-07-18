USE DBA;
GO

CREATE OR ALTER PROCEDURE Maintenance.usp_WeeklyMaintenanceReport
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @report NVARCHAR(MAX) ='
    -- SEKCE 1: errory za 7 dní
    SELECT * FROM DBA.Maintenance.vw_retentionView
    WHERE Status = ''Error'' AND StartTime >= DATEADD(DAY,-7,SYSUTCDATETIME());

    -- SEKCE 2: poslední běh per config
    WITH LastRun AS (
        SELECT *, ROW_NUMBER() OVER (PARTITION BY TARGET ORDER BY StartTime DESC) AS rn
        FROM DBA.Maintenance.vw_retentionView
    )
    SELECT * FROM LastRun WHERE rn = 1;

    -- SEKCE 3: log file za 7 dní
    SELECT AVG(LogUsedMB) AS AvgUsedMB, MAX(LogUsedMB) AS MaxUsedMB,
           SUM(CASE WHEN AlertState <> ''NORMAL'' THEN 1 ELSE 0 END) AS NoOfAlerts
    FROM HomeMonitoring.PiHole.LogFileMonitoring
    WHERE CreatedAt >= DATEADD(DAY,-7,SYSUTCDATETIME());

    -- SEKCE 4: Velikost mdf
        SELECT DB_NAME(database_id) AS DBName,
            CAST(SUM(size) * 8.0 / 1024 AS DECIMAL(10,2)) AS TotalSizeMB
        FROM sys.master_files
        WHERE database_id > 4          -- přeskoč systémové DB (master/model/msdb/tempdb)
        GROUP BY database_id
        ORDER BY TotalSizeMB DESC;
    ';

    EXEC msdb.dbo.sp_send_dbmail
        @profile_name = N'Alerts',   -- pozor na uvozovky, viz níže
        @recipients   = N'emailemail@email.cz',
        @subject      = N'Maintenance – týdenní report',
        @query        = @report;
END