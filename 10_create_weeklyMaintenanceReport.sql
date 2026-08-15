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
        ;WITH Latest AS
    (
        SELECT
            DBName,
            LogSizeMB,
            LogUsedMB,
            LogUsedPercent,
            MaxSizeMB,
            PctOfMax,
            LogReuseWait,
            AlertState,
            ROW_NUMBER() OVER
            (
                PARTITION BY DBName
                ORDER BY CreatedAt DESC
            ) AS rn
        FROM DBA.Maintenance.LogSpaceLog
    ),
    Peak AS
    (
        SELECT
            DBName,
            MAX(PctOfMax)        AS MaxPctOfMax7d,
            MAX(LogUsedPercent)  AS MaxUsedPct7d,
            SUM(CASE WHEN AlertState <> 'Normal' THEN 1 ELSE 0 END) AS AlertCount7d
        FROM DBA.Maintenance.LogSpaceLog
        WHERE CreatedAt >= DATEADD(DAY,-7,SYSUTCDATETIME())
        GROUP BY DBName
    )
    SELECT
        @rows = STRING_AGG(
            CONVERT(NVARCHAR(MAX),
                CONCAT(
                    '<tr>',
                    '<td>', l.DBName, '</td>',
                    '<td>', l.LogUsedMB, '</td>',
                    '<td>', l.LogUsedPercent, '%</td>',
                    '<td>', ISNULL(CONVERT(VARCHAR(20),p.MaxPctOfMax7d),'N/A'), '%</td>',
                    '<td>', p.AlertCount7d, '</td>',
                    '<td>', l.AlertState, '</td>',
                    '</tr>'
                )
            ),
            ''
        )
    FROM Latest l
    JOIN Peak p
        ON p.DBName = l.DBName
    WHERE l.rn = 1;
    SET @body += N'<h3>3) Transaction Log (7 dní)</h3>'
            + @tbl
            + N'<tr>
                        <th>Database</th>
                        <th>Used MB</th>
                        <th>Used %</th>
                        <th>Peak % Of Max (7d)</th>
                        <th>Alerts (7d)</th>
                        <th>Current State</th>
                </tr>'
            + @rows
            + N'</table>';

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

-- SEKCE 5: index maintenance za 7 dní
    SELECT @rows = STRING_AGG(CONVERT(NVARCHAR(MAX),
            CONCAT('<tr><td>', CONCAT(DbName,'.',SchemaName,'.',TableName),
                   '</td><td>', IndexName,
                   '</td><td>', Operation,
                   '</td><td>', FragmentationPercent,
                   '</td><td>', Status,
                   '</td></tr>')), '')
    FROM DBA.Maintenance.IndexMaintenanceLog
    WHERE StartTime >= DATEADD(DAY, -7, SYSUTCDATETIME());

    SET @body += N'<h3>5) Index maintenance (7 dní)</h3>';
    IF @rows IS NULL
        SET @body += N'<p>Nic se nedělalo (indexy zdravé) ✅</p>';
    ELSE
        SET @body += @tbl + N'<tr><th>Target</th><th>Index</th><th>Operace</th><th>Frag %</th><th>Status</th></tr>'
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