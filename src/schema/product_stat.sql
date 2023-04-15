create table product_stat (
    tenant netext,
    product text not null,
    channel text not null,
    locale text not null,
    filled bigint not null,
    to_complete bigint not null,
    total bigint not null,
    percent_to_complete decimal(6,3) not null generated always as (((filled::float / greatest(1, to_complete))) * 100) stored,
    percent_total decimal(6,3) not null generated always as (((filled::float / greatest(1, total))) * 100) stored,
    primary key (tenant, product, channel, locale),
    foreign key (tenant, product) references product (tenant, product)
        on update cascade
        on delete cascade,
    foreign key (tenant, channel) references channel (tenant, channel)
        on update cascade
        on delete cascade,
    foreign key (tenant, locale) references locale (tenant, locale)
        on update cascade
        on delete cascade
);

grant select on table product_stat to app;
grant insert, update on table product_stat to ivm;

alter table product_stat enable row level security;

create policy product_stat_by_tenant
on product_stat
to app
using (tenant = current_setting('app.tenant', true));

create policy product_stat_ivm on product_stat to ivm using (true);
create policy product_stat_ivm on family_has_attribute to ivm using (true);
create policy product_stat_ivm on locale to ivm using (true);
create policy product_stat_ivm on channel to ivm using (true);
create policy product_stat_ivm on product to ivm using (true);

create function maintain_product_stat()
returns trigger
language plpgsql 
set search_path to pim, pg_catalog
security definer
as $$
begin
    with fha_stat (tenant, family, to_complete, total) as (
        select tenant, family, count(*) filter (where to_complete), count(*)
        from family_has_attribute
        group by 1, 2
    ),
    cs_stat as (
        select p.tenant, p.family, p.product,
        coalesce(c.channel, case when value.channel = '__all__' then c.channel else value.channel end) channel,
        coalesce(l.locale, case when value.locale = '__all__' then l.locale else value.locale end) locale,
        count(value) filter (where value not in (jsonb '{}', to_jsonb(text ''))) filled
        from product p
        join locale l using (tenant)
        join channel c using (tenant)
        left join change_set value
            on p.tenant = value.tenant
            and p.product = value.product
            and c.channel = case when value.channel = '__all__' then c.channel else value.channel end
            and l.locale = case when value.locale = '__all__' then l.locale else value.locale end
        where c.channel <> '__all__'
        and l.locale <> '__all__'
        group by 1, 2, 3, 4, 5
    )
    insert into product_stat
    select css.tenant, css.product, css.channel, css.locale, css.filled, fs.to_complete, fs.total
    from cs_stat css
    join fha_stat fs using (tenant, family)
    on conflict (tenant, product, channel, locale)
    do update
    set filled = product_stat.filled + (
        case when TG_OP in ('INSERT', 'UPDATE')
            then + excluded.filled
            else - excluded.filled
        end
    );
    return null;
end
$$;
alter function maintain_product_stat owner to ivm;

create trigger "002: maintain product_stat insert"
after insert on product_value
referencing new table as change_set
for each statement execute function maintain_product_stat();

create trigger "003: maintain product_stat update"
after update on product_value
referencing new table as change_set
for each statement execute function maintain_product_stat();

create trigger "004: maintain product_stat delete"
after delete on product_value
referencing old table as change_set
for each statement execute function maintain_product_stat();


