import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';
test('Administration enforces authorization and last-admin invariant', async t => {
 const db=new PGlite(); t.after(()=>db.close());
 await db.exec(`create role anon; create role authenticated; create schema auth;
 create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz,invited_at timestamptz);
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 grant usage on schema auth to authenticated; grant execute on function auth.uid() to authenticated;`);
 const dir=new URL('../../supabase/migrations/',import.meta.url);
 for(const file of (await readdir(dir)).filter(f=>/identity|auth_admin|role_permission/.test(f)).sort()) await db.exec(await readFile(new URL(file,dir),'utf8'));
 async function user(role,kind='employee') {
   const id=(await db.query("insert into auth.users values(gen_random_uuid(),'person@example.test',now(),now()) returning id")).rows[0].id;
   await db.query('update public.profiles set is_active=true,user_kind=$2,activated_at=now() where id=$1',[id,kind]);
   if(role) await db.query('insert into public.user_roles(user_id,role) values($1,$2)',[id,role]); return id;
 }
 const admin=await user('systems_admin'), sales=await user('sales'), client=await user(null,'client');
 async function as(id,sql,args=[]) {
   await db.exec('begin; set local role authenticated');
   try {await db.query("select set_config('request.jwt.claim.sub',$1,true)",[id]); const result=await db.query(sql,args);await db.exec('commit');return result.rows;}
   catch(error){await db.exec('rollback');throw error;}
 }
 const update=(actor,target,roles,active=true)=>as(actor,'select public.admin_update_access($1,$2,$3)',[target,roles,active]);
 await t.test('ordinary staff cannot self-promote or invite',async()=>{
   await assert.rejects(update(sales,sales,['systems_admin']),/Forbidden/);
   await assert.rejects(as(sales,"select public.admin_create_invitation('x@example.test','systems_admin')"),/Forbidden/);
 });
 await t.test('directory exposes emails only to administrators and validates pagination',async()=>{
   await assert.rejects(as(sales,'select * from public.admin_user_directory()'),/Forbidden/);
   assert.equal((await as(admin,'select * from public.admin_user_directory()')).length,3);
   await assert.rejects(as(admin,'select * from public.admin_user_directory(-1)'),/Invalid page/);
 });
 await t.test('last administrator cannot be demoted or disabled',async()=>{
   await assert.rejects(update(admin,admin,['sales']),/Last administrator/);
   await assert.rejects(update(admin,admin,['systems_admin'],false),/Last administrator/);
 });
 await t.test('client cannot receive staff roles and invalid role is rejected',async()=>{
   await assert.rejects(update(admin,client,['systems_admin']),/scoped/);
   await assert.rejects(update(admin,sales,['unknown']),/Invalid role/);
 });
 await t.test('role replacement revokes previous grant and suspended identity loses permission',async()=>{
   await update(admin,sales,['pricing_manager']);
   assert.equal((await db.query('select role from public.user_roles where user_id=$1 and revoked_at is null',[sales])).rows[0].role,'pricing_manager');
   await update(admin,sales,['pricing_manager'],false);
   assert.equal((await as(sales,"select private.has_permission('cotizador.pricing.manage') allowed"))[0].allowed,false);
 });
 await t.test('admin creates and revokes invitation without granting immediate access',async()=>{
   const id=(await as(admin,"select public.admin_create_invitation('new@example.test','sales') id"))[0].id;
   await as(admin,'select public.admin_revoke_invitation($1)',[id]);
   assert.ok((await db.query('select revoked_at from public.invitations where id=$1',[id])).rows[0].revoked_at);
 });
 await t.test('anonymous cannot invoke administrative mutations',async()=>{
   assert.equal((await db.query("select has_function_privilege('anon','public.admin_update_access(uuid,text[],boolean)','execute') allowed")).rows[0].allowed,false);
 });
 await t.test('only an administrator can change modules assigned to a role',async()=>{
   const updatePermissions=(actor,role,permissions)=>as(actor,'select public.admin_update_role_permissions($1,$2)',[role,permissions]);
   await assert.rejects(updatePermissions(sales,'sales',['audit.read']),/Forbidden/);
   await updatePermissions(admin,'sales',['cotizador.read','reports.read_own']);
   assert.deepEqual(
     (await db.query("select permission from public.role_permissions where role='sales' order by permission")).rows.map(row=>row.permission),
     ['cotizador.read','reports.read_own'],
   );
   await assert.rejects(updatePermissions(admin,'systems_admin',['cotizador.read']),/must retain user management/);
   assert.ok((await db.query("select 1 from public.audit_events where entity='role_permissions' and entity_id='sales:reports.read_own' limit 1")).rows.length);
 });
});
