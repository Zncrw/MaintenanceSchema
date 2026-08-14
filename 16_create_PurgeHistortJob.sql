USE msdb;
GO

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'Maintenance - PurgeHistory')
    EXEC msdb.dbo.sp_delete_job @job_name = N'Maintenance - PurgeHistory';

EXEC dbo.sp_add_job @job_name = N'Maintenance - PurgeHistory';

EXEC dbo.sp_add_jobstep
    @job_name = N'Maintenance - PurgeHistory',
    @step_name = N'Run Purge History',
    @subsystem = N'TSQL',
    @database_name = N'DBA', -- Replace with your actual database name
    @command = N'EXEC [Maintenance].[usp_PurgeHistory];';

EXEC dbo.sp_add_jobschedule
    @job_name = N'Maintenance - PurgeHistory',
    @name = N'Weekly Midnight',
    @freq_type = 8, -- Weekly
    @freq_interval = 1, -- Sunday
    @freq_recurrence_factor = 1, -- Every 1st week 
    @freq_subday_type = 1, -- Once a day
    @active_start_time = 003000; -- 30 minutes after Midnight   

EXEC dbo.sp_add_jobserver
    @job_name = N'Maintenance - PurgeHistory';
GO