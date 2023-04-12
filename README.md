#pgpim

## install
```
psql -c "set app.tenant to 'tenant#1'"  -f src/schema.sql -f example.sql
```

## tests
```
find test -name '*.sql' -printf '%h/%f\n' | sort -V | xargs psql -f
```


## whatever

aka, only provide columns you are interested in, `whatever(oid)` will do the rest

```
begin;
set constraints all deferred;
set local app.tenant to 't1';

insert into pim.family select * from jsonb_populate_recordset(
    null::pim.family,
    to_jsonb(array[
        whatever('pim.family'::regclass, jsonb_build_object(
            'family', 'parent1'
        )),
        whatever('pim.family'::regclass, jsonb_build_object(
            'parent', 'parent1'
        ))
    ])
);
commit
```
