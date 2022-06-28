\set ON_ERROR_STOP on

begin;
-- set constraints all deferred;

set local search_path to pim;
set local role to app; -- rls compliant :)

insert into channel values ('ecommerce'), ('mobile');
insert into locale values ('fr_FR'), ('de_DE'), ('en_US');

insert into attribute (attribute, type, scopable, localizable) values
('description', 'text', true, true),
('image', 'image', true, true),
('seo', 'text', true, true),
('dimension', 'text', true, true),
('color', 'text', false, false),
('flashy', 'bool', false, false),
('size', 'number', false, false)
;

insert into family (family, parent) values
('shoe', null),
    ('shoe by color', 'shoe'),
        ('shoe by size', 'shoe by color')
;

insert into family_has_attribute (family, attribute, to_complete) values
('shoe', 'description', true),
('shoe', 'image', true),
('shoe', 'seo', false),
    ('shoe by color', 'color', true),
    ('shoe by color', 'flashy', true),
        ('shoe by size', 'size', true),
        ('shoe by size', 'dimension', false)
;

insert into product (product, parent, family) values
('nike air max', null, 'shoe');
insert into product (product, parent, family) values -- can't do in one onsert, RLS
    ('nike air max red', 'nike air max', 'shoe by color');
insert into product (product, parent, family) values
        ('nike air max red 13"', 'nike air max red', 'shoe by size');
;

insert into product_value (product, attribute, channel, locale, value) values
-- ('nike air max', 'description', 'ecommerce', 'en_US', to_jsonb(text 'Nice shoes')),
('nike air max', 'description', 'ecommerce', 'fr_FR', to_jsonb(text 'Belles chaussures')),
('nike air max', 'description', 'ecommerce', 'de_DE', to_jsonb(text 'Belles chaussures')),
('nike air max', 'image', 'ecommerce', 'en_US', to_jsonb(text 'https://example.org/nike-air-max.png')),
('nike air max', 'image', 'ecommerce', 'fr_FR', to_jsonb(text 'https://example.org/nike-air-max.png')),
    ('nike air max red', 'color', '__all__', '__all__', to_jsonb(text 'blue'))
        -- ('nike air max red 13"', 'size', '__all__', '__all__', to_jsonb(13))
;
commit;
