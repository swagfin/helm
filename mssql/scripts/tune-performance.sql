/*
  MSSQL Performance Tuning Script (manual run)
  Usage example:
    sqlcmd -S <server>,1433 -U sa -P "<password>" -d master -i tune-performance.sql
*/

SET NOCOUNT ON;

PRINT 'Starting MSSQL tuning script...';

-- Enable advanced options
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE WITH OVERRIDE;

-- Recommended baseline values (adjust per workload and CPU count)
EXEC sp_configure 'cost threshold for parallelism', 50;
EXEC sp_configure 'max degree of parallelism', 2;
EXEC sp_configure 'optimize for ad hoc workloads', 1;
RECONFIGURE WITH OVERRIDE;

-- Output effective values after applying settings
SELECT name, value, value_in_use
FROM sys.configurations
WHERE name IN (
  'cost threshold for parallelism',
  'max degree of parallelism',
  'optimize for ad hoc workloads'
);

PRINT 'MSSQL tuning script completed.';
