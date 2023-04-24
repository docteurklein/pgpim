\set ON_ERROR_STOP on
\timing on

set search_path to pim;
alter table product_descendant set unlogged;
alter table product_in_category set unlogged;
alter table product_value set unlogged;
alter table product_completeness set unlogged;
alter table product set unlogged;

begin;


create or replace function lorem(size int default 1) returns text as $$
with words(words) as (select array['lorem', 'ipsum', 'dolor', 'sit', 'amet', 'consectetur', 'adipiscing', 'elit', 'a', 'ac', 'accumsan', 'ad', 'aenean', 'aliquam', 'aliquet', 'ante', 'aptent', 'arcu', 'at', 'auctor', 'augue', 'bibendum', 'blandit', 'class', 'commodo', 'condimentum', 'congue', 'consequat', 'conubia', 'convallis', 'cras', 'cubilia', 'cum', 'curabitur', 'curae', 'cursus', 'dapibus', 'diam', 'dictum', 'dictumst', 'dignissim', 'dis', 'donec', 'dui', 'duis', 'egestas', 'eget', 'eleifend', 'elementum', 'enim', 'erat', 'eros', 'est', 'et', 'etiam', 'eu', 'euismod', 'facilisi', 'facilisis', 'fames', 'faucibus', 'felis', 'fermentum', 'feugiat', 'fringilla', 'fusce', 'gravida', 'habitant', 'habitasse', 'hac', 'hendrerit', 'himenaeos', 'iaculis', 'id', 'imperdiet', 'in', 'inceptos', 'integer', 'interdum', 'justo', 'lacinia', 'lacus', 'laoreet', 'lectus', 'leo', 'libero', 'ligula', 'litora', 'lobortis', 'luctus', 'maecenas', 'magna', 'magnis', 'malesuada', 'massa', 'mattis', 'mauris', 'metus', 'mi', 'molestie', 'mollis', 'montes', 'morbi', 'mus', 'nam', 'nascetur', 'natoque', 'nec', 'neque', 'netus', 'nibh', 'nisi', 'nisl', 'non', 'nostra', 'nulla', 'nullam', 'nunc', 'odio', 'orci', 'ornare', 'parturient', 'pellentesque', 'penatibus', 'per', 'pharetra', 'phasellus', 'placerat', 'platea', 'porta', 'porttitor', 'posuere', 'potenti', 'praesent', 'pretium', 'primis', 'proin', 'pulvinar', 'purus', 'quam', 'quis', 'quisque', 'rhoncus', 'ridiculus', 'risus', 'rutrum', 'sagittis', 'sapien', 'scelerisque', 'sed', 'sem', 'semper', 'senectus', 'sociis', 'sociosqu', 'sodales', 'sollicitudin', 'suscipit', 'suspendisse', 'taciti', 'tellus', 'tempor', 'tempus', 'tincidunt', 'torquent', 'tortor', 'tristique', 'turpis', 'ullamcorper', 'ultrices', 'ultricies', 'urna', 'ut', 'varius', 'vehicula', 'vel', 'velit', 'venenatis', 'vestibulum', 'vitae', 'vivamus', 'viverra', 'volutpat', 'vulputate'])
select array_to_string(
    words[1:size]
, ' ') from words;
$$ language sql volatile;

-- create table sentence (
--     language text not null default 'english',
--     sentence text not null
-- );
-- \copy sentence(sentence) from 'sentences.txt' with (format text);
-- 
-- alter table sentence alter language set default 'french';
-- \copy sentence(sentence) from 'french.txt' with (format text);
-- 
-- grant select on sentence to app;
-- 
-- create or replace function sentence() returns text as $$
--     select sentence from sentence tablesample bernoulli(1) limit 1
-- $$ language sql volatile;

set local role to app;
-- select set_config('app.tenant', 'tenant#1', true);

insert into channel (channel) values ('ecommerce'), ('print');
insert into locale (locale) values ('fr_FR'), ('de_DE'), ('en_US');

-- truncate family cascade;
insert into family (family, parent)
with recursive tree(family, parent, level) as (
    select 'family#' || i, null, 1 from generate_series(1, 20) i
    union all
    select format('%s.%s', tree.family, j), tree.family, level + 1
    from
    tree,
    generate_series(1, 3 - level) j
    where level < 3
)
select family, parent from tree;

-- truncate attribute cascade;
insert into attribute (attribute, type, scopable, localizable, is_unique)
select 'attribute#' || i, 'text', true, true, i % 3 = 0
from generate_series(1, 20) i;

insert into attribute (attribute, type, scopable, localizable, is_unique)
select 'parent attribute#' || i, 'text', false, false, i % 3 = 0
from generate_series(1, 10) i;

-- truncate family_has_attribute cascade;
insert into family_has_attribute (family, attribute, to_complete)
select family, attribute, random() > 0.5
from family, attribute
where parent is not null
and attribute not like 'parent attr%';

insert into family_has_attribute (family, attribute, to_complete)
select family, attribute, random() > 0.5
from family, attribute
where parent is null
and attribute like 'parent attr%';

commit;
begin;

-- truncate product cascade;
insert into product (product, parent, family)
select format('product#%s', random()), null, family
from generate_series(1, 1000) i,
family
where family.parent is null;

insert into product (product, parent, family)
select format('child %s', random()), product, family_child.family
from product
join family using(family)
join family family_child on family_child.parent = family.family
;

commit;
begin;

-- truncate product_value cascade;
insert into product_value (product, attribute, locale, channel, language, value)
select product, attribute, '__all__', '__all__', 'simple'::regconfig, to_jsonb('parent data: ' || random()::text)
from product
join family_has_attribute using (family)
join family using (family)
join attribute using (attribute)
where product.parent is null
and family.parent is null
and random() > 0.8
;

commit;
begin;

insert into product_value (product, attribute, locale, channel, language, value)
select product, attribute, locale, channel, 'simple'::regconfig, to_jsonb(random()::text)
from (values ('en_US'), ('de_DE')) locale (locale),
(values ('ecommerce'), ('print')) channel (channel),
product
join family_has_attribute using (family)
join family using (family)
join attribute using (attribute)
where product.parent is not null
and family.parent is not null
and random() > 0.7
;

commit;
vacuum analyze;
