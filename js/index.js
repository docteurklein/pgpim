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
    let lastTableMap = null;
    zongji.on('binlog', async function(evt) {
        if (evt.getEventName() === 'tablemap') {
            lastTableMap = evt.tableName;
            return;
        }
        let payload = [
            'tenant#1',
            evt.tableName || lastTableMap,
            evt.getEventName(),
            JSON.stringify(evt.rows)
        ];
        console.log(payload);
        const res = await client.query('call public.handle_mysql_event($1, $2, $3, $4)', payload);
    });
});


zongji.start({
  includeEvents: ['tablemap', 'writerows', 'updaterows', 'deleterows']
});

process.on('SIGINT', async function() {
  console.log('Got SIGINT.');
  zongji.stop();
  await client.end();
  process.exit();
});
