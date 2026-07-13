USE [DBA];
GO

IF SCHEMA_ID('Maintenance') IS NULL
BEGIN
    EXEC('CREATE SCHEMA [Maintenance]');
END
ELSE
BEGIN
    PRINT('Schema Already exist');
END;
