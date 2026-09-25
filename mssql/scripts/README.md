Run the tuning script manually against the SQL instance:

```bash
sqlcmd -S <server>,1433 -U sa -P "<password>" -d master -i tune-performance.sql
```

If `sqlcmd` is not in PATH, use:

```bash
/opt/mssql-tools18/bin/sqlcmd -S <server>,1433 -U sa -P "<password>" -d master -i tune-performance.sql
```
