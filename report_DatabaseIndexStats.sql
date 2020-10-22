-- Thanks to
--     https://dataedo.com/kb/query/sql-server/list-all-indexes-in-the-database for the excellent index listing query
--     https://stackoverflow.com/a/7892349/1964861 for size info
--     https://dba.stackexchange.com/a/4287 for example recommendations

create procedure report_DatabaseIndexStats as begin
select i.[name] as index_name,
    substring(column_names, 1, len(column_names)-1) as [columns],
    case when i.[type] = 1 then 'Clustered index'
        when i.[type] = 2 then 'Nonclustered unique index'
        when i.[type] = 3 then 'XML index'
        when i.[type] = 4 then 'Spatial index'
        when i.[type] = 5 then 'Clustered columnstore index'
        when i.[type] = 6 then 'Nonclustered columnstore index'
        when i.[type] = 7 then 'Nonclustered hash index'
        end as index_type,
    case when i.is_unique = 1 then 'Unique'
        else 'Not unique' end as [unique],
    schema_name(t.schema_id) + '.' + t.[name] as table_view, 
    case when t.[type] = 'U' then 'Table'
        when t.[type] = 'V' then 'View'
        end as [object_type],
	indexstats.avg_fragmentation_in_percent,
  -- Set up recommended activities below
	case when indexstats.avg_fragmentation_in_percent < 10 then 'do nothing'
		when indexstats.avg_fragmentation_in_percent between 10 and 30 then 'reorganize, update statistics'
		when indexstats.avg_fragmentation_in_percent >= 30 then 'rebuild'
	end as recommendation,
	alloc.TotalMB,alloc.UsedMB,alloc.UnusedMB,
	indexstats.page_count
from sys.objects t
    inner join sys.indexes i
        on t.object_id = i.object_id
    cross apply (select col.[name] + ', '
                    from sys.index_columns ic
                        inner join sys.columns col
                            on ic.object_id = col.object_id
                            and ic.column_id = col.column_id
                    where ic.object_id = t.object_id
                        and ic.index_id = i.index_id
                            order by key_ordinal
                            for xml path ('') ) D (column_names)
	cross apply (select 
				 CAST(ROUND(((SUM(a.total_pages) * 8) / 1024.00), 2) AS NUMERIC(36, 2)) AS TotalSpaceMB,
				 CAST(ROUND(((SUM(a.used_pages) * 8) / 1024.00), 2) AS NUMERIC(36, 2)) AS UsedSpaceMB, 
				 CAST(ROUND(((SUM(a.total_pages) - SUM(a.used_pages)) * 8) / 1024.00, 2) AS NUMERIC(36, 2)) AS UnusedSpaceMB
		from sys.partitions p
		join sys.allocation_units a ON p.partition_id = a.container_id
		where i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
	) alloc (TotalMB,UsedMB,UnusedMB)
	join sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, NULL) indexstats on indexstats.index_id = i.index_id and i.[object_id] = indexstats.[object_id]
where t.is_ms_shipped <> 1
and i.index_id > 0
order by i.[name]
end
