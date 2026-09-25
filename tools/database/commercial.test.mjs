import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';
import { btree_gist } from '@electric-sql/pglite/contrib/btree_gist';

test('Commercial database: pricing snapshots, calendar and permissions', async t => {
 const db = new PGlite({extensions:{btree_gist}});
 t.after(()=>db.close());
 await db.exec(`create role anon; create role authenticated; create schema auth;
 create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz,invited_at timestamptz);
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 grant usage on schema auth to authenticated; grant execute on function auth.uid() to authenticated;`);
 const dir = new URL('../../supabase/migrations/',import.meta.url);
 for (const f of (await readdir(dir)).filter(f=>f.endsWith('.sql')).sort()) {
   await db.exec('begin');
   await db.exec(await readFile(new URL(f,dir),'utf8'));
   await db.exec('commit');
 }
 const one=async(sql,args=[]) => (await db.query(sql,args)).rows[0];
 const id=async(sql,args=[]) => (await one(sql,args)).id;
 async function staff(role) {
   const u=await id(`insert into auth.users(id,email) values(gen_random_uuid(),'test@example.invalid') returning id`);
   await db.query(`update public.profiles set user_kind='employee',is_active=true,activated_at=now() where id=$1`,[u]);
   await db.query('insert into public.user_roles(user_id,role) values($1,$2)',[u,role]); return u;
 }
 const manager=await staff('availability_manager'), pricing=await staff('pricing_manager'), sales=await staff('sales');
 async function asUser(u,sql,args=[]) {
   await db.exec('begin; set local role authenticated');
   try { await db.query("select set_config('request.jwt.claim.sub',$1,true)",[u]); const r=await db.query(sql,args); await db.exec('commit');return r.rows; }
   catch(e) { await db.exec('rollback');throw e; }
 }
 const product=await id(`insert into products(code,name,commercial_unit,visibility) values('P1','Valla','mes','visible') returning id`);
 const asset=await id(`insert into inventory_assets(product_id,canonical_code,name,visibility,operational,is_provisional,booking_mode)
 values($1,'A1','Valla A','visible','operational',false,'exclusive_daily') returning id`,[product]);
 const account=await id("insert into customer_accounts(name) values('Empresa A') returning id");
 const price=await id(`insert into product_price_versions(product_id,version,amount,commercial_unit,tax_percent,valid_from,valid_until,state,created_by,published_by,published_at)
 values($1,1,100000,'mes',19,current_date-1,current_date+365,'published',$2,$2,now()) returning id`,[product,pricing]);
 const add=(u,start,end,kind='maintenance',expires=null,evidence=null)=>asUser(u,
 'select public.add_availability($1,$2,$3,$4,$5,$6,null,$7) as id',[asset,start,end,kind,'Motivo verificado',expires,evidence]);
 await t.test('new tables have RLS and neither anonymous reads nor direct authenticated writes',async()=>{
   const rows=(await db.query(`select relname,relrowsecurity,has_table_privilege('anon',c.oid,'SELECT') as anon,
   has_table_privilege('authenticated',c.oid,'INSERT,UPDATE,DELETE') as writes
   from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and relkind='r'`)).rows;
   assert.equal(rows.length,18); for(const r of rows){assert.equal(r.relrowsecurity,true);assert.equal(r.anon,false);assert.equal(r.writes,false);}
 });
 await t.test('availability permission is separate from pricing and sales',async()=>{
   await assert.rejects(add(pricing,'2027-01-01','2027-01-03'),e=>e.code==='42501');
   await assert.rejects(add(sales,'2027-01-01','2027-01-03'),e=>e.code==='42501');
   assert.equal((await asUser(manager,'select * from product_price_versions')).length,0);
 });
 let booking;
 await t.test('inclusive dates prevent overlap and permit the following day',async()=>{
   booking=(await add(manager,'2027-01-01','2027-01-03'))[0].id;
   await assert.rejects(add(manager,'2027-01-03','2027-01-04'),e=>e.code==='23P01');
   await add(manager,'2027-01-04','2027-01-04');
 });
 await t.test('revision check protects cancellation and keeps an immutable history',async()=>{
   await assert.rejects(asUser(manager,'select public.cancel_availability($1,9,$2)',[booking,'Cancelado']),e=>e.code==='40001');
   await asUser(manager,'select public.cancel_availability($1,1,$2)',[booking,'Cancelado por cambio']);
   assert.equal(Number((await one('select count(*) from availability_events where entry_id=$1',[booking])).count),2);
   await assert.rejects(asUser(manager,'delete from availability_events'),e=>e.code==='42501');
   await add(manager,'2027-01-01','2027-01-03');
 });
 await t.test('reservations require evidence and unsupported shared capacity fails closed',async()=>{
   await assert.rejects(add(manager,'2027-02-01','2027-02-02','reservation'),e=>e.code==='23514');
   await add(manager,'2027-02-01','2027-02-02','reservation',null,'private-document-reference');
   await db.query("update inventory_assets set booking_mode='shared_pending' where id=$1",[asset]);
   await assert.rejects(add(manager,'2027-03-01','2027-03-02'),e=>e.code==='23514');
   await db.query("update inventory_assets set booking_mode='exclusive_daily' where id=$1",[asset]);
 });
 await t.test('expired holds are released atomically before new occupancy',async()=>{
   const expired=await id(`insert into availability_entries(asset_id,starts_on,ends_on,kind,expires_at,created_at,reason,created_by,updated_by)
   values($1,'2027-04-01','2027-04-02','hold',now()-interval '1 hour',now()-interval '2 hours','Expired test',$2,$2) returning id`,[asset,manager]);
   await add(manager,'2027-04-01','2027-04-02');
   assert.equal((await one('select status from availability_entries where id=$1',[expired])).status,'expired');
 });
 await t.test('published prices are immutable and cannot overlap',async()=>{
   await assert.rejects(db.query('update product_price_versions set amount=1 where id=$1',[price]),e=>e.code==='23514');
   await assert.rejects(db.query(`insert into product_price_versions(product_id,version,amount,commercial_unit,tax_percent,valid_from,valid_until,state,created_by,published_by,published_at)
   values($1,2,120000,'mes',19,current_date,current_date+1,'published',$2,$2,now())`,[product,pricing]),e=>e.code==='23P01');
 });
 let quote;
 await t.test('quote lines use official prices and totals, ignoring supplied amounts',async()=>{
   quote=await id(`insert into quotes(customer_id,created_by,customer_snapshot,valid_until) values($1,$2,'{"name":"Empresa A"}',current_date+15) returning id`,[account,sales]);
   await db.query(`insert into quote_lines(quote_id,line_number,product_id,price_version_id,quantity,periods,unit_price,tax_percent,product_snapshot)
   values($1,1,$2,$3,2,3,1,0,'{}')`,[quote,product,price]);
   const q=await one('select subtotal,tax_total,total from quotes where id=$1',[quote]);
   assert.deepEqual(Object.values(q).map(Number),[600000,114000,714000]);
   await assert.rejects(db.query('update quotes set subtotal=1 where id=$1',[quote]),e=>e.code==='23514');
 });
 await t.test('issued quotes retain prices and cannot be altered',async()=>{
   await db.query("update quotes set status='issued',issued_at=now() where id=$1",[quote]);
   await db.query("update product_price_versions set state='retired' where id=$1",[price]);
   assert.equal(Number((await one('select unit_price from quote_lines where quote_id=$1',[quote])).unit_price),100000);
   await assert.rejects(db.query('update quote_lines set quantity=3 where quote_id=$1',[quote]),e=>e.code==='23514');
   await assert.rejects(db.query("update quotes set status='draft' where id=$1",[quote]),e=>e.code==='23514');
 });
 await t.test('client cannot read staff quotes or calendar',async()=>{
   const client=await id(`insert into auth.users(id,email) values(gen_random_uuid(),'client@example.invalid') returning id`);
   await db.query("update profiles set user_kind='client',is_active=true,activated_at=now() where id=$1",[client]);
   await db.query('insert into customer_memberships(customer_account_id,user_id) values($1,$2)',[account,client]);
   for(const table of ['quotes','quote_lines','availability_entries','availability_events','products'])
     assert.equal((await asUser(client,`select * from public.${table}`)).length,0);
 });
});
