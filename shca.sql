begin;

drop schema if exists shca cascade;
create schema shca;
set local search_path to shca;

drop role if exists app;
create role app;
grant usage on schema shca to app;

create table family (
     tenant text not null,
     family text not null,
     parent text null,
     primary key (tenant, family),
     foreign key (tenant, parent) references family (tenant, family) on delete cascade deferrable
);
alter table family enable row level security;

create policy family_by_tenant
on family
-- as restrictive
to app
using (tenant = current_setting('app.tenant', true));

create recursive view family_ancestry (family, parent, level, ancestors) as
select family, parent, 1, '{}'::text[]
from family
where parent is null
union all
select child.family, child.parent, level + 1, ancestors || parent.family
from family_ancestry parent
join family child on child.parent = parent.family;

create table category (
     tenant text not null,
     category text not null,
     parent text null,
     primary key (tenant, category),
     foreign key (tenant, parent) references category (tenant, category) on delete cascade deferrable
);
alter table category enable row level security;

create policy category_by_tenant
on category
-- as restrictive
to app
using (tenant = current_setting('app.tenant', true));

create recursive view category_ancestry (category, level, ancestors) as
select category, 1, '{}'::text[]
from category
where parent is null
union all
select child.category, level + 1, ancestors || parent.category
from category_ancestry parent
join category child on child.parent = parent.category;

create table attribute (
    tenant text not null,
    attribute text not null,
    type text not null,
    primary key (tenant, attribute)
);
alter table attribute enable row level security;

create policy attribute_by_tenant
on attribute
-- as restrictive
to app
using (tenant = current_setting('app.tenant', true));

create table family_has_attribute (
     tenant text not null,
     family text not null,
     attribute text not null,
     primary key (tenant, family, attribute),
     foreign key (tenant, family) references family (tenant, family) on delete cascade,
     foreign key (tenant, attribute) references attribute (tenant, attribute) on delete cascade
);
alter table family_has_attribute enable row level security;

create policy family_has_attribute_by_tenant
on attribute
-- as permissive
for all
to app
using (tenant = current_setting('app.tenant', true));

create function debug_me(fha text) returns boolean
as $$
begin
	raise notice '%', fha;
	return true;
end;
$$ language 'plpgsql';

create function family_has_attribute_is_valid(_attribute text, _family text) returns boolean
as $$
select not exists(
    select from family_has_attribute fha
    join family_ancestry f using (family)
    where f.family = _family
    and fha.attribute = _attribute
)
$$ language sql strict volatile;

create policy family_has_no_parent_attribute
on family_has_attribute
-- as restrictive -- why can't I? there is a permissive one above
for insert
to app
with check (family_has_attribute_is_valid(attribute, family));

create table product (
    tenant text not null,
    product text not null,
    parent text null,
    family text not null,
    primary key (tenant, product),
    foreign key (tenant, family) references family (tenant, family) on delete cascade,
    foreign key (tenant, parent) references product (tenant, product) on delete cascade deferrable
);
alter table product enable row level security;

create policy product_by_tenant
on product
-- as restrictive
to app
using (tenant = current_setting('app.tenant', true));

create table product_in_category (
     tenant text not null,
     product text not null,
     category text not null,
     primary key (tenant, product, category),
     foreign key (tenant, product) references product (tenant, product) on delete cascade,
     foreign key (tenant, category) references category (tenant, category) on delete cascade
);
alter table product_in_category enable row level security;

create policy product_in_category_by_tenant
on product_in_category
-- as restrictive
to app
using (tenant = current_setting('app.tenant', true));

create table product_value (
    tenant text not null,
    product text not null,
    attribute text not null,
    locale text not null default '__all__', -- hack for nullable composite pkey. consider `__all__` to be NULL here, and must exist in ref table if used as fkey.
    channel text not null default '__all__', -- also, it means 2 values can coexist on the same attribute ("__all__" and a custom one). coalesce by hand if necessary.
    language text null,
    value jsonb null,
    primary key (tenant, product, attribute, locale, channel),
    unique nulls not distinct (tenant, product, attribute, locale, channel),
    foreign key (tenant, product) references product (tenant, product) on delete cascade,
    foreign key (tenant, attribute) references attribute (tenant, attribute) on delete cascade
);
alter table product_value enable row level security;

create policy product_value_by_tenant
on product_value
-- as restrictive
to app
using (tenant = current_setting('app.tenant', true));

create function localized_tsvector(language text, value jsonb) returns tsvector
as $$ select to_tsvector(language::regconfig, value); $$ -- wrapped because it fails as not immutable. why?
language sql strict immutable;

create index product_value_fts
on product_value
using gin
(localized_tsvector(language, value))
where jsonb_typeof(value) = 'string';

create view inherited_product_value (product, parent, family, attribute, locale, channel, value) as
with recursive product_ancestry (product, parent, family, path, level) as (
    select product, parent, family, array[product], 1
    from product
    union all
    select child.product, parent.product, parent.family, path || child.product, level + 1
    from product_ancestry child
    join product parent on child.product = parent.product
    where not child.product = any(path)
) -- search breadth first by tenant, product set ordercol
select product, parent, family, attribute, locale, channel, value
from product_ancestry
join product_value value using (product)
order by level desc;

grant all on all tables in schema shca to app;

commit;
