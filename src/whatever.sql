create or replace function whatever(
    toid oid,
    custom jsonb default '{}'::jsonb
) returns jsonb
language sql strict stable
set search_path to public, pg_catalog
as $$
with field(name, type) as (
    select a.attname, coalesce(bt.typname, t.typname)
    from pg_attribute a
    join pg_type t
        on a.atttypid = t.oid
    left join pg_type bt
        on t.typbasetype = bt.oid
    where a.attrelid = toid
    and a.attnum > 0
)
select jsonb_object_agg(name, case type
    when 'int4' then to_jsonb(random() * 10)
    when 'text' then to_jsonb(pim.lorem())
    else to_jsonb(type)
end) || custom
from field
;
$$;
