USE [DBA];
GO
CREATE OR ALTER PROCEDURE [Maintenance].[usp_RunRetention]
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @RunStart DATETIME2 = SYSUTCDATETIME();

    DECLARE @LockId INT, @ConfigId INT, @LogId INT;
    DECLARE @DBName SYSNAME, @SchemaName SYSNAME, @TableName SYSNAME, @DateColumn SYSNAME;
    DECLARE @RetentionPeriodInDays INT, @BatchSize INT;
    DECLARE @SQL NVARCHAR(MAX), @Rows BIGINT, @Total BIGINT;
    DECLARE @HadError BIT = 0;

    -- 1) APPLOCK: jen jedna instance najednou
    EXEC @LockId = sp_getapplock @Resource='Maintenance_RunRetention',
         @LockMode='Exclusive', @LockOwner='Session', @LockTimeout=0;
    IF @LockId < 0
    BEGIN
        PRINT 'Už běží jiná instance, končím.';
        RETURN;
    END

    BEGIN TRY                                              -- vnější záchranná síť
        DECLARE RetentionCursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT [ConfigId],[DBName],[SchemaName],[TableName],
                   [RetentionPeriodInDays],[DateColumn],[BatchSize]
            FROM [Maintenance].[RetentionConfig]
            WHERE [IsEnabled] = 1;

        OPEN RetentionCursor;
        FETCH NEXT FROM RetentionCursor INTO @ConfigId,@DBName,@SchemaName,@TableName,
              @RetentionPeriodInDays,@DateColumn,@BatchSize;

        WHILE @@FETCH_STATUS = 0
        BEGIN                                              -- kurzorová smyčka
            INSERT INTO [Maintenance].[RetentionLog]([ConfigId],[StartTime],[Status])
            VALUES (@ConfigId, SYSUTCDATETIME(), 'Running');
            SET @LogId = SCOPE_IDENTITY();
            SET @Total = 0;

            BEGIN TRY                                      -- per-config
                IF @BatchSize IS NULL OR @BatchSize <= 0
                    THROW 50001, 'BatchSize musí být > 0.', 1;
                IF @RetentionPeriodInDays IS NULL OR @RetentionPeriodInDays < 0
                    THROW 50002, 'RetentionPeriodInDays musí být >= 0.', 1;

                SET @SQL =
                    N'DELETE TOP (' + CAST(@BatchSize AS NVARCHAR(10)) + N') FROM '
                    + QUOTENAME(@DBName) + N'.' + QUOTENAME(@SchemaName) + N'.' + QUOTENAME(@TableName)
                    + N' WHERE ' + QUOTENAME(@DateColumn)
                    + N' < DATEADD(DAY, -' + CAST(@RetentionPeriodInDays AS NVARCHAR(10)) + N', SYSUTCDATETIME());';

                WHILE 1 = 1                                -- batch smyčka
                BEGIN
                    EXEC sp_executesql @SQL;
                    SET @Rows = @@ROWCOUNT;
                    SET @Total += @Rows;
                    IF @Rows < @BatchSize BREAK;
                    WAITFOR DELAY '00:00:00.200';
                END                                        -- konec batch smyčky

                UPDATE [Maintenance].[RetentionLog]        -- SUCCESS jednou, po smyčce
                SET [Status]='Success', [RowsDeleted]=@Total, [EndTime]=SYSUTCDATETIME()
                WHERE [LogId]=@LogId;
            END TRY
            BEGIN CATCH                                    -- per-config chyba → loguj a jeď dál
                SET @HadError = 1;
                UPDATE [Maintenance].[RetentionLog]
                SET [Status]='Error', [EndTime]=SYSUTCDATETIME(), [ErrorMessage]=ERROR_MESSAGE()
                WHERE [LogId]=@LogId;
            END CATCH

            FETCH NEXT FROM RetentionCursor INTO @ConfigId,@DBName,@SchemaName,@TableName,
                  @RetentionPeriodInDays,@DateColumn,@BatchSize;
        END                                                -- konec kurzorové smyčky

        CLOSE RetentionCursor;
        DEALLOCATE RetentionCursor;
    END TRY
    BEGIN CATCH                                            -- katastrofa mimo config (kurzor…)
        SET @HadError = 1;
    END CATCH

    EXEC sp_releaseapplock @Resource='Maintenance_RunRetention', @LockOwner='Session';  -- VŽDY

    IF @HadError = 1                                        -- ať job spadne a spustí alert
        BEGIN
            DECLARE @mailQuery NVARCHAR(MAX) =
            N'SELECT ConfigId, Status, ErrorMessage
            FROM DBA.Maintenance.RetentionLog
            WHERE Status = ''Error''
                AND StartTime >= ''' + CONVERT(NVARCHAR(30), @RunStart, 126) + N'''';
            -- 1) pošli detailní mail (které configy selhaly)
            EXEC msdb.dbo.sp_send_dbmail
                @profile_name = N'HomeMonitoringAlerts',
                @recipients   = N'email@email.com',
                @subject      = N'Retention FAILED',
                @query        = @mailQuery;
            -- 2) pak THROW, ať job zůstane v historii červený
            THROW 50000, 'Retention: aspoň jeden config selhal.', 1;
END
END
GO