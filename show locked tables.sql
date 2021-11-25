-- 1. once in 15 secs shows number of locks at the moment
declare 
  @cnt int = 0,
  @cnt_max int = 1000,
  @treshold int = 1, -- if more than this then log sessions
  @locks_cnt nvarchar(50) = ''

while(@cnt < @cnt_max)
begin
  set @cnt = @cnt + 1
  set @locks_cnt = (select convert(varchar(10), GETDATE(), 108) + ': locks_cnt: ' + convert(varchar(10), count(1))
                      from sys.dm_tran_locks l
                      left join sys.all_objects o on (l.resource_type not in ('PAGE', 'HOBT', 'ALLOCATION UNIT') and l.resource_associated_entity_id = o.object_id)
                      left join sys.partitions p on (l.resource_type in('PAGE','KEY','HOBT') and l.resource_associated_entity_id = p.hobt_id)
                      left join sys.all_objects o_1 on (p.objecT_id = o_1.object_id)
                      left join sys.dm_exec_sessions s on (l.request_session_id = s.session_id)
                      left join sys.dm_tran_active_transactions t on (l.request_owner_type = 'TRANSACTION' and t.transaction_id = l.request_owner_id)
                      left join sys.sysprocesses pr on (pr.spid = s.session_id)
                     where resource_type <> 'DATABASE')
  
  raiserror (@locks_cnt, 0, 1) WITH NOWAIT -- this is for output!
  waitfor delay '00:00:15'
end

-- 2. shows which tables are locked with which SQL statements

-- request_reference_count - Returns an approximate number of times the same requestor has requested this resource

/*
s.status - Status of the session. Possible values:

Running - Currently running one or more requests

Sleeping - Currently running no requests

Dormant – Session has been reset because of connection pooling and is now in prelogin state.

Preconnect - Session is in the Resource Governor classifier.

Is not nullable.
*/

select isnull(o.name, o_1.name) name,
       l.resource_type,
       l.request_status, 
	   l.request_reference_count, -- Returns an approximate number of times the same requestor has requested this resource
	   s.session_id,
	   s.login_time, -- Time when session was established. Is not nullable.
	   s.status, -- descr above
	   s.total_elapsed_time, --  Time, in milliseconds, since the session was established. Is not nullable.
	   s.last_request_start_time, -- Time at which the last request on the session began. This includes the currently executing request. Is not nullable.
	   s.last_request_end_time, -- Time of the last completion of a request on the session. Is nullable.
	   t.transaction_id,
	   t.name,
	   t.transaction_begin_time,
	   case t.transaction_type
	     when 1 then 'Read/write transaction'
		 when 2 then 'Read-only transaction'
		 when 3 then 'System transaction'
		 when 4 then 'Distributed transaction'
	   end transaction_type,
	   case t.transaction_state
		 when 0 then 'The transaction has not been completely initialized yet.'
	     when 1 then 'The transaction has been initialized but has not started.'
		 when 2 then 'The transaction is active.'
		 when 3 then 'The transaction has ended. This is used for read-only transactions.'
		 when 4 then 'The commit process has been initiated on the distributed transaction. This is for distributed transactions only. The distributed transaction is still active but further processing cannot take place.'
		 when 5 then 'The transaction is in a prepared state and waiting resolution.'
		 when 6 then 'The transaction has been committed.'
		 when 7 then 'The transaction is being rolled back.'
		 when 8 then 'The transaction has been rolled back.'
	   end transaction_state,
	   sql_text.text
  from sys.dm_tran_locks l
  left join sys.all_objects o on (l.resource_type not in ('PAGE', 'HOBT', 'ALLOCATION UNIT') and l.resource_associated_entity_id = o.object_id)
  left join sys.partitions p on (l.resource_type in('PAGE','KEY','HOBT') and l.resource_associated_entity_id = p.hobt_id)
  left join sys.all_objects o_1 on (p.objecT_id = o_1.object_id)
  left join sys.dm_exec_sessions s on (l.request_session_id = s.session_id)
  left join sys.dm_tran_active_transactions t on (l.request_owner_type = 'TRANSACTION' and t.transaction_id = l.request_owner_id)
  left join sys.sysprocesses pr on (pr.spid = s.session_id)
  cross apply sys.dm_exec_sql_text(pr.sql_handle) sql_text
 where resource_type <> 'DATABASE'
 order by s.total_elapsed_time desc;