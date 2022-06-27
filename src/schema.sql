\set ON_ERROR_STOP on

begin;

drop schema if exists pim cascade;
create schema pim;
set local search_path to pim;

drop role if exists app;
create role app;
grant usage on schema pim to app;

create domain netext as text constraint "non-empty text" check (value <> '');

create table family (
    tenant netext not null default current_setting('app.tenant', true),
    family netext not null,
    parent netext null,
    primary key (tenant, family),
    foreign key (tenant, parent) references family (tenant, family)
        on update cascade
        on delete cascade deferrable
);
grant update (family) on table family to app;
alter table family enable row level security;

create policy family_by_tenant
on family
to app
using (tenant = current_setting('app.tenant', true));

create recursive view family_ancestry (tenant, family, parent, level, ancestors) with (security_invoker) as
select tenant, family, parent, 1, '{}'::text[]
from family
where parent is null
union all
select child.tenant, child.family, child.parent, level + 1, ancestors || parent.family
from family_ancestry parent
join family child on child.parent = parent.family;

create view family_with_relatives as
select fa.*, coalesce(
    array_agg(descendant.family) filter (where descendant.family is not null),
    '{}'
) descendants
from family_ancestry fa
left join family_ancestry descendant on fa.family = any(descendant.ancestors)
group by 1, 2, 3, 4, 5;

create table category (
    tenant netext not null default current_setting('app.tenant', true),
    category netext not null,
    parent netext null,
    primary key (tenant, category),
    foreign key (tenant, parent) references category (tenant, category)
        on update cascade
        on delete cascade deferrable
);
grant update (category) on table category to app;
alter table category enable row level security;

create policy category_by_tenant
on category
to app
using (tenant = current_setting('app.tenant', true));

create recursive view category_ancestry (tenant, category, level, ancestors) with (security_invoker) as
select tenant, category, 1, '{}'
from category
where parent is null
union all
select child.tenant, child.category, level + 1, ancestors || child.parent
from category_ancestry parent
join category child on child.parent = parent.category;

create table attribute (
    tenant netext not null default current_setting('app.tenant', true),
    attribute netext not null,
    type netext not null,
    scopable boolean not null default false,
    localizable boolean not null default false,
    primary key (tenant, attribute)
);
grant update (attribute) on table attribute to app;
alter table attribute enable row level security;

create policy attribute_by_tenant
on attribute
to app
using (tenant = current_setting('app.tenant', true));

create table family_has_attribute (
    tenant netext not null default current_setting('app.tenant', true),
    family netext not null, -- not null, otherwise it's a draft
    attribute netext not null,
    to_complete boolean not null,
    primary key (tenant, family, attribute),
    foreign key (tenant, family) references family (tenant, family)
        on update cascade
        on delete cascade,
    foreign key (tenant, attribute) references attribute (tenant, attribute)
        on update cascade
        on delete cascade
);
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
    tenant netext not null default current_setting('app.tenant', true),
    product netext not null,
    parent netext null,
    family netext not null,
    primary key (tenant, product),
    foreign key (tenant, family) references family (tenant, family)
        on update cascade
        on delete cascade,
    foreign key (tenant, parent) references product (tenant, product)
        on update cascade
        on delete cascade deferrable
);
grant update (product) on table product to app;
alter table product enable row level security;

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

create recursive view product_ancestry (tenant, product, parent, family, level, ancestors) with (security_invoker) as
select tenant, product, parent, family, 1, '{}'::text[]
from product
where parent is null
union all
select child.tenant, child.product, child.parent, child.family, level + 1, ancestors || child.parent
from product_ancestry parent
join product child on child.parent = parent.product;

create table product_in_category (
    tenant netext not null default current_setting('app.tenant', true),
    product netext not null,
    category netext not null,
    primary key (tenant, product, category),
    foreign key (tenant, product) references product (tenant, product)
        on update cascade
        on delete cascade,
    foreign key (tenant, category) references category (tenant, category)
        on update cascade
        on delete cascade
);
alter table product_in_category enable row level security;

create policy product_in_category_by_tenant
on product_in_category
to app
using (tenant = current_setting('app.tenant', true));

create table product_value (
    tenant netext not null default current_setting('app.tenant', true),
    product netext not null,
    attribute netext not null,
    locale netext not null default '__all__', -- hack for pk
    channel netext not null default '__all__',
    language regconfig null,
    value jsonb not null,
    primary key (tenant, product, attribute, locale, channel),
    -- constraint "unique" unique nulls not distinct (tenant, product, attribute, locale, channel),
    foreign key (tenant, product) references product (tenant, product)
        on update cascade
        on delete cascade,
    foreign key (tenant, attribute) references attribute (tenant, attribute)
        on update cascade
        on delete cascade
);
grant update (locale, channel, language, value) on table product_value to app;
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
    with product_family as (select family from product where product = product_value.product)
    select from family_has_attribute fha
    join product_family using (family)
    where fha.attribute = product_value.attribute
));

create policy "has channel/locale if attribute is scopable/localizable"
on product_value
as restrictive
for insert
to app
with check (exists(
    select from attribute a
    where product_value.attribute = a.attribute 
    and (
        (a.scopable and product_value.channel <> '__all__')
        or (not a.scopable and product_value.channel = '__all__')
    )
    and (
        (a.localizable and product_value.locale <> '__all__')
        or (not a.localizable and product_value.locale = '__all__')
    )
));

create index product_value_fts
on product_value
using gin
(to_tsvector(language, value))
where jsonb_typeof(value) = 'string'
and language is not null
;

create view inherited_product_value (tenant, product, attribute, locale, channel, language, value, ancestors) with (security_invoker) as
select value.tenant, value.product, attribute, locale, channel, language, value, ancestors || pa.product
from product_ancestry pa
join product_value value using (tenant)
where value.product = any(ancestors || pa.product)
;

create view product_completeness (tenant, product, channel, locale, completed, to_complete, total) as
select fha.tenant, product.product, channel, locale,
    count(1) filter (where value is not null),
    count(1) filter (where to_complete),
    count(1)
from product
join family_has_attribute fha using (family)
-- join attribute using (attribute)
left join product_value value
    on value.product = product.product
    and value.attribute = fha.attribute
group by 1, 2, 3, 4
;

grant select, insert, delete on all tables in schema pim to app;

commit;
