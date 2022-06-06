drop type if exists mysql_product cascade;
create type mysql_product as (
    id int,
    family text
);

create table if not exists mysql_binlog_replay_error (
    tenant text,
    table_ text,
    event text,
    rows jsonb,
    reason text,
    at timestamptz
);

create or replace procedure public.handle_mysql_event(
    tenant_ text,
    table_ text,
    event text,
    rows jsonb
)
language plpgsql
set search_path to pim
as $$ begin
    case
        when table_ = 'product' and event = 'writerows' then
            insert into product (tenant, product, parent, family)
            select tenant_, r.id, null, r.family
            from jsonb_populate_recordset(null::mysql_product, rows) r
            on conflict on constraint product_pkey do update
                set parent = excluded.parent,
                family = excluded.family;

        when table_ = 'product' and event = 'updaterows' then
            insert into product (tenant, product, parent, family)
            select tenant_, r.id, null, r.family
            from jsonb_populate_recordset(null::mysql_product, rows) r;

        else raise 'UNSUPPORTED';
    end case;
exception when others then
    insert into mysql_binlog_replay_error values (tenant_, table_, event, rows, sqlerrm, now());
end $$;

