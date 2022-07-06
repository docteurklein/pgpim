create or replace function notice(inout anyelement)
as $$ begin
raise notice $notice$
#########
%
#########
$notice$, $1;
end $$ language plpgsql strict stable;
