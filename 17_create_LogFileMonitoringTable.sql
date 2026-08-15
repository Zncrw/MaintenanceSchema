USE [DBA];
GO

IF OBJECT_ID('DBA.Maintenance.LogSpaceLog') IS NULL
BEGIN
    CREATE TABLE DBA.Maintenance.LogSpaceLog
    (
        ID INT IDENTITY PRIMARY KEY,
        DBName SYSNAME NOT NULL,
        LogUsedPercent DECIMAL(5,2) NOT NULL,
        LogSizeMB BIGINT NOT NULL,
        LogUsedMB BIGINT NOT NULL,
        MaxSizeMB BIGINT NULL,
        PctOfMax DECIMAL(5,2) NULL,
        LogReuseWait NVARCHAR(60) NULL,
        AlertState VARCHAR(20) NOT NULL,
        CreatedAt DATETIME2 NOT NULL DEFAULT GETUTCDATE()
    );

-- Kvuli rychlejsimu vyhledavani a zobrazeni poslednich zaznamu v tabulce LogSpaceLog vytvorime index na sloupcich DBName a CreatedAt
    CREATE INDEX IX_LogMon_DB_Created ON DBA.Maintenance.LogSpaceLog (DBName, CreatedAt DESC);
    PRINT 'Table created.';
END
ELSE
    PRINT 'Table already exists, skipping.';
GO