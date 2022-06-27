\set ON_ERROR_STOP on

begin;

-- drop schema if exists "mysql binlog" cascade;
-- create schema "mysql binlog";
set local search_path to "mysql binlog";

-- drop table if exists event cascade;
-- create table event (
--     tenant text not null,
--     table_ text not null,
--     name text not null,
--     xid bigint not null,
--     timestamp_ bigint not null,
--     next_position bigint not null,
--     index_ bigint not null,
--     rows jsonb not null,
--     at timestamptz not null default now(),
--     handled bool not null default false,
--     primary key (tenant, xid, index_)
-- );
-- 
-- create type mysql_product as (
--     id bigint,
--     parent bigint,
--     family text,
--     raw_values text
-- );

create or replace function handle_mysql_event(inout event event)
language plpgsql
set search_path to "mysql binlog", pim
as $$ begin
    perform set_config('lock_timeout', '2s', true); 
    raise notice '% % %', event.xid, event.table_, event.index_;
    case
        when event.table_ = 'pim_catalog_product' and event.name = 'writerows' then
            with to_insert as (
                select * from jsonb_populate_recordset(null::mysql_product, event.rows->'after') r
            ),
            inserted_product as (
                insert into product (tenant, product, parent, family)
                select event.tenant, id::text, null, family
                from to_insert
                on conflict (tenant, product) -- should never happen, let's make it resilient anyway
                do update
                    set parent = excluded.parent,
                    family = excluded.family
                returning *
            ),
            by_attr (id, attribute, rest) as (
                select id, j.* from to_insert, jsonb_each(raw_values::jsonb) j
            ),
            by_channel (id, attribute, channel, rest) as (
                select id, attribute, case j.key when '<all_channels>' then null else j.key end, j.value
                from by_attr, jsonb_each(rest) j
            ),
            raw_value (id, attribute, channel, locale, value) as (
                select id, attribute, channel, case j.key when '<all_locales>' then null else j.key end, j.value
                from by_channel, jsonb_each(rest) j
            )
            insert into product_value (tenant, product, attribute, channel, locale, language, value)
            select event.tenant, id::text, attribute, channel, locale, 'simple'::regconfig, value
            from raw_value
            -- merge into product_value value -- existing row should never exist, let's just use insert above, use merge for resilience
            -- using raw_value new
            --     on (value.tenant, value.product, value.attribute) = (event.tenant, new.id::text, new.attribute)
            -- when matched then
            --     update set locale = new.locale,
            --     channel = new.channel,
            --     value = new.value
            -- when not matched then
            --     insert values(event.tenant, new.id::text, new.attribute, new.channel, new.locale, 'simple'::regconfig, new.value)
            ;

        when event.table_ = 'pim_catalog_product' and event.name = 'updaterows' then
            with to_update as (
                select distinct after
                from jsonb_array_elements(event.rows) r,
                jsonb_populate_record(null::mysql_product, r->'after') after
            ),
            by_attr (id, attribute) as (
                select (after).id::text, j.key from to_update
                left join jsonb_each((after).raw_values::jsonb) j on true
            )
            delete from product_value extra -- cleanup all values that don't appear in new raw_values (or if raw_values is empty)
            using by_attr new
            where (extra.tenant, extra.product) = (event.tenant, new.id::text)
            and (extra.attribute != new.attribute or new.attribute is null)
            ;

            with to_update as (
                select distinct before, after
                from jsonb_array_elements(event.rows) r,
                jsonb_populate_record(null::mysql_product, r->'before') before,
                jsonb_populate_record(null::mysql_product, r->'after') after
            ),
            updated_product as (
                update product
                set product = (after).id::text, parent = (after).parent, family = (after).family
                from to_update
                where (tenant, product) = (event.tenant, (before).id::text)
                returning *
            ),
            by_attr (id, attribute, rest) as (
                select (before).id::text, j.* from to_update, jsonb_each((after).raw_values::jsonb) j
            ),
            by_channel (id, attribute, channel, rest) as (
                select id, attribute, case j.key when '<all_channels>' then null else j.key end, j.value
                from by_attr, jsonb_each(rest) j
            ),
            raw_value (id, attribute, channel, locale, value) as (
                select distinct id, attribute, channel, case j.key when '<all_locales>' then null else j.key end, j.value
                from by_channel, jsonb_each(rest) j
            )
            merge into product_value value -- had to use merge because insert on conflict do update was blocking
            using raw_value new
                on (value.tenant, value.product, value.attribute) = (event.tenant, new.id::text, new.attribute)
            when matched then
                update set locale = new.locale,
                channel = new.channel,
                value = new.value
            when not matched then
                insert values(event.tenant, new.id::text, new.attribute, new.channel, new.locale, 'simple'::regconfig, new.value)
            ;

        when event.table_ = 'pim_catalog_product' and event.name = 'deleterows' then
            with to_delete as (
                select * from jsonb_populate_recordset(null::mysql_product, event.rows) r
            )
            delete from product
            using to_delete
            where (product.tenant, product.product) = (event.tenant, to_delete.id::text)
            ;

        else raise notice 'UNSUPPORTED %', event;
    end case;
-- exception when others then
--     raise warning 'error %', sqlerrm;
end $$;

create or replace function consume_queue(tenants text[] default null, batch_size int default 10) returns setof event
language sql volatile
set search_path to "mysql binlog"
as $$
with inflight as (
  select tenant, xid, index_ from event
  where case when tenants is null then true else tenant = any(tenants) end
  and not handled
  order by 1, 2, 3
  for update skip locked -- serializable? ok by tenant
  limit batch_size
)
delete from event
using inflight i
-- update event
-- set handled = true
-- from inflight i
where (event.tenant, event.xid, event.index_) = (i.tenant, i.xid, i.index_)
returning event.* -- (handle_mysql_event(event)).*
$$;

commit;
