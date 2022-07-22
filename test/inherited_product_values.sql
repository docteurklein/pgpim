do $it$
begin
set local search_path to pim, public;

raise notice 'query all attributes of a product, including inherited ones from ancestors';

set local role to app;
set local "app.tenant" to 'tenant#1';

insert into family (family, parent) values
('f1', null),
('f2', 'f1'),
('f3', 'f2');

insert into attribute (attribute, type, is_unique, scopable, localizable) values
('a1', 'text', false, false, false),
('a2', 'text', false, false, false),
('a3', 'text', false, false, false);

insert into family_has_attribute (family, attribute, to_complete) values
('f1', 'a1', true),
('f2', 'a2', true),
('f3', 'a3', true);

insert into product (product, parent, family) values
('p1', null, 'f1');
insert into product (product, parent, family) values
('p2', 'p1', 'f2');
insert into product (product, parent, family) values
('p3', 'p2', 'f3');

insert into product_value (product, attribute, channel, locale, value) values
('p1', 'a1', '__all__', '__all__', to_jsonb(text 'v1')),
('p2', 'a2', '__all__', '__all__', to_jsonb(text 'v2'));

assert count(_log(a, 'unexpected inherited value!')) = 0 from (
    with expected as (
        values
        ('p1', 'a1', to_jsonb(text 'v1')),
        ('p2', 'a2', to_jsonb(text 'v2'))
    ),
    actual as (
        select product, attribute, value from inherited_product_value where 'p3' = any(ancestors)
    )
    (table expected except table actual)
    union all
    (table actual except table expected)
) a;

rollback;
end
$it$;
