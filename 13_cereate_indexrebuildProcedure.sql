USE [DBA]
GO

    CREATE OR ALTER PROCEDURE Maintenance.usp_IndexMaintenance
    AS
    BEGIN

    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @LockId INT;

    DECLARE @DbName SYSNAME;
    DECLARE @SchemaName SYSNAME;
    DECLARE @TableName SYSNAME;
    DECLARE @IxName SYSNAME;

    DECLARE @Fragm TINYINT;
    DECLARE @PageCount BIGINT;

    DECLARE @Operation VARCHAR(10);
    DECLARE @Sql NVARCHAR(MAX);

    DECLARE @RunStart DATETIME2(7);
    DECLARE @ErrorMsg NVARCHAR(MAX);
    DECLARE @WasRebuildOffline BIT;
    DECLARE @Status VARCHAR(10);

    -- Fail variables for alert
    DECLARE @ProcStart DATETIME2(7) = SYSUTCDATETIME();
    DECLARE @HadError  BIT = 0;

    DECLARE @MinTreshold TINYINT = 5;
    DECLARE @RebuildTreshold TINYINT = 30;
    DECLARE @MinPageCount INT = 1000;



    EXEC @LockId = sp_getapplock
        @Resource = 'Maintenance_IndexMaintenance',
        @LockMode = 'Exclusive',
        @LockOwner = 'Session',
        @LockTimeout = 0;

    IF @LockId < 0
    BEGIN
        PRINT 'Another maintenance session is already running.';
        RETURN;
    END;

    BEGIN TRY

        IF OBJECT_ID('tempdb..#WorkTable') IS NOT NULL
            DROP TABLE #WorkTable;

        CREATE TABLE #WorkTable
        (
            DbName SYSNAME,
            SchemaName SYSNAME,
            TableName SYSNAME,
            IndexName SYSNAME,
            Frag TINYINT,
            PageCount BIGINT
        );

        -------------------------------------------------
        -- Collect indexes
        -------------------------------------------------

        DECLARE DBS CURSOR LOCAL FAST_FORWARD FOR
        SELECT name
        FROM sys.databases
        WHERE state_desc = 'ONLINE'
          AND is_read_only = 0
          AND database_id > 4;

        OPEN DBS;

        FETCH NEXT FROM DBS INTO @DbName;

        WHILE @@FETCH_STATUS = 0
        BEGIN

            SET @Sql = N'
INSERT INTO #WorkTable
(
    DbName,
    SchemaName,
    TableName,
    IndexName,
    Frag,
    PageCount
)
SELECT
    DB_NAME(),
    s.name,
    o.name,
    i.name,
    CAST(ROUND(f.avg_fragmentation_in_percent,0) AS TINYINT),
    f.page_count
FROM sys.dm_db_index_physical_stats
(
    DB_ID(),
    NULL,
    NULL,
    NULL,
    ''LIMITED''
) f
JOIN sys.objects o
    ON o.object_id = f.object_id
JOIN sys.indexes i
    ON i.object_id = f.object_id
   AND i.index_id = f.index_id
JOIN sys.schemas s
    ON s.schema_id = o.schema_id
WHERE
    f.avg_fragmentation_in_percent > @MinTreshold
    AND f.page_count > @MinPageCount
    AND i.type_desc IN (''CLUSTERED'', ''NONCLUSTERED'')
    AND i.is_disabled = 0
    AND i.is_hypothetical = 0
    AND o.is_ms_shipped = 0;
