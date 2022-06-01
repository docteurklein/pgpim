\set ON_ERROR_STOP on

begin;

set local search_path to shca;

create or replace function lorem() returns text as $$
with words(words) as (select array['lorem', 'ipsum', 'dolor', 'sit', 'amet', 'consectetur', 'adipiscing', 'elit', 'a', 'ac', 'accumsan', 'ad', 'aenean', 'aliquam', 'aliquet', 'ante', 'aptent', 'arcu', 'at', 'auctor', 'augue', 'bibendum', 'blandit', 'class', 'commodo', 'condimentum', 'congue', 'consequat', 'conubia', 'convallis', 'cras', 'cubilia', 'cum', 'curabitur', 'curae', 'cursus', 'dapibus', 'diam', 'dictum', 'dictumst', 'dignissim', 'dis', 'donec', 'dui', 'duis', 'egestas', 'eget', 'eleifend', 'elementum', 'enim', 'erat', 'eros', 'est', 'et', 'etiam', 'eu', 'euismod', 'facilisi', 'facilisis', 'fames', 'faucibus', 'felis', 'fermentum', 'feugiat', 'fringilla', 'fusce', 'gravida', 'habitant', 'habitasse', 'hac', 'hendrerit', 'himenaeos', 'iaculis', 'id', 'imperdiet', 'in', 'inceptos', 'integer', 'interdum', 'justo', 'lacinia', 'lacus', 'laoreet', 'lectus', 'leo', 'libero', 'ligula', 'litora', 'lobortis', 'luctus', 'maecenas', 'magna', 'magnis', 'malesuada', 'massa', 'mattis', 'mauris', 'metus', 'mi', 'molestie', 'mollis', 'montes', 'morbi', 'mus', 'nam', 'nascetur', 'natoque', 'nec', 'neque', 'netus', 'nibh', 'nisi', 'nisl', 'non', 'nostra', 'nulla', 'nullam', 'nunc', 'odio', 'orci', 'ornare', 'parturient', 'pellentesque', 'penatibus', 'per', 'pharetra', 'phasellus', 'placerat', 'platea', 'porta', 'porttitor', 'posuere', 'potenti', 'praesent', 'pretium', 'primis', 'proin', 'pulvinar', 'purus', 'quam', 'quis', 'quisque', 'rhoncus', 'ridiculus', 'risus', 'rutrum', 'sagittis', 'sapien', 'scelerisque', 'sed', 'sem', 'semper', 'senectus', 'sociis', 'sociosqu', 'sodales', 'sollicitudin', 'suscipit', 'suspendisse', 'taciti', 'tellus', 'tempor', 'tempus', 'tincidunt', 'torquent', 'tortor', 'tristique', 'turpis', 'ullamcorper', 'ultrices', 'ultricies', 'urna', 'ut', 'varius', 'vehicula', 'vel', 'velit', 'venenatis', 'vestibulum', 'vitae', 'vivamus', 'viverra', 'volutpat', 'vulputate'])
select array_to_string(
    words[greatest(1, random() * 10):greatest(array_length(words, 1), random() * 100)]
, ' ') from words;
$$ language sql volatile;

create or replace function sentence() returns text as $$
    select sentence from sentence tablesample bernoulli(20) limit 1
$$ language sql volatile;

set local role app;
-- select set_config('app.tenant', 'tenant#1', true);

-- truncate family cascade;
insert into family (tenant, family, parent)
with recursive tree(family, parent, level) as (
    select 'family#' || i, null, 1 from generate_series(1, 5) i
    union all
    select format('%s.%s', tree.family, j), tree.family, level + 1 from generate_series(1, 3) j, tree
    where level < 2
)
select current_setting('app.tenant', true), family, parent from tree;

-- truncate attribute cascade;
insert into attribute (tenant, attribute, type)
select current_setting('app.tenant', true), 'attribute#' || i, 'text'
from generate_series(1, 5) i;

insert into attribute (tenant, attribute, type)
select current_setting('app.tenant', true), 'parent attribute#' || i, 'text'
from generate_series(1, 5) i;

-- truncate family_has_attribute cascade;
insert into family_has_attribute (tenant, family, attribute)
select tenant, family, attribute
from family
join attribute using (tenant)
where parent is not null
and family.tenant = current_setting('app.tenant', true)
and attribute not like 'parent attr%';

insert into family_has_attribute (tenant, family, attribute)
select current_setting('app.tenant', true), family, attribute
from family
join attribute using (tenant)
where parent is null
and attribute like 'parent attr%';

-- truncate product cascade;
insert into product (tenant, product, parent, family)
select current_setting('app.tenant', true), format('product#%s of %s', i, family), null, family
from generate_series(1, 3) i,
family
where family.parent is null;

insert into product (tenant, product, parent, family)
select current_setting('app.tenant', true), format('child %s of %s', random(), product), product, family_child.family
from product
join family using(tenant, family)
join family family_child on family_child.parent = family.family
-- where family.parent is not null;
;

-- truncate product_value cascade;
insert into product_value (tenant, product, attribute, locale, channel, language, value)
select current_setting('app.tenant', true), product, attribute, locale, channel, 'simple', to_jsonb(sentence())
from (values ('en_EN'), ('de_DE')) locale (locale),
(values ('ecommerce'), ('print')) channel (channel),
product
join family_has_attribute using (tenant, family)
join family using (tenant, family)
join attribute using (tenant, attribute)
where product.parent is not null
and family.parent is not null
and attribute not like 'parent attr%';
;

insert into product_value (tenant, product, attribute, locale, channel, language, value)
select current_setting('app.tenant', true), product, attribute, null, null, 'simple', to_jsonb('parent data: ' || sentence())
from product
join family_has_attribute using (tenant, family)
join family using (tenant, family)
join attribute using (tenant, attribute)
where product.parent is null
and family.parent is null
and attribute like 'parent attr%';

commit;
