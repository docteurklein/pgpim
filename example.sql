\set ON_ERROR_STOP on
\timing on

begin;
set constraints all deferred;

set local search_path to pim;

-- truncate product, channel, locale, attribute, family cascade;
-- insert into locale (locale) values ('__all__');
-- insert into channel (channel) values ('__all__');

set local role to app; -- rls compliant :)

insert into channel (channel) values
    ('ecommerce'),
    ('mobile')
;
insert into locale (locale, labels) values
    ('fr_FR', jsonb_build_object('en_US', 'French', 'fr_FR', 'Français')),
    ('de_DE', jsonb_build_object('en_US', 'German', 'de_DE', 'Deutsch')),
    ('en_US', '{}');

insert into attribute (attribute, type, is_unique, scopable, localizable) values
('description', 'text', false, true, true),
('image', 'url', false, true, true),
('seo', 'text', false, false, true),
('dimension', 'text', false, true, false),
('color', 'text', false, false, false),
('flashy', 'bool', false, false, false),
('EAN', 'text', true, false, false),
('UPC', 'text', true, false, false),
('size', 'select', false, false, false),
('essence', 'select', false, false, false),
('styles', 'multiselect', false, false, false)
;

insert into family (family, parent) values
('shoe', null),
    ('shoe by color', 'shoe'),
        ('shoe by size', 'shoe by color')
;
insert into family (family, parent) values
('table', null),
    ('table by essence', 'table')
;

insert into family_has_attribute (family, attribute, to_complete) values
('shoe', 'EAN', true),
('shoe', 'styles', false),
('shoe', 'UPC', true),
('shoe', 'description', true),
('shoe', 'image', true),
('shoe', 'seo', false),
    ('shoe by color', 'color', true),
    ('shoe by color', 'flashy', true),
        ('shoe by size', 'size', true),
        ('shoe by size', 'dimension', false)
;
insert into family_has_attribute (family, attribute, to_complete) values
('table', 'size', false),
('table', 'dimension', false),
    ('table by essence', 'color', false),
    ('table by essence', 'essence', true)
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
;
insert into product (product, parent, family) values
('2023 garden table', null, 'table');
insert into product (product, parent, family) values
    ('eben 2023 garden table', '2023 garden table', 'table by essence');

insert into select_option (attribute, option) values
('size', '13'),
('size', '14'),
('size', '15');

insert into select_option (attribute, option) values
('styles', 'sport'),
('styles', 'music'),
('styles', 'nature');

insert into select_option (attribute, option) values
('essence', 'eben'),
('essence', 'accacia');

insert into product_value (product, attribute, channel, locale, language, value) values
('adidas', 'UPC', '__all__', '__all__', null, to_jsonb(text 'UPC2')),
('adidas', 'EAN', '__all__', '__all__', null, to_jsonb(text 'EAN2')),
('nike air max', 'description', 'ecommerce', 'en_US', 'italian', to_jsonb(text 'Nice shoes')),
('nike air max', 'styles', '__all__', '__all__', null, to_jsonb(array['sport', 'music'])),
('nike air max', 'description', 'mobile', 'en_US', 'english', to_jsonb(text 'Nice!')),
('nike air max', 'description', 'ecommerce', 'fr_FR', 'french', to_jsonb(text 'Belles chaussures')),
('nike air max', 'UPC', '__all__', '__all__', null, to_jsonb(text 'UPC1')),
('nike air max', 'image', 'ecommerce', 'en_US', null, to_jsonb(text '')),
('nike air max', 'image', 'ecommerce', 'fr_FR', null, to_jsonb(text 'https://example.org/nike-air-max.png')),
-- ('nike air max', 'description', 'ecommerce', 'de_DE', to_jsonb(text 'Schöne Schuhe')),
    ('nike air max red', 'color', '__all__', '__all__', null, to_jsonb(text 'blue')),
        ('nike air max red 13', 'size', '__all__', '__all__', null, to_jsonb(text '13'))
;

insert into product_value (product, attribute, channel, locale, language, value) values
('eben 2023 garden table', 'essence', '__all__', '__all__', null, to_jsonb(text 'eben'))
;

insert into role (role, permissions) values
    ('admin', '{}'),
    ('editor', array['view', 'write']),
    ('seo', array['meta', 'title']),
    ('config', array['settings', 'timeouts'])
;
insert into role_inherits_role (role, inherited) values
    ('admin', 'config'),
    ('admin', 'editor'),
    ('editor', 'seo')
;
insert into "user" ("user") values
    ('alice'),
    ('bob')
;
insert into "grant" ("user", role) values 
    ('alice', 'admin'),
    ('bob', 'seo')
;

commit;
vacuum analyze;
