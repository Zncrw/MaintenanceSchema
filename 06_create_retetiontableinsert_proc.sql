USE [DBA];
GO

CREATE OR ALTER PROCEDURE [Maintenance].[usp_InsertOrUpdateRetentionConfig]
    @DBName SYSNAME,
    @SchemaName SYSNAME,
    @TableName SYSNAME,
    @RetentionPeriodInDays INT=30,
    @BatchSize INT=10000,
    @DateColumn SYSNAME

    AS
    DECLARE @msg NVARCHAR(400);
    DECLARE @SQL nvarchar(max);
    DECLARE @Found int = 0;

IF @DBName IS NULL OR @SchemaName IS NULL OR @TableName IS NULL OR @DateColumn IS NULL
BEGIN
    SET @msg = N'DBName, SchemaName, TableName a DateColumn cannot be NULL.';
    THROW 50002, @msg, 1;
END;

SET @SQL = N'
IF NOT EXISTS
(
    SELECT 1
    FROM ' + QUOTENAME(@DBName) + N'.sys.tables t
    JOIN ' + QUOTENAME(@DBName) + N'.sys.schemas s
        ON s.schema_id = t.schema_id
    WHERE s.name = @SchemaName
      AND t.name = @TableName
)
    THROW 50003, ''Table does not exist.'', 1;
';

EXEC sp_executesql    @SQL,    N'@SchemaName sysname, @TableName sysname',    @SchemaName,    @TableName;

-- CHeck if the DateColumn exists in the specified table and is of a supported date type (date, datetime, datetime2, smalldatetime

SET @SQL = N'
IF EXISTS
(
    SELECT 1
    FROM ' + QUOTENAME(@DBName) + N'.sys.columns c
    INNER JOIN ' + QUOTENAME(@DBName) + N'.sys.tables t
        ON c.object_id = t.object_id
    INNER JOIN ' + QUOTENAME(@DBName) + N'.sys.schemas s
        ON t.schema_id = s.schema_id
    WHERE s.name = @SchemaName
      AND t.name = @TableName
      AND c.name = @DateColumn
      AND c.system_type_id IN (40,42,43,58,61)
)
    SET @Found = 1;
';

EXEC sp_executesql
    @SQL,
    N'@SchemaName sysname,
      @TableName sysname,
      @DateColumn sysname,
      @Found int OUTPUT',
    @SchemaName,
    @TableName,
    @DateColumn,
    @Found OUTPUT;

IF @Found = 0
BEGIN
    THROW 50004,'DateColumn does not exist or is not a supported date type.', 1;
END;


    -- Check If retetionperiod is not null and greater than or equal to 0, if not throw error
    IF @RetentionPeriodInDays <= 0
    BEGIN
        SET @msg = N'RetentionPeriodInDays must be greater than 0.';
        THROW 50005, @msg, 1;
    END;

    IF @BatchSize <= 0
    BEGIN
        SET @msg = N'BatchSize must be greater than 0.';
        THROW 50006, @msg, 1;
    END;   

-- Pokud existuje zaznam s danym DBName, SchemaName a TableName, tak ho aktualizujeme, jinak vložíme nový záznam
IF EXISTS (SELECT 1 FROM [Maintenance].[RetentionConfig] WHERE [DBName] = @DBName AND [SchemaName] = @SchemaName AND [TableName] = @TableName)
    BEGIN
        UPDATE [Maintenance].[RetentionConfig]
        SET [RetentionPeriodInDays] = @RetentionPeriodInDays,
            [BatchSize] = @BatchSize,
            [DateColumn] = @DateColumn
        WHERE [DBName] = @DBName AND [SchemaName] = @SchemaName AND [TableName] = @TableName;
    END
    -- Pokud neexistuje, vložíme nový záznam
    ELSE
    BEGIN
        INSERT INTO [Maintenance].[RetentionConfig] ([DBName], [SchemaName], [TableName], [RetentionPeriodInDays], [BatchSize], [DateColumn])
        VALUES (@DBName, @SchemaName, @TableName, @RetentionPeriodInDays, @BatchSize, @DateColumn);
    END