USE DBA;
GO
CREATE OR ALTER PROCEDURE [Maintenance].[usp_WeeklyMaintenanceReport]
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @body NVARCHAR(MAX) = N'<h2>Maintenance – týdenní report</h2>';
    DECLARE @rows NVARCHAR(MAX);
    DECLARE @tbl  NVARCHAR(200) = N'<table border="1" cellpadding="4" cellspacing="0">';

    -- SEKCE 1: retenční errory za posledních 7 dní
    SELECT @rows = STRING_AGG(CONVERT(NVARCHAR(MAX),
            CONCAT('<tr><td>', TARGET,
                   '</td><td>', Status,
                   '</td><td>', ISNULL(ErrorMessage, '-'),
                   '</td><td>', CONVERT(VARCHAR(20), StartTime, 120),
                   '</td></tr>')), '')
    FROM DBA.Maintenance.vw_retentionView
    WHERE Status = 'Error' AND StartTime >= DATEADD(DAY, -7, SYSUTCDATETIME());

    SET @body += N'<h3>1) Retenční errory (7 dní)</h3>';
    IF @rows IS NULL
        SET @body += N'<p>Žádné errory ✅</p>';
    ELSE
        SET @body += @tbl + N'<tr><th>Target</th><th>Status</th><th>Error</th><th>Start (UTC)</th></tr>'
                   + @rows + N'</table>';

    -- SEKCE 2: poslední běh každého configu
    ;WITH LastRun AS (
        SELECT *, ROW_NUMBER() OVER (PARTITION BY TARGET ORDER BY StartTime DESC) AS rn
        FROM DBA.Maintenance.vw_retentionView
    )
    SELECT @rows = STRING_AGG(CONVERT(NVARCHAR(MAX),
            CONCAT('<tr><td>', TARGET,
                   '</td><td>', Status,
                   '</td><td>', ISNULL(CAST(RowsDeleted AS VARCHAR(20)), '-'),
                   '</td><td>', CONVERT(VARCHAR(20), StartTime, 120),
                   '</td><td>', ISNULL(CONVERT(VARCHAR(20), EndTime, 120), '-'),
                   '</td></tr>')), '')
    FROM LastRun WHERE rn = 1;

    SET @body += N'<h3>2) Poslední běh každé retence</h3>';
    IF @rows IS NULL
        SET @body += N'<p>Žádné běhy zatím neproběhly.</p>';
    ELSE
        SET @body += @tbl + N'<tr><th>Target</th><th>Status</th><th>RowsDeleted</th><th>Start (UTC)</th><th>End (UTC)</th></tr>'
                   + @rows + N'</table>';

    -- SEKCE 3: transaction log za posledních 7 dní
    SELECT @rows = CONVERT(NVARCHAR(MAX),
            CONCAT('<tr><td>',  CAST(AVG(CAST(LogUsedMB AS DECIMAL(10,2))) AS DECIMAL(10,2)),
                   '</td><td>', MAX(LogUsedMB),
                   '</td><td>', SUM(CASE WHEN AlertState <> 'NORMAL' THEN 1 ELSE 0 END),
                   '</td></tr>'))
    FROM HomeMonitoring.PiHole.LogFileMonitoring
    WHERE CreatedAt >= DATEADD(DAY, -7, SYSUTCDATETIME());

    SET @body += N'<h3>3) Transaction log (7 dní)</h3>'
               + @tbl + N'<tr><th>Avg Used MB</th><th>Max Used MB</th><th>Alerty (mimo NORMAL)</th></tr>'
               + @rows + N'</table>';

    -- SEKCE 4: velikost databází
    SELECT @rows = STRING_AGG(CONVERT(NVARCHAR(MAX),
            CONCAT('<tr><td>', DBName, '</td><td>', TotalSizeMB, '</td></tr>')), '')
    FROM (
        SELECT DB_NAME(database_id) AS DBName,
               CAST(SUM(size) * 8.0 / 1024 AS DECIMAL(10,2)) AS TotalSizeMB
        FROM sys.master_files
        WHERE database_id > 4
        GROUP BY database_id
    ) AS t;

    SET @body += N'<h3>4) Velikost databází (MB)</h3>'
               + @tbl + N'<tr><th>Database</th><th>Total MB</th></tr>'
               + @rows + N'</table>';

    -- Odeslání
    EXEC msdb.dbo.sp_send_dbmail
        @profile_name = N'HomeMonitoringAlerts',
        @recipients   = N'zancroweq@gmail.com',
        @subject      = N'Maintenance – týdenní report',
        @body         = @body,
        @body_format  = 'HTML';
END
GO