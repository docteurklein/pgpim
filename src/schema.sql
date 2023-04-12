\set ON_ERROR_STOP on

begin;

drop schema if exists pim cascade;
create schema pim;
set local search_path to pim;

create extension if not exists pg_trgm schema public;

drop role if exists app;
create role app;
grant usage on schema pim to app;

create domain netext as text constraint "non-empty text" check (trim(value) <> '');

create table "user" (
    
);

create table locale (
    tenant netext default current_setting('app.tenant', true),
    locale netext,
    labels jsonb not null default '{}',
    primary key (tenant, locale)
);

create index locale_labels on locale using gin (to_tsvector('simple', labels));

grant select, insert (locale), update (locale) on table locale to app;

alter table locale enable row level security;
create policy "see all" on locale for all to app using (true);
create policy "keep __all__ on update" on locale as restrictive for update to app using (locale <> '__all__');
create policy "keep __all__ on delete" on locale as restrictive for delete to app using (locale <> '__all__');

grant select, insert, delete, update (locale, labels) on table locale to app;

insert into locale (locale) values ('__all__'); -- equivalent to NULL

create table channel (
    tenant netext default current_setting('app.tenant', true),
    channel netext,
    labels jsonb not null default '{}',
    primary key (tenant, channel)
);

alter table locale enable row level security;
create policy "see all" on channel for all to app using (true);
create policy "keep __all__ on update" on channel as restrictive for update to app using (channel <> '__all__');
create policy "keep __all__ on delete" on channel as restrictive for delete to app using (channel <> '__all__');

grant select, insert, delete, update (channel, labels) on table channel to app;

insert into channel (channel) values ('__all__');

create table family (
    tenant netext default current_setting('app.tenant', true),
    family text not null,
    labels jsonb not null default '{}',
    parent text null,
    primary key (tenant, family),
    foreign key (tenant, parent) references family (tenant, family)
        on update cascade
        on delete cascade deferrable
);

grant select, insert, delete, update (family, labels) on table family to app; -- changing parent would break product constraints
alter table family enable row level security;

create policy family_by_tenant
on family
to app
using (tenant = current_setting('app.tenant', true));

create recursive view family_ancestry (tenant, family, parent, level, ancestors)
with (security_invoker)
as select tenant, family, parent, 1, '{}'::text[]
from family
where parent is null
union all
select child.tenant, child.family, child.parent, level + 1, ancestors || parent.family
from family_ancestry parent
join family child on child.parent = parent.family;

grant select on table family_ancestry to app;

create view family_with_relatives 
with (security_invoker)
as select fa.*, coalesce(
    array_agg(descendant.family) filter (where descendant.family is not null),
    '{}'
) descendants
from family_ancestry fa
left join family_ancestry descendant on fa.family = any(descendant.ancestors)
group by 1, 2, 3, 4, 5;

grant select on table family_with_relatives to app;

create table category (
    tenant netext default current_setting('app.tenant', true),
    category netext,
    labels jsonb not null default '{}',
    parent text null,
    primary key (tenant, category),
    foreign key (tenant, parent) references category (tenant, category)
        on update cascade
        on delete cascade deferrable
);

grant select, insert, delete, update (category, labels, parent) on table category to app;
alter table category enable row level security;

create policy category_by_tenant
on category
to app
using (tenant = current_setting('app.tenant', true));

create recursive view category_ancestry (tenant, category, level, ancestors)
with (security_invoker)
as select tenant, category, 1, '{}'
from category
where parent is null
union all
select child.tenant, child.category, level + 1, ancestors || child.parent
from category_ancestry parent
join category child on child.parent = parent.category;

create table attribute (
    tenant netext default current_setting('app.tenant', true),
    attribute netext,
    labels jsonb not null default '{}',
    type netext,
    is_unique boolean not null,
    scopable boolean not null,
    localizable boolean not null,
    primary key (tenant, attribute)
);
grant select, insert, delete, update (attribute, labels) on table attribute to app; -- updating something else would invalidate product_value

alter table attribute enable row level security;

create policy attribute_by_tenant
on attribute for all to app
using (tenant = current_setting('app.tenant', true));

