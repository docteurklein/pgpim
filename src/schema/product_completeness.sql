create table product_completeness (
    tenant netext,
    product text not null,
    channel text not null,
    locale text not null,
    filled bigint not null,
    to_complete bigint not null,
    total bigint not null,
    percent_to_complete decimal(6,3) not null
        generated always as ((filled::float / greatest(1, to_complete)) * 100) stored,
    percent_total decimal(6,3) not null
        generated always as ((filled::float / greatest(1, total)) * 100) stored,
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

grant select on table product_completeness to app;
grant insert, update on table product_completeness to ivm;

alter table product_completeness enable row level security;

create policy product_completeness_by_tenant
on product_completeness
to app
using (tenant = current_setting('app.tenant', true));

create view product_completeness_view (tenant, product, channel, locale, filled, to_complete, total) as
    with fha_stat (tenant, family, to_complete, total) as (
        select fha.tenant, fha.family,
            count(distinct fha.attribute) filter (where to_complete),
            count(distinct fha.attribute)
        from family_has_attribute fha
        group by 1, 2
    ),
    pv_stat (tenant, family, product, channel, locale, filled) as (
        select p.tenant, p.family, p.product,
        coalesce(c.channel, case when v.channel = '__all__' then c.channel else v.channel end),
        coalesce(l.locale, case when v.locale = '__all__' then l.locale else v.locale end),
        count(v.value) filter (where v.value not in (jsonb '{}', to_jsonb(text '')))
        from product p
        join locale l using (tenant)
        join channel c using (tenant)
        left join product_value v
            on p.tenant = v.tenant
            and p.product = v.product
            and c.channel = case when v.channel = '__all__' then c.channel else v.channel end
            and l.locale = case when v.locale = '__all__' then l.locale else v.locale end
        where c.channel <> '__all__'
        and l.locale <> '__all__'
        group by 1, 2, 3, 4, 5
    )
    select s.tenant, s.product, s.channel, s.locale, s.filled, fs.to_complete, fs.total
    from pv_stat s
    join fha_stat fs using (tenant, family)
;
grant select on table product_completeness_view to ivm;

create function maintain_product_completeness()
returns trigger
language plpgsql
set search_path to pim, pg_catalog
security definer
as $$
begin
    insert into product_completeness
    select distinct s.*
    from change_set v
    join product_completeness_view s using (tenant, product)
    where case when v.channel = '__all__' then true else s.channel = v.channel end
    and case when v.locale = '__all__' then true else s.locale = v.locale end
    on conflict (tenant, product, channel, locale)
    do update
    set filled = excluded.filled;
    return null;
end
$$;
alter function maintain_product_completeness owner to ivm;

create trigger "002: maintain product_completeness insert"
after insert on product_value
referencing new table as change_set
for each statement execute function maintain_product_completeness();

create trigger "003: maintain product_completeness update"
after update on product_value
referencing new table as change_set
for each statement execute function maintain_product_completeness();

create trigger "004: maintain product_completeness delete"
after delete on product_value
referencing old table as change_set
for each statement execute function maintain_product_completeness();
