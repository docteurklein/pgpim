const ZongJi = require('@vlasky/zongji');
const { Client } = require('pg');

const zongji = new ZongJi({
  host     : 'localhost',
  port     : '49153',
  user     : 'root',
  password : 'root',
  // debug: true
});

const client = new Client();
client.connect().then(function() {
    let events = [];
    zongji.on('binlog', async function(evt) {
        if (evt.getEventName() === 'tablemap') {
            lastTableMap = evt.tableName;
            return;
        }
        if (['writerows', 'updaterows', 'deleterows'].includes(evt.getEventName())) {
            events.push({
                tenant: 'tenant#1',// TODO argv or env
                table: evt.tableName || lastTableMap,
                name: evt.getEventName(),
                rows: JSON.stringify(evt.rows)
            });
        }
        if (evt.getEventName() === 'xid') {
            events.forEach(async (payload, index) => {
                await client.query({
                    name: 'upsert-mysql-binlog-event',
                    text: `insert into "mysql binlog".event
                           (tenant, table_, name, xid, timestamp_, next_position, index_, rows)
                           values ($1, $2, $3, $4, $5, $6, $7, $8)
                           on conflict do nothing
                    `,
                    values: [
                        payload.tenant,
                        payload.table,
                        payload.name,
                        evt.xid,
                        evt.timestamp,
                        evt.nextPosition,
                        index,
                        payload.rows
                    ]
                })
            });
            events = [];
        }
    });
});


zongji.start({
  includeEvents: ['tablemap', 'xid', 'writerows', 'updaterows', 'deleterows']
});

process.on('SIGINT', async function() {
  console.log('Got SIGINT.');
  zongji.stop();
  await client.end();
  process.exit();
});
