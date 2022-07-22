\set ON_ERROR_STOP on

begin;
-- set constraints all deferred;

set local search_path to pim;
set local role to app; -- rls compliant :)

insert into channel (channel) values ('ecommerce'), ('mobile');
insert into locale (locale) values ('fr_FR'), ('de_DE'), ('en_US');

insert into attribute (attribute, type, is_unique, scopable, localizable) values
('description', 'text', false, true, true),
('image', 'image', false, true, true),
('seo', 'text', false, true, true),
('dimension', 'text', false, true, true),
('color', 'text', false, false, false),
('flashy', 'bool', false, false, false),
('EAN', 'text', true, false, false),
('UPC', 'text', true, false, false),
('size', 'select', false, false, false)
;

insert into family (family, parent) values
('shoe', null),
    ('shoe by color', 'shoe'),
        ('shoe by size', 'shoe by color')
;

insert into family_has_attribute (family, attribute, to_complete) values
('shoe', 'EAN', true),
('shoe', 'UPC', true),
('shoe', 'description', true),
('shoe', 'image', true),
('shoe', 'seo', false),
    ('shoe by color', 'color', true),
    ('shoe by color', 'flashy', true),
        ('shoe by size', 'size', true),
        ('shoe by size', 'dimension', false)
;

insert into product (product, parent, family) values
('adidas', null, 'shoe'),
('nike air max', null, 'shoe');
insert into product (product, parent, family) values -- can't do in one insert because RLS (parent needs to be inserted first)
    ('nike air max red', 'nike air max', 'shoe by color');
insert into product (product, parent, family) values
        ('nike air max red 13', 'nike air max red', 'shoe by size'),
        ('nike air max red 14', 'nike air max red', 'shoe by size'),
        ('nike air max red 16', 'nike air max red', 'shoe by size')
        -- ('nike air max red 17', 'nike air max red', 'shoe by size'),
        -- ('nike air max red 18', 'nike air max red', 'shoe by size'),
        -- ('nike air max red 19', 'nike air max red', 'shoe by size'),
        -- ('nike air max red 20', 'nike air max red', 'shoe by size'),
        -- ('nike air max red 21', 'nike air max red', 'shoe by size'),
        -- ('nike air max red 22', 'nike air max red', 'shoe by size'),
        -- ('nike air max red 23', 'nike air max red', 'shoe by size'),
        -- ('nike air max red 24', 'nike air max red', 'shoe by size'),
        -- ('nike air max red 25', 'nike air max red', 'shoe by size'),
        -- ('nike air max red 26', 'nike air max red', 'shoe by size'),
        -- ('nike air max red 27', 'nike air max red', 'shoe by size'),
        -- ('nike air max red 28', 'nike air max red', 'shoe by size'),
        -- ('nike air max red 29', 'nike air max red', 'shoe by size');
;

insert into select_option (attribute, option) values
('size', '13'),
('size', '14'),
('size', '15');

insert into product_value (product, attribute, channel, locale, value) values
('nike air max', 'description', 'ecommerce', 'en_US', to_jsonb(text 'Nice shoes')),
('nike air max', 'description', 'mobile', 'en_US', to_jsonb(text 'Nice!')),
('nike air max', 'description', 'ecommerce', 'fr_FR', to_jsonb(text 'Belles chaussures')),
('nike air max', 'UPC', '__all__', '__all__', to_jsonb(text 'UPC1')),
('adidas', 'UPC', '__all__', '__all__', to_jsonb(text 'UPC2')),
('adidas', 'EAN', '__all__', '__all__', to_jsonb(text 'EAN2')),
-- ('nike air max', 'description', 'ecommerce', 'de_DE', to_jsonb(text 'Schöne Schuhe')),
('nike air max', 'image', 'ecommerce', 'en_US', to_jsonb(text 'https://example.org/nike-air-max.png')),
('nike air max', 'image', 'ecommerce', 'fr_FR', to_jsonb(text 'https://example.org/nike-air-max.png')),
    ('nike air max red', 'color', '__all__', '__all__', to_jsonb(text 'blue')),
        ('nike air max red 13', 'size', '__all__', '__all__', to_jsonb(array['13', '15']))
;
commit;
vacuum analyze;
