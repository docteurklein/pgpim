use std::collections::HashMap;
use mysql::binlog::events::*;
use mysql::*;
use serde_json::*;
use serde::{Serialize};
use postgres_types::{ToSql, Json};

use postgres::{Client, NoTls};

#[derive(Debug, Serialize, ToSql)]
struct Event {
    table_: String,
    name: String,
    index_: i8,
    rows: Vec<String>
}

fn main() -> mysql::Result<()> {
    let mut pg = Client::connect("host=localhost user=postgres", NoTls).unwrap();
    let pos: i64 = pg.query_one("select max(next_position) from \"mysql binlog\".event", &[]).unwrap().get(0);
    let mut mysql = Conn::new(Opts::from_url("mysql://root:root@127.0.0.1:49153")?)?;
    let mut binlog_stream = mysql.get_binlog_stream(
            BinlogRequest::new(11114)
            .with_filename("91c70b079f9a-bin.000003".as_bytes().to_vec())
            .with_pos(4 as u64)
    ).unwrap();
    let mut tmes = HashMap::new();
    let mut events: Vec<RowsEventData> = vec!();

    while let Some(event) = binlog_stream.next() {
        let event = event.unwrap();
        if  let Some(e) = event.read_data()? {
            match e {
                EventData::RowsEvent(ee) => {
                    match ee {
                        RowsEventData::WriteRowsEvent(_) => {
                            //dbg!(eee);
                            events.push(ee.into_owned());
                        },
                        RowsEventData::UpdateRowsEvent(_) => {
                            events.push(ee.into_owned());
                        },
                        RowsEventData::DeleteRowsEvent(_) => {
                            events.push(ee.into_owned());
                        },
                        _ => {}
                    }
                }
                EventData::TableMapEvent(ee) => {
                    tmes.insert(ee.table_id(), ee.into_owned());
                }
                EventData::XidEvent(ee) => {
                    //dbg!(events.iter().map(|event| Event {
                    //        table: "product".to_string(),
                    //        name: "writerows".to_string(),
                    //        index_: 0,
                    //        rows: event.rows(&tmes[&event.table_id()])
                    //}).collect::<Vec<Event>>());
                    pg.execute("insert into \"mysql binlog\".event
                        (tenant, table_, name, xid, timestamp_, next_position, index_, rows)
                        select $1, table_, name, $2, $3, $4, index_, rows
                        from jsonb_populate_recordset(null::\"mysql binlog\".event, $5) _
                        on conflict do nothing;
                    ",
                    &[
                        &"tenant#1",
                        &(ee.xid as i64),
                        &(event.header().timestamp() as i64),
                        &(event.header().log_pos() as i64),
                        &Json::<Vec<Event>>(events.iter().map(|event| Event {
                            table_: "product".to_string(), // todo
                            name: "writerows".to_string(), // todo
                            index_: 0,
                            rows: event.rows(&tmes[&event.table_id()]).map(|r| { // @TODO how to get json here?
                                match r {
                                    Ok((before, after)) => format!("{:?}", after),
                                    Err(e) => format!("{:?}", e)
                                }
                            }).collect()
                        }).collect())
                    ]).unwrap();
                    events.clear();
                }
                _ => {}
            }
        };
    }
    Ok(())
}
