\set ON_ERROR_STOP on

begin;

drop schema if exists "mysql binlog" cascade;
create schema "mysql binlog";
set local search_path to "mysql binlog";

create table event (
    tenant text not null,
    table_ text not null,
    name text not null,
    xid bigint not null,
    timestamp_ bigint not null,
    next_position bigint not null,
    index_ bigint not null,
    rows jsonb not null,
    at timestamptz not null default now(),
    handled bool not null default false,
    primary key (tenant, xid, index_)
);

create type mysql_product as (
    id bigint,
    parent bigint,
    family text,
    raw_values text
);

create function handle_mysql_event(inout event event)
language plpgsql
set search_path to "mysql binlog", pim
as $$ begin
    case
        when event.table_ = 'product' and event.name = 'writerows' then
            insert into product (tenant, product, parent, family)
            select event.tenant, id, null, family
            from jsonb_populate_recordset(null::mysql_product, event.rows) r
            on conflict on constraint product_pkey do update
                set parent = excluded.parent,
                family = excluded.family
            ;

            with to_insert as (
                select * from jsonb_populate_recordset(null::mysql_product, event.rows) r
            ),
            by_attr (id, attribute, rest) as (
              select id, j.* from to_insert, jsonb_each(raw_values::jsonb) j
            ),
            by_channel (id, attribute, channel, rest) as (
              select id, attribute,
                  case j.key when '<all_channels>' then null else j.key end,
                  j.value
              from by_attr, jsonb_each(rest) j
            ),
            by_locale (id, attribute, channel, locale, value) as (
              select id, attribute, channel,
                  case j.key when '<all_locales>' then null else j.key end,
                  j.value
              from by_channel, jsonb_each(rest) j
            )
            insert into product_value (tenant, product, attribute, locale, channel, language, value)
            select event.tenant, public.notice(id), attribute, locale, channel, 'simple', value
            from by_locale
            on conflict on constraint product_value_tenant_product_attribute_locale_channel_key
            do update
                set locale = excluded.locale,
                channel = excluded.channel,
                language = excluded.language,
                value = excluded.value
            ;

        when event.table_ = 'product' and event.name = 'updaterows' then
            with to_update as (
                select before, after
                from jsonb_array_elements(event.rows) r,
                jsonb_populate_record(null::mysql_product, r->'before') before,
                jsonb_populate_record(null::mysql_product, r->'after') after
            ),
            updated_product as (
                update product
                set product = (after).id::text, parent = (after).parent, family = (after).family
                from to_update
                where tenant = event.tenant
                and product = (before).id::text
                returning *
            ),
            by_attr (id, attribute, rest) as (
              select (before).id::text, j.* from updated_product, jsonb_each((after).raw_values::jsonb) j
            ),
            by_channel (id, attribute, channel, rest) as (
              select id, attribute,
                  case j.key when '<all_channels>' then null else j.key end,
                  j.value
              from by_attr, jsonb_each(rest) j
            ),
            by_locale (id, attribute, channel, locale, value) as (
              select id, attribute, channel,
                  case j.key when '<all_locales>' then null else j.key end,
                  j.value
              from by_channel, jsonb_each(rest) j
            )
            insert into product_value (tenant, product, attribute, locale, channel, language, value)
            select event.tenant, id, attribute, locale, channel, 'simple', public.notice(value)
            from by_locale
            on conflict on constraint product_value_tenant_product_attribute_locale_channel_key
            do update
                set locale = excluded.locale,
                channel = excluded.channel,
                language = excluded.language,
                value = excluded.value
            ;

        else raise notice 'UNSUPPORTED';
    end case;
exception when others then
    raise warning 'error %', sqlerrm;
end $$;

create function consume_queue(tenants text[] default null, batch_size int default 10) returns setof event
language sql volatile
set search_path to "mysql binlog"
as $$
with inflight as (
  select tenant, xid, index_ from event
  where case when tenants is null then true else tenant = any(tenants) end
  and not handled
  order by 1, 2, 3
  for update -- skip locked -- serializable? ok by tenant
  limit batch_size
)
-- delete from event
-- using inflight i
update event
set handled = true
from inflight i
where (event.tenant, event.xid, event.index_) = (i.tenant, i.xid, i.index_)
returning (handle_mysql_event(event)).*
$$;

commit;
