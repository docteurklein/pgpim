\set ON_ERROR_STOP on
\timing on

begin;
-- set constraints all deferred;

set local search_path to pim;
set local role to app; -- rls compliant :)

-- truncate product, channel, locale, attribute, family cascade;
insert into locale (locale) values ('__all__') on conflict do nothing;
insert into channel (channel) values ('__all__') on conflict do nothing;

insert into channel (channel) values
    ('print')
;
insert into locale (locale, labels) values
    ('en_UK', '{}'),
    ('da_DK', '{}')
;

insert into attribute (attribute, type, is_unique, scopable, localizable) values
    ('description', 'text', false, true, true),
    ('ink', 'select', false, false, false)
on conflict do nothing
;

insert into family (family, parent) values
('pen', null),
    ('pen by ink', 'pen')
;

insert into family_has_attribute (family, attribute, to_complete) values
('pen', 'description', true),
    ('pen by ink', 'ink', true)
;

insert into product (product, parent, family) values
('bic', null, 'pen');
insert into product (product, parent, family) values
    ('blue bic', 'bic', 'pen by ink');

insert into select_option (attribute, option) values
    ('ink', 'blue'),
    ('ink', 'green')
;
insert into product_value (product, attribute, channel, locale, language, value) values
('bic', 'description', 'print', 'en_UK', 'english', to_jsonb(text 'The classical bic pen')),
    ('blue bic', 'ink', '__all__', '__all__', null, to_jsonb(text 'blue'))
;

commit;
vacuum analyze;
