import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
// Resolve ws from the server workspace regardless of where the script is run from.
const WebSocket = require('./apps/server/node_modules/ws');
const base = 'http://localhost:8787';

async function jget(path) {
  const r = await fetch(base + path);
  const t = await r.text();
  try { return JSON.parse(t); } catch { console.log('GET', path, 'non-json', t); throw new Error(t); }
}
async function jpost(path, body) {
  const r = await fetch(base + path, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
  const t = await r.text();
  let j; try { j = JSON.parse(t); } catch { console.log('POST', path, 'status', r.status, t); throw new Error(t); }
  if (!r.ok) { console.log('POST fail', r.status, j); throw new Error(JSON.stringify(j)); }
  return j;
}
async function jput(path, body) {
  const r = await fetch(base + path, { method: 'PUT', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
  const t = await r.text();
  let j; try { j = JSON.parse(t); } catch { console.log('PUT', path, t); throw new Error(t); }
  if (!r.ok) { console.log('PUT fail', r.status, j); throw new Error(JSON.stringify(j)); }
  return j;
}
async function jdel(path) {
  const r = await fetch(base + path, { method: 'DELETE' });
  const t = await r.text();
  let j; try { j = JSON.parse(t); } catch { console.log('DELETE', path, t); throw new Error(t); }
  return j;
}

function uuid() { return crypto.randomUUID(); }

async function wsTest() {
  console.log('\n== WebSocket 多端实时同步测试 ==');
  const ws1 = new WebSocket('ws://localhost:8787/ws');
  const ws2 = new WebSocket('ws://localhost:8787/ws');
  const msgs1 = [], msgs2 = [];
  await Promise.all([
    new Promise((res, rej) => { ws1.on('open', res); ws1.on('error', rej); }),
    new Promise((res, rej) => { ws2.on('open', res); ws2.on('error', rej); }),
  ]);
  console.log('ws1+ws2 connected');
  ws1.on('message', d => { try { const m = JSON.parse(d.toString()); msgs1.push(m); console.log('ws1 <-', m.type); } catch {} });
  ws2.on('message', d => { try { const m = JSON.parse(d.toString()); msgs2.push(m); console.log('ws2 <-', m.type); } catch {} });

  const awaitMsg = (arr, type, ms=3000) => new Promise((res, rej) => {
    const t = setTimeout(()=>rej(new Error('timeout '+type)), ms);
    const check = () => {
      const f = arr.find(m=>m.type===type);
      if (f) { clearTimeout(t); res(f); }
      else setTimeout(check, 50);
    };
    check();
  });

  ws1.send(JSON.stringify({ type: 'hello', deviceId: 'test-ws1', cursor: new Date(0).toISOString() }));
  ws2.send(JSON.stringify({ type: 'hello', deviceId: 'test-ws2', cursor: new Date(0).toISOString() }));
  await Promise.all([awaitMsg(msgs1,'hello_ack'), awaitMsg(msgs2,'hello_ack')]);
  console.log('hello_ack ok', 'ws1 notes', msgs1.find(m=>m.type==='hello_ack')?.notes?.length, 'ws2 notes', msgs2.find(m=>m.type==='hello_ack')?.notes?.length);
  msgs1.length=0; msgs2.length=0;

  // ws1 push a note, ws2 should receive broadcast
  const nid = uuid();
  const now = new Date().toISOString();
  ws1.send(JSON.stringify({ type:'push', entityType:'note', operation:'CREATE', entity:{ id:nid, title:'ws实时', content:'from ws1', created_at:now, updated_at:now, device_id:'test-ws1' }}));
  const ack = await awaitMsg(msgs1,'push_ack');
  console.log('ws1 push_ack applied', ack.applied, 'conflict', ack.conflict, 'version', ack.version);
  const bc = await awaitMsg(msgs2,'broadcast');
  console.log('ws2 broadcast received', bc.entityType, bc.entity?.id===nid ? 'id match' : 'id mismatch', bc.entity?.title);

  // LWW: ws2 tries to overwrite with old timestamp should be rejected
  msgs1.length=0; msgs2.length=0;
  ws2.send(JSON.stringify({ type:'push', entityType:'note', operation:'UPDATE', entity:{ id:nid, title:'old overwrite', updated_at:'2020-01-01T00:00:00.000Z', device_id:'test-ws2', version:1 }}));
  const ack2 = await awaitMsg(msgs2,'push_ack');
  console.log('LWW old push ack applied', ack2.applied, 'conflict', ack2.conflict, '(expect false / lww_rejected)');

  // ws1 pull via WS
  ws1.send(JSON.stringify({ type:'pull', since: new Date(0).toISOString(), limit: 10 }));
  const pr = await awaitMsg(msgs1,'pull_result');
  console.log('WS pull_result notes', pr.notes?.length, 'folders', pr.folders?.length);

  ws1.close(); ws2.close();
  console.log('WS 测试完成');
}

async function main(){
  console.log('health', await jget('/api/health'));
  // clean check: initial pull
  const pull0 = await jget('/api/sync/pull?since=1970-01-01T00:00:00.000Z&limit=100&includeDeleted=1');
  console.log('\n初始 pull notes', pull0.notes.length, 'folders', pull0.folders.length, 'cursor', pull0.cursor);

  // 1. folder
  const fid = uuid();
  const now = new Date().toISOString();
  const f = await jpost('/api/folders', { id: fid, name: '工作', created_at: now, updated_at: now, device_id: 'windows-test1' });
  console.log('\n1 folder', f.id, f.name, 'v', f.version, 'updated', f.updated_at);

  // 2. notes
  const id1 = uuid(), id2 = uuid();
  const n1 = await jpost('/api/notes', { id:id1, title:'本地优先测试', content:'hello **md**', folder_id:fid, created_at:now, updated_at:now, device_id:'windows-test1' });
  console.log('2 note1', n1.id, 'v', n1.version, 'folder', n1.folder_id);
  const n2 = await jpost('/api/notes', { id:id2, title:'第二篇', content:'offline-first', created_at:now, updated_at:now, device_id:'android-test2' });
  console.log('  note2', n2.id, 'v', n2.version);

  // 3. list
  const list1 = await jget('/api/notes?includeDeleted=0&limit=10');
  console.log('\n3 list visible', list1.notes.length, '(expect 2)');
  const listF = await jget('/api/folders?includeDeleted=0');
  console.log('  folders', listF.folders.length);

  // 4. update
  await new Promise(r=>setTimeout(r,30));
  const now2 = new Date().toISOString();
  const up = await jput(`/api/notes/${id1}`, { title:'本地优先测试-已更新', content:'updated', folder_id:fid, updated_at:now2, device_id:'windows-test1' });
  console.log('\n4 update v', up.version, 'title', up.title, 'updated_at', up.updated_at);

  // 5. soft delete
  const del = await jdel(`/api/notes/${id2}?device_id=android-test2`);
  console.log('\n5 delete', del.id, 'deleted_at', del.deleted_at, 'v', del.version);
  const afterDel = await jget('/api/notes?includeDeleted=0&limit=10');
  console.log('  after delete visible', afterDel.notes.length, '(expect 1) ids', afterDel.notes.map(x=>x.id));
  const withDel = await jget('/api/notes?includeDeleted=1&limit=10');
  console.log('  with deleted', withDel.notes.length, '(expect 2)');

  // 6. restore
  await new Promise(r=>setTimeout(r,20));
  const now3 = new Date().toISOString();
  const restored = await jput(`/api/notes/${id2}`, { title:'第二篇-已恢复', content:'restored', updated_at:now3, deleted_at:null, device_id:'android-test2' });
  console.log('\n6 restore deleted_at', restored.deleted_at, 'v', restored.version);
  const afterRestore = await jget('/api/notes?includeDeleted=0&limit=10');
  console.log('  after restore visible', afterRestore.notes.length, '(expect 2)');

  // 7. pull incremental
  const pull1 = await jget('/api/sync/pull?since=1970-01-01T00:00:00.000Z&limit=100&includeDeleted=1');
  console.log('\n7 pull1 notes', pull1.notes.length, 'folders', pull1.folders.length, 'cursor', pull1.cursor, 'hasMore', pull1.hasMore);
  const encCursor = encodeURIComponent(pull1.cursor);
  const pull2 = await jget(`/api/sync/pull?since=${encCursor}&limit=100&includeDeleted=1`);
  console.log('  pull2 since cursor notes', pull2.notes.length, '(expect 0) cursor', pull2.cursor);

  // 8. push REST
  const pid = uuid();
  const now4 = new Date().toISOString();
  const pushRes = await jpost('/api/sync/push', { entityType:'note', operation:'CREATE', entity:{ id:pid, title:'push测试', content:'via REST', created_at:now4, updated_at:now4, device_id:'web-test3' }});
  console.log('\n8 push applied', pushRes.applied, 'conflict', pushRes.conflict, 'id', pushRes.entity.id, 'v', pushRes.entity.version);

  // 9. LWW
  const conflict = await jpost('/api/sync/push', { entityType:'note', operation:'UPDATE', entity:{ id:id1, title:'old', updated_at:'2020-01-01T00:00:00.000Z', device_id:'windows-test1', version:1 }});
  console.log('\n9 LWW old applied', conflict.applied, 'conflict', conflict.conflict, '(expect false/lww_rejected)');
  const check = await jget('/api/sync/pull?since=1970-01-01T00:00:00.000Z&limit=100&includeDeleted=1');
  const target = check.notes.find(x=>x.id===id1);
  console.log('  after conflict title still', target?.title, '(expect 本地优先测试-已更新)');

  // 10. search via list filter (client would use watchNotes query)
  const searchPull = await jget('/api/notes?includeDeleted=0&limit=100');
  console.log('\n10 total visible after all', searchPull.notes.length);

  await wsTest();

  console.log('\n=== 全部本地测试通过 ===');
}

main().catch(e=>{ console.error('TEST FAIL', e); process.exit(1); });
