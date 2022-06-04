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
    foreign key (tenant, parent) references family (tenant, family) on delete cascade deferrable
);
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

create table category (
    tenant netext not null default current_setting('app.tenant', true),
    category netext not null,
    parent netext null,
    primary key (tenant, category),
    foreign key (tenant, parent) references category (tenant, category) on delete cascade deferrable
);
alter table category enable row level security;

create policy category_by_tenant
on category
to app
using (tenant = current_setting('app.tenant', true));

create recursive view category_ancestry (tenant, category, level, ancestors) with (security_invoker) as
select tenant, category, 1, '{}'::text[]
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
    primary key (tenant, attribute)
);
alter table attribute enable row level security;

create policy attribute_by_tenant
on attribute
to app
using (tenant = current_setting('app.tenant', true));

create table family_has_attribute (
    tenant netext not null default current_setting('app.tenant', true),
    family netext not null,
    attribute netext not null,
    primary key (tenant, family, attribute),
    foreign key (tenant, family) references family (tenant, family) on delete cascade,
    foreign key (tenant, attribute) references attribute (tenant, attribute) on delete cascade
);
alter table family_has_attribute enable row level security;

create policy family_has_attribute_by_tenant
on family_has_attribute
for all
to app
using (tenant = current_setting('app.tenant', true));

create function debug(inout anyelement) as $$ begin raise notice '%', $1; end $$ language plpgsql strict stable;

create policy family_has_no_parent_attribute
on family_has_attribute
as restrictive
for insert
to app
with check (
    not exists(
        select from family_has_attribute ancestor_has_attribute
        join family_ancestry f using (tenant)
        where family_has_attribute.family = f.family
        and ancestor_has_attribute.family = any(f.ancestors)
        and ancestor_has_attribute.attribute = family_has_attribute.attribute
    )
);
revoke update on family_has_attribute from app;

create table product (
    tenant netext not null default current_setting('app.tenant', true),
    product netext not null,
    parent netext null,
    family netext not null,
    primary key (tenant, product),
    foreign key (tenant, family) references family (tenant, family) on delete cascade,
    foreign key (tenant, parent) references product (tenant, product) on delete cascade deferrable
);
alter table product enable row level security;

create policy product_by_tenant
on product
to app
using (tenant = current_setting('app.tenant', true));

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
    foreign key (tenant, product) references product (tenant, product) on delete cascade,
    foreign key (tenant, category) references category (tenant, category) on delete cascade
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
    locale netext null,
    channel netext null,
    language regconfig null,
    value jsonb null,
    -- primary key (tenant, product, attribute, locale, channel), -- can't do, forces not null :/
    unique nulls not distinct (tenant, product, attribute, locale, channel),
    foreign key (tenant, product) references product (tenant, product) on delete cascade,
    foreign key (tenant, attribute) references attribute (tenant, attribute) on delete cascade
);
alter table product_value enable row level security;

create policy product_value_by_tenant
on product_value
to app
using (tenant = current_setting('app.tenant', true));

create function localized_tsvector(language netext, value jsonb) returns tsvector
as $$ select to_tsvector(language::regconfig, value); $$ -- wrapped because it fails as not immutable. why?
language sql strict immutable;

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

grant all on all tables in schema pim to app;

commit;