create table family_has_attribute (
    tenant netext default current_setting('app.tenant', true),
    family text not null, -- not null, otherwise it's a draft
    attribute text not null,
    to_complete boolean not null,
    primary key (tenant, family, attribute),
    foreign key (tenant, family) references family (tenant, family)
        on update cascade
        on delete cascade,
    foreign key (tenant, attribute) references attribute (tenant, attribute)
        on update cascade
        on delete cascade
);
grant select, insert, delete on table family_has_attribute to app;
alter table family_has_attribute enable row level security;

create policy family_has_attribute_by_tenant
on family_has_attribute
for all
to app
using (tenant = current_setting('app.tenant', true));

create policy "attribute appears at most once in family relatives"
on family_has_attribute
as restrictive
for insert
to app
with check (
    not exists (
        select from family_has_attribute relative_has_attribute
        join family_with_relatives f using (tenant)
        where family_has_attribute.family = f.family
        and family_has_attribute.attribute = relative_has_attribute.attribute
        and (
            relative_has_attribute.family = any(f.ancestors)
            or relative_has_attribute.family = any(f.descendants)
        )
    )
);

create table product (
    tenant netext default current_setting('app.tenant', true),
    product netext,
    parent text null,
    family text not null,
    primary key (tenant, product),
    foreign key (tenant, family) references family (tenant, family)
        on update cascade
        on delete cascade,
    foreign key (tenant, parent) references product (tenant, product)
        on update cascade
        on delete cascade deferrable
);
grant select, insert, delete, update (product) on table product to app; -- updating parent or family would break policies
alter table product enable row level security;

create index product_parent on product (tenant, parent);
create index product_family on product (tenant, family);

create policy product_by_tenant
on product
to app
using (tenant = current_setting('app.tenant', true));

create policy "product's family must respect parent's family"
on product
as restrictive
for insert
to app
with check (
    parent is null or exists (
        select from product p
        join family pf using (family)
        join family on family.family = product.family
        where p.product = product.parent
        and pf.family = family.parent
    )
);

create table product_descendant (
    tenant netext default current_setting('app.tenant', true),
    product text not null,
    descendant text not null,
    primary key (tenant, product, descendant),
    foreign key (tenant, product) references product (tenant, product)
        on update cascade
        on delete cascade,
    foreign key (tenant, descendant) references product (tenant, product)
        on update cascade
        on delete cascade
);

grant select on table product_descendant to app;

alter table product_descendant enable row level security;

create policy product_descendant_by_tenant
on product_descendant
to app
using (tenant = current_setting('app.tenant', true));

create function maintain_product_descendants()
returns trigger
language plpgsql 
set search_path to pim, pg_catalog
security definer
as $$
begin
    with recursive ancestry (tenant, descendant, ancestor) as (
        select tenant, product, parent
        from new_product
        union all
        select parent.tenant, a.descendant, parent.parent
        from ancestry a
        join product parent on (a.tenant, a.ancestor) = (parent.tenant, parent.product)
    )
    insert into product_descendant
    select tenant, ancestor, descendant
    from ancestry a
    where ancestor is not null;

    return null;
end
$$;

create trigger "001: maintain product_descendants"
after insert
on product
referencing new table as new_product
for each statement
execute function maintain_product_descendants();

create table family_stat (
    tenant netext,
    family text not null,
    num_products bigint not null,
    primary key (tenant, family),
    foreign key (tenant, family) references family (tenant, family)
        on update cascade
        on delete cascade
);

grant select on table family_stat to app;

alter table family_stat enable row level security;

create policy family_stat_by_tenant
on family_stat
to app
using (tenant = current_setting('app.tenant', true));

create function maintain_family_stat()
returns trigger
language plpgsql 
set search_path to pim, pg_catalog
security definer
as $$
begin
    with cs_stat as (
        select tenant, family, count(product)
        from change_set
        group by 1, 2
    )
    insert into family_stat
    select * from cs_stat
    on conflict (tenant, family)
    do update
    set num_products = family_stat.num_products + (
        case when TG_OP = 'INSERT'
            then + excluded.num_products
            else - excluded.num_products
        end
    );
    return null;
end
$$;

create trigger "002: maintain family_stat insert"
after insert
on product
referencing new table as change_set
for each statement
execute function maintain_family_stat();

create trigger "003: maintain family_stat delete"
after delete
on product
referencing old table as change_set
for each statement
execute function maintain_family_stat();

