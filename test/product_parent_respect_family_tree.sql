do $it$
begin
    set local search_path to pim;

    perform public.notice(text 'product''s parent respect family tree');

    set local role to app;
    set local "app.tenant" to 'tenant#1';

    insert into family (family, parent) values
        ('f1', null),
        ('f3', null),
        ('f2', 'f1');

    insert into product (product, parent, family) values ('p1', null, 'f1');
    insert into product (product, parent, family) values ('p2', 'p1', 'f2');

    begin
        insert into product (product, parent, family) values
            ('p3', 'p2', 'f3');
    exception when others then
        rollback;
        assert sqlerrm = 'new row violates row-level security policy "product''s family must respect parent''s family" for table "product"';
        return;
    end;
    raise 'should have refused to insert';
end
$it$;
