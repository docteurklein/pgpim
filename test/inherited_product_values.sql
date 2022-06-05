do $it$
begin
    set local search_path to pim;

    perform notice(text 'query all attributes of a product, including inherited ones from ancestors');

    set local role to app;
    set local "app.tenant" to 'tenant#1';

    insert into family (family, parent) values
        ('f1', null),
        ('f2', 'f1'),
        ('f3', 'f2');

    insert into attribute (attribute, type) values
        ('a1', 'text'),
        ('a2', 'text'),
        ('a3', 'text');

    insert into product (product, parent, family) values
        ('p1', null, 'f1'),
        ('p2', 'p1', 'f2'),
        ('p3', 'p2', 'f3');

end
$it$;
