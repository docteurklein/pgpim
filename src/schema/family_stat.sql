create table family_stat (
    tenant netext,
    family text not null,
    num_products bigint not null,
    primary key (tenant, family),
    foreign key (tenant, family) references family (tenant, family)
        on update cascade
        on delete cascade
);

grant select on table family_stat to app;

alter table family_stat enable row level security;

create policy family_stat_by_tenant
on family_stat
to app
using (tenant = current_setting('app.tenant', true));

create policy family_stat_ivm
on family_stat
to ivm
using (true);

create function maintain_family_stat()
returns trigger
language plpgsql 
set search_path to pim, pg_catalog
security definer
as $$
begin
    with cs_stat as (
        select tenant, family, count(*)
        from change_set
        group by 1, 2
    )
    insert into family_stat
    select * from cs_stat
    on conflict (tenant, family)
    do update
    set num_products = family_stat.num_products + (
        case when TG_OP = 'INSERT'
            then + excluded.num_products
            else - excluded.num_products
        end
    );
    return null;
end
$$;

alter function maintain_family_stat owner to ivm;
grant insert, update, delete on table family_stat to ivm;

create trigger "002: maintain family_stat insert"
after insert
on product
referencing new table as change_set
for each statement
execute function maintain_family_stat();

create trigger "003: maintain family_stat delete"
after delete
on product
referencing old table as change_set
for each statement
execute function maintain_family_stat();
