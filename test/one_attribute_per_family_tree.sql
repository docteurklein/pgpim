do $it$
begin
    set local search_path to pim;

    raise notice 'attribute appears only once in family tree';

    set local role to app;
    set local "app.tenant" to 'tenant#1';

    insert into family (family, parent) values
        ('f1', null),
        ('f2', 'f1');

    insert into attribute (attribute, type, is_unique, scopable, localizable) values
        ('a1', 'text', false, false, false),
        ('a2', 'text', false, false, false);

    insert into family_has_attribute (family, attribute, to_complete) values ('f1', 'a1', false);
    begin
        insert into family_has_attribute (family, attribute, to_complete) values ('f2', 'a1', false);
    exception when others then
        rollback;
        assert sqlerrm = 'new row violates row-level security policy "attribute appears at most once in family relatives" for table "family_has_attribute"';
        return;
    end;
    raise 'should have refused to insert';
end
$it$;