';

            SET @Sql =
                N'USE ' + QUOTENAME(@DbName) + N';'
                + @Sql;

            EXEC sp_executesql
                @Sql,
                N'@MinTreshold TINYINT,@MinPageCount INT',
                @MinTreshold,
                @MinPageCount;

            FETCH NEXT FROM DBS INTO @DbName;
        END

        CLOSE DBS;
        DEALLOCATE DBS;

        -------------------------------------------------
        -- Execute maintenance
        -------------------------------------------------

        DECLARE IX CURSOR LOCAL FAST_FORWARD FOR
        SELECT
            DbName,
            SchemaName,
            TableName,
            IndexName,
            Frag,
            PageCount
        FROM #WorkTable;

        OPEN IX;

        FETCH NEXT FROM IX
        INTO
            @DbName,
            @SchemaName,
            @TableName,
            @IxName,
            @Fragm,
            @PageCount;

        WHILE @@FETCH_STATUS = 0
        BEGIN

            SET @RunStart = SYSUTCDATETIME();
            SET @ErrorMsg = NULL;
            SET @WasRebuildOffline = NULL;
            SET @Operation = CASE WHEN @Fragm >= @RebuildTreshold THEN 'Rebuild' ELSE 'Reorganize' END;

            BEGIN TRY

                IF @Fragm >= @RebuildTreshold
                BEGIN

                    SET @Operation = 'Rebuild';

                    BEGIN TRY

                        SET @WasRebuildOffline = 0;

                        SET @Sql =
                            N'USE ' + QUOTENAME(@DbName) + N';
                              ALTER INDEX ' + QUOTENAME(@IxName) +
                            N' ON ' + QUOTENAME(@SchemaName) +
                            N'.' + QUOTENAME(@TableName) +
                            N' REBUILD WITH (ONLINE = ON);';

                        EXEC sp_executesql @Sql;                         

                    END TRY
                    BEGIN CATCH
                        BEGIN TRY
                        SET @WasRebuildOffline = 1;

                        SET @Sql =
                            N'USE ' + QUOTENAME(@DbName) + N';
                              ALTER INDEX ' + QUOTENAME(@IxName) +
                            N' ON ' + QUOTENAME(@SchemaName) +
                            N'.' + QUOTENAME(@TableName) +
                            N' REBUILD WITH (ONLINE = OFF);';

                        EXEC sp_executesql @Sql;
                        END TRY
                        BEGIN CATCH
                            SET @ErrorMsg = ERROR_MESSAGE();
                            SET @HadError = 1;
                        END CATCH;
                    END CATCH;

                END
                ELSE
                BEGIN

                    SET @Operation = 'Reorganize';

                    SET @Sql =
                        N'USE ' + QUOTENAME(@DbName) + N';
                          ALTER INDEX ' + QUOTENAME(@IxName) +
                        N' ON ' + QUOTENAME(@SchemaName) +
                        N'.' + QUOTENAME(@TableName) +
                        N' REORGANIZE;';

                    EXEC sp_executesql @Sql;
                    -- Reorganize does not update statistics, so we need to do it manually after the operation
                SET @Sql = NULL;
                SET @Sql =
                        N'USE ' + QUOTENAME(@DbName) + N';
                        UPDATE STATISTICS '
                        + QUOTENAME(@SchemaName) + N'.'
                        + QUOTENAME(@TableName) + N' '
                        + QUOTENAME(@IxName) + N';';
                EXEC sp_executesql @Sql;
                END

            END TRY
            BEGIN CATCH

                SET @ErrorMsg = ERROR_MESSAGE();
                SET @HadError = 1;

            END CATCH;
            IF @ErrorMsg IS NOT NULL SET @HadError = 1;
            INSERT INTO Maintenance.IndexMaintenanceLog
        (DbName, SchemaName, TableName, IndexName, StartTime, EndTime,
         FragmentationPercent, PageCount, Operation, WasRebuildOffline, Status, ErrorMsg)
    VALUES
        (@DbName, @SchemaName, @TableName, @IxName, @RunStart, SYSUTCDATETIME(),
         @Fragm, @PageCount, @Operation, @WasRebuildOffline,
         CASE WHEN @ErrorMsg IS NULL THEN 'Completed' ELSE 'Error' END, @ErrorMsg);

            FETCH NEXT FROM IX
            INTO
                @DbName,
                @SchemaName,
                @TableName,
                @IxName,
                @Fragm,
                @PageCount;
        END

        CLOSE IX;
        DEALLOCATE IX;

    END TRY
    BEGIN CATCH
        SET @HadError = 1;

        INSERT INTO [Maintenance].[IndexMaintenanceLog]
        (
            DbName,
            SchemaName,
            TableName,
            IndexName,
            StartTime,
            EndTime,
            FragmentationPercent,
            PageCount,
            Operation,
            WasRebuildOffline,
            ErrorMsg,
            Status
        )
        VALUES
        (
            ISNULL(@DbName,'N/A'),
            ISNULL(@SchemaName,'N/A'),
            ISNULL(@TableName,'N/A'),
            ISNULL(@IxName,'N/A'),
            SYSUTCDATETIME(),
            SYSUTCDATETIME(),
            0,
            0,
            'Reorganize',
            NULL,
            ERROR_MESSAGE(),
            'Error'
        );

    END CATCH;

    EXEC sp_releaseapplock
        @Resource = 'Maintenance_IndexMaintenance',
        @LockOwner = 'Session';
    IF @HadError = 1
BEGIN
    DECLARE @mailQuery NVARCHAR(MAX) =
        N'SELECT DbName, SchemaName, TableName, IndexName, Operation, ErrorMsg
          FROM DBA.Maintenance.IndexMaintenanceLog
          WHERE Status = ''Error''
            AND StartTime >= ''' + CONVERT(NVARCHAR(30), @ProcStart, 126) + N'''';

    EXEC msdb.dbo.sp_send_dbmail
        @profile_name = N'HomeMonitoringAlerts',
        @recipients   = N'zancroweq@gmail.com',
        @subject      = N'Index Maintenance FAILED',
        @query        = @mailQuery;

    THROW 50010, 'Index maintenance: aspoň jeden index selhal.', 1;
    END
END

GO