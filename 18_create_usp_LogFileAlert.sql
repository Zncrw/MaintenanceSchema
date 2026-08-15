USE [DBA];
GO

CREATE OR ALTER PROCEDURE [Maintenance].[usp_LogFileAlert]
AS
BEGIN
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID('#LogSpace') IS NOT NULL
    DROP TABLE #LogSpace;

-- Zacatek vnejsi smycky pro transakci
BEGIN TRY
    BEGIN TRANSACTION;

    -- Tresholds
    DECLARE @warningTreshold DECIMAL (5,2) = 75.0;
    DECLARE @criticalTreshold DECIMAL (5,2) = 90.0;
    
    DECLARE @ErrorMessage NVARCHAR(MAX);


    --Vytvoreni temp tabulky a vlozeni dat z DBCC SQLPERF(LOGSPACE)
    CREATE TABLE #LogSpace (DatabaseName SYSNAME, LogSizeMB FLOAT, LogSpaceUsedPct FLOAT, Status INT);
    INSERT INTO #LogSpace  EXEC ('DBCC SQLPERF(LOGSPACE)');

    -- Get Previous AlertState for each database
    IF OBJECT_ID('tempdb..#PreviousAlerts') IS NOT NULL
        DROP TABLE #PreviousAlerts;

    ;WITH LastAlert AS
    (
        SELECT
            DBName,
            AlertState,
            CreatedAt,
            ROW_NUMBER() OVER
            (
                PARTITION BY DBName
                ORDER BY CreatedAt DESC
            ) AS rn
        FROM Maintenance.LogSpaceLog
    )
    SELECT
        DBName,
        ISNULL(AlertState, 'Normal') AS PreviousAlertState
    INTO #PreviousAlerts
    FROM LastAlert
    WHERE rn = 1;

    -- Vytvoreni temp tabulky pro nove alerty
        IF OBJECT_ID('tempdb..#NewAlerts') IS NOT NULL
            DROP TABLE #NewAlerts;
        SELECT 
            s.DatabaseName AS DBName,
            CASE 
                WHEN calc.PctOfMax >= @criticalTreshold THEN 'Critical'
                WHEN calc.PctOfMax >= @warningTreshold THEN 'Warning'
                ELSE 'Normal'
            END AS AlertState
        INTO #NewAlerts
        FROM #LogSpace s
        JOIN sys.databases d on s.[DatabaseName] = d.[name]
        JOIN sys.master_files f on f.database_id = d.[database_id]
        CROSS APPLY (VALUES (
    CASE WHEN f.max_size NOT IN (-1, 268435456)
         THEN ROUND(s.LogSizeMB * 100.0 / (f.max_size * 8.0 / 1024.0), 2)
    END
        )) AS calc(PctOfMax)
    WHERE f.type_desc = 'LOG'

        INSERT INTO Maintenance.LogSpaceLog (DBName, LogUsedPercent, LogSizeMB, LogUsedMB, MaxSizeMB, PctOfMax, LogReuseWait, AlertState)
        SELECT 
            s.DatabaseName,
            ROUND(s.LogSpaceUsedPct,0) AS LogUsedPercent,
            ROUND(s.LogSizeMB,0) AS LogSizeMB,
            ROUND((s.LogSpaceUsedPct * s.LogSizeMB / 100),0) AS LogUsedMB,
            -- MaxSizeMB:
            CASE 
                WHEN f.[max_size] IN (-1, 268435456) THEN NULL 
                ELSE ROUND(f.[max_size] * 8.0 / 1024.0,0)
            END AS MaxSizeMB,
            --PctOfMax:
            calc.PctOfMax AS PctOfMax,
            -- LogReuseWait:
            d.log_reuse_wait_desc AS LogReuseWait,
            -- AlertState
            CASE 
                WHEN calc.PctOfMax >= @criticalTreshold THEN 'Critical'
                WHEN calc.PctOfMax >= @warningTreshold THEN 'Warning'
                ELSE 'Normal'
            END AS AlertState
        FROM #LogSpace s
        JOIN sys.databases d on s.[DatabaseName] = d.[name]
        JOIN sys.master_files f on f.database_id = d.[database_id]
        CROSS APPLY (VALUES (
    CASE WHEN f.max_size NOT IN (-1, 268435456)
         THEN ROUND(s.LogSizeMB * 100.0 / (f.max_size * 8.0 / 1024.0), 2)
    END
)) AS calc(PctOfMax)
        WHERE f.type_desc = 'LOG'


    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    SET @ErrorMessage = ERROR_MESSAGE();
    PRINT @ErrorMessage;
    IF @@TRANCOUNT > 0
    ROLLBACK TRANSACTION;
    THROW;
    
END CATCH;

-- Alerting logic: Compare current and previous alert states, send email if state changed and is not 'Normal'
IF OBJECT_ID('tempdb..#AlertsToSend') IS NOT NULL
    DROP TABLE #AlertsToSend;
SELECT
    n.DBName,
    ISNULL(p.PreviousAlertState, 'Normal') AS PreviousState,
    n.AlertState AS CurrentState
INTO #AlertsToSend
FROM #NewAlerts n
LEFT JOIN #PreviousAlerts p
    ON p.DBName = n.DBName
WHERE ISNULL(p.PreviousAlertState, 'Normal') <> n.AlertState;

IF EXISTS (SELECT 1 FROM #AlertsToSend)
BEGIN
    DECLARE @Rows NVARCHAR(MAX);
    SELECT @Rows = STRING_AGG(CONVERT(NVARCHAR(MAX),
        CONCAT('Database: ', DBName, ', Previous: ', PreviousState, ', Current: ', CurrentState)),
        CHAR(13) + CHAR(10))
    FROM #AlertsToSend;

DECLARE @AlertMessage NVARCHAR(MAX) =
    N'Log file alert changes detected:' + CHAR(13) + CHAR(10) + @Rows;

    EXEC msdb.dbo.sp_send_dbmail
        @profile_name = 'PFName',
        @recipients = 'dummy@mail.com',
        @subject = 'Log File Alert - State Change Detected',
        @body = @AlertMessage;
END
END