create recursive view product_ancestry (tenant, product, parent, family, level, ancestors)
with (security_invoker)
as select tenant, product, parent, family, 1, '{}'::text[]
from product
where parent is null
union all
select child.tenant, child.product, child.parent, child.family, level + 1, ancestors || child.parent
from product_ancestry parent
join product child on child.parent = parent.product;

grant select on table product_ancestry to app;

create table product_in_category (
    tenant netext default current_setting('app.tenant', true),
    product text not null,
    category text not null,
    primary key (tenant, product, category),
    foreign key (tenant, product) references product (tenant, product)
        on update cascade
        on delete cascade,
    foreign key (tenant, category) references category (tenant, category)
        on update cascade
        on delete cascade
);

grant select, insert, delete, update on table product_in_category to app;
alter table product_in_category enable row level security;

create policy product_in_category_by_tenant
on product_in_category
to app
using (tenant = current_setting('app.tenant', true));

create table select_option (
    tenant netext default current_setting('app.tenant', true),
    attribute text not null,
    option netext,
    labels jsonb not null default '{}',
    primary key (tenant, attribute, option),
    foreign key (tenant, attribute) references attribute (tenant, attribute)
        on update cascade
        on delete cascade
);
grant select, insert, delete, update (option, labels) on table select_option to app;
alter table select_option enable row level security;

create policy select_option_by_tenant
on select_option
to app
using (tenant = current_setting('app.tenant', true));

create policy "select options are for (multi)select attributes only"
on select_option
as restrictive
for insert
to app
with check (
    exists(
        select from attribute
        where attribute = select_option.attribute
        and type in ('select', 'multiselect')
    )
);

create table product_value (
    tenant netext default current_setting('app.tenant', true),
    product text not null,
    attribute text not null,
    locale text not null default '__all__',
    channel text not null default '__all__',
    language text null,
    type netext,
    is_unique boolean not null,
    value jsonb not null,
    primary key (tenant, product, attribute, locale, channel), -- need __all__ instead of null
    -- constraint "unique" unique nulls not distinct (tenant, product, attribute, locale, channel), -- cool, but no replica identity with NULL
    foreign key (tenant, channel) references channel (tenant, channel)
        on update cascade
        on delete cascade,
    foreign key (tenant, locale) references locale (tenant, locale)
        on update cascade
        on delete cascade,
    foreign key (tenant, product) references product (tenant, product)
        on update cascade
        on delete cascade,
    foreign key (tenant, attribute) references attribute (tenant, attribute)
        on update cascade
        on delete cascade
);

grant
    select,
    insert (product, attribute, locale, channel, language, value), -- app role cannot decide attribute's is_unique or type
    update (locale, channel, language, value),
    delete
on table product_value to app;

alter table product_value enable row level security;
create policy product_value_by_tenant
on product_value
to app
using (tenant = current_setting('app.tenant', true));

create policy "attribute exists in product's family at correct tree level"
on product_value
as restrictive
for insert
to app
with check (exists(
    select from family_has_attribute fha
    where fha.attribute = product_value.attribute
    and fha.family = (select family from product where product = product_value.product)
));

create policy "has channel/locale if attribute is scopable/localizable"
on product_value
as restrictive
for insert
to app
with check (exists(
    select from attribute a
    where product_value.attribute = a.attribute 
    and case when a.scopable then product_value.channel <> '__all__' else product_value.channel = '__all__' end
    and case when a.localizable then product_value.locale <> '__all__' else product_value.locale = '__all__' end
));

create function denormarlize_attribute()
returns trigger
language plpgsql 
set search_path to pim, pg_catalog
security definer
as $$
begin
    select is_unique, type
    into strict new.is_unique, new.type
    from attribute
    where attribute = new.attribute;
    return new;
end
$$;

create trigger "001: denormarlize_attribute"
before insert on product_value
for each row when (new.is_unique is null or new.type is null)
execute function denormarlize_attribute();

create function check_select_options()
returns trigger
language plpgsql 
set search_path to pim, pg_catalog
parallel safe
security definer
as $$
begin
    assert jsonb_agg(option) = case when new.type = 'select' then to_jsonb(array[new.value]) else new.value end
        from select_option
        where new.value ? option
        and new.attribute = attribute
    , format('invalid option in %L for attribute %L', new.value, new.attribute);
    return new;
end
$$;

create constraint trigger "002: check select_options"
after insert or update of value
on product_value
from select_option
deferrable
for each row when (new.type in ('select', 'multiselect'))
execute function check_select_options();

create unique index unique_attribute on product_value (tenant, attribute, locale, channel, value)
where is_unique;

create function ts_lang(text) returns regconfig
immutable strict
begin atomic;
select coalesce((select cfgname::regconfig from pg_ts_config where cfgname = $1), 'simple')::regconfig;
end;

create index product_value_fts on product_value
using gin (to_tsvector(ts_lang(language), value))
where language is not null;

create view inherited_product_value (tenant, product, attribute, locale, channel, language, value, ancestors)
with (security_invoker)
as select value.tenant, value.product, attribute, locale, channel, language, value, ancestors || p.product
from product_ancestry p
join product_value value using (tenant)
where value.product = any(ancestors || p.product)
;

grant select on table inherited_product_value to app;

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

alter table product_stat enable row level security;

create policy product_stat_by_tenant
on product_stat
to app
using (tenant = current_setting('app.tenant', true));

create function maintain_product_stat()
returns trigger
language plpgsql 
set search_path to pim, pg_catalog
security definer
as $$
begin
    with family_stat (family, to_complete, total) as (
        select family, count(*) filter (where to_complete), count(*)
        from family_has_attribute
        group by family
    ),
    cs_stat as (
        select p.tenant, p.family, p.product,
        coalesce(c.channel, case when value.channel = '__all__' then c.channel else value.channel end) channel,
        coalesce(l.locale, case when value.locale = '__all__' then l.locale else value.locale end) locale,
        count(value) filter (where value not in (jsonb '{}', to_jsonb(text ''))) filled
        from product p
        cross join locale l
        cross join channel c
        left join change_set value
            on value.product = p.product
            and case when value.channel = '__all__' then c.channel else value.channel end = c.channel
            and case when value.locale = '__all__' then l.locale else value.locale end = l.locale
        where c.channel <> '__all__'
        and l.locale <> '__all__'
        group by 1, 2, 3, 4, 5
    )
    insert into product_stat
    select tenant, product, channel, locale, filled, to_complete, total
    from cs_stat
    join family_stat using (family)
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


create view product_form (
    tenant,
    product,
    via,
    attribute,
    type,
    channel,
    locale,
    is_unique,
    to_complete,
    language,
    value
)
with (security_invoker)
as select
    p.tenant,
    coalesce(pd.descendant, p.product),
    p.product,
    fha.attribute,
    a.type,
    jsonb_build_object(
        'value', c.channel,
        'in', case when a.localizable then 'select channel from channel' end
    ),
    jsonb_build_object(
        'value', l.locale,
        'in', case when a.scopable then 'select locale from locale' end
    ),
    a.is_unique,
    fha.to_complete,
    jsonb_build_object(
        'value', language,
        'in', $sql$
            select cfgname from pg_ts_config
            where case when $1 is not null then cfgname ilike concat('%', $1, '%') else true end
        $sql$,
        'args', array['language']
    ),
    jsonb_build_object(
        'value', value,
        'in', jsonb_build_object(
            'sql', case when a.type in ('select', 'multiselect')
                then format($sql$
                    select option from select_option
                    where attribute = %L
                    and case when $1 is not null then option ilike concat('%%', $1, '%%') else true end
                $sql$,
                a.attribute)
            end,
            'args', array['value']
        ),
        'edit', jsonb_build_object(
            'sql', $sql$
                insert into product_value (product, attribute, channel, locale, language, value)
                values ($1, $2, $3, $4, $5, $6)
                on conflict (tenant, product, attribute, channel, locale)
                do update
                set language = excluded.language,
                value = excluded.value
            $sql$,
            'args', array['product', 'attribute', 'channel', 'locale', 'language', 'value']
        )
    )
from product p
left join product_descendant pd using (product)
cross join locale l
cross join channel c
join family_has_attribute fha using (family)
join attribute a using (attribute)
left join product_value value
    on value.product = p.product
    and value.attribute = fha.attribute
    and value.channel = c.channel
    and value.locale = l.locale
where case when a.scopable
    then c.channel <> '__all__'
    else c.channel = '__all__' end
and case when a.localizable
    then l.locale <> '__all__'
    else l.locale = '__all__' end
;

grant select on table product_form to app;

commit;
