const ZongJi = require('@vlasky/zongji');
const { Client } = require('pg').native;

const zongji = new ZongJi({
  host     : 'localhost',
  port     : '49153',
  user     : 'root',
  password : 'root',
  // debug: true
});


setInterval(() => {
        const used = process.memoryUsage().heapUsed / 1024 / 1024;
        console.log(`The script uses approximately ${Math.round(used * 100) / 100} MB`);
}, 1000);

const pg = new Client();

pg.connect().then(async function() {
    const lastPosition = await pg.query('select max(next_position) from "mysql binlog".event where tenant = $1', [process.argv[2]]);
    console.log(lastPosition.rows[0]);

    let events = [];
    let index = 0;
    let lastTableName = null;

    zongji.on('binlog', async function(evt) {
        if (evt.getEventName() === 'tablemap') {
            lastTableName = evt.tableName;
            return;
        }
        if (['writerows', 'updaterows', 'deleterows'].includes(evt.getEventName())) {
            events.push({
                tenant: process.argv[2],
                table_: evt.tableName || lastTableName,
                name: evt.getEventName(),
                index_: index++,
                rows: evt.rows,
            });
            return;
        }
        if (evt.getEventName() === 'xid') {
            try {
            await pg.query({
                name: 'upsert-mysql-binlog-event',
                text: `insert into "mysql binlog".event
                       (tenant, table_, name, xid, timestamp_, next_position, index_, rows)
                       select $1, table_, name, $2, $3, $4, index_, rows
                       from jsonb_populate_recordset(null::"mysql binlog".event, $5) _
                       on conflict do nothing;
                `,
                values: [
                    process.argv[2],
                    evt.xid,
                    evt.timestamp,
                    evt.nextPosition,
                    JSON.stringify(events)
                ]
            });
            events.length = 0;
            index = 0;
            return;
            } catch(e) { throw e }
        }
    });

    zongji.start({
        includeEvents: ['tablemap', 'xid', 'writerows', 'updaterows', 'deleterows'],
        filename: process.argv[3],
        position: lastPosition.rows[0].max
    });
}).catch(e => {console.log(e); process.exit(); });

process.on('SIGINT', async function() {
  console.log('Got SIGINT.');
  zongji.stop();
  await pg.end();
  process.exit();
});
