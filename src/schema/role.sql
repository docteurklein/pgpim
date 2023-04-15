create table "user" (
    tenant netext default current_setting('app.tenant', true),
    "user" netext not null,
    primary key (tenant, "user")
);

grant select, insert ("user"), update ("user") on table "user" to app;

create table role (
    tenant netext default current_setting('app.tenant', true),
    role netext not null,
    permissions netext[] not null default '{}',
    primary key (tenant, role)
);
grant select, insert (role, permissions), update (role, permissions) on table role to app;

create table role_inherits_role (
    tenant netext default current_setting('app.tenant', true),
    role netext not null,
    inherited text not null,
    primary key (tenant, role, inherited),
    foreign key (tenant, role) references role (tenant, role)
        on update cascade
        on delete cascade,
    foreign key (tenant, inherited) references role (tenant, role)
        on update cascade
        on delete cascade
);
grant select, insert (role, inherited), update (role, inherited) on table role_inherits_role to app;

create table "grant" (
    tenant netext default current_setting('app.tenant', true),
    "user" text not null,
    role text not null,
    primary key (tenant, "user", role),
    foreign key (tenant, "user") references "user" (tenant, "user")
        on update cascade
        on delete cascade,
    foreign key (tenant, role) references role (tenant, role)
        on update cascade
        on delete cascade
);
grant select, insert ("user", role), update ("user", role) on table "grant" to app;

create aggregate array_accum(anycompatiblearray)
(
    sfunc = array_cat,
    stype = anycompatiblearray,
    initcond = '{}'
); 

create view user_permissions (tenant, "user", permissions)
with (security_invoker)
as with recursive inherited_role (tenant, role) as (
    select * from role
    union all
    select r.* from inherited_role r
    join role_inherits_role rir on (r.role) = (rir.inherited)
) cycle role set is_cycle using path
select u.tenant, u."user", array_accum(permissions)
from "user" u
join "grant" using ("user")
join inherited_role using (role)
group by 1, 2;

grant select on table user_permissions to app;
