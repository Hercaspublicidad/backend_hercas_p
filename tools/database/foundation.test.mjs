import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';

const migration = await readFile(new URL('../../supabase/migrations/20260917223649_platform_identity_foundation.sql', import.meta.url), 'utf8');
const hardening = await readFile(new URL('../../supabase/migrations/20260917223752_identity_advisor_hardening.sql', import.meta.url), 'utf8');
const bootstrap = await readFile(new URL('../../supabase/admin/prepare_initial_admin.sql', import.meta.url), 'utf8');
const uid = n => `00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;

test('PostgreSQL foundation and RLS isolation', async t => {
  const db = new PGlite();
  t.after(() => db.close());
  // Minimal Supabase Auth contract. Real Auth gateway/email are not simulated here.
  await db.exec(`
    create role anon nologin;
    create role authenticated nologin;
    create schema auth;
    create table auth.users (id uuid primary key, email text, email_confirmed_at timestamptz, invited_at timestamptz);
    create function auth.uid() returns uuid language sql stable as $$
      select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid;
    $$;
    grant usage on schema auth to authenticated,anon;
    grant execute on function auth.uid() to authenticated,anon;
  `);
  await db.exec(migration);
  await db.exec(hardening);

  async function asUser(user, sql, params=[]) {
    await db.exec('begin; set local role authenticated');
    try {
      await db.query("select set_config('request.jwt.claim.sub',$1,true)",[user ?? '']);
      const result = await db.query(sql, params);
      await db.exec('commit');
      return result.rows;
    } catch (error) { await db.exec('rollback'); throw error; }
  }
  async function addUser(n, email, confirmed=true, invited=true) {
    await db.query('insert into auth.users values($1,$2,$3,$4)', [uid(n),email,confirmed?'2026-01-01T00:00:00Z':null,invited?'2026-01-01T00:00:00Z':null]);
  }
  async function invitation(email, kind, role, account=null) {
    return (await db.query(`insert into public.invitations(email,user_kind,role,scope,customer_account_id)
      values($1,$2,$3,$4,$5) returning id`,[email,kind,role,kind==='employee'?'staff':'client',account])).rows[0].id;
  }
  const accept = (n, id) => asUser(uid(n),'select public.accept_invitation($1)',[id]);
  const count = rows => Number(rows[0].count);

  await t.test('all foundation tables have RLS and anonymous has no grants', async () => {
    const tables = (await db.query("select relname,relrowsecurity from pg_class join pg_namespace n on n.oid=relnamespace where n.nspname='public' and relkind='r'")).rows;
    assert.equal(tables.length,9);
    assert.ok(tables.every(row=>row.relrowsecurity));
    for (const row of tables) {
      const privileges = (await db.query("select has_table_privilege('anon',$1,'select') as allowed",['public.'+row.relname])).rows;
      assert.equal(privileges[0].allowed,false);
    }
    assert.equal((await db.query("select has_function_privilege('anon','public.accept_invitation(uuid)','execute') as allowed")).rows[0].allowed,false);
    assert.equal((await db.query("select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef")).rows[0].count,0);
  });

  await addUser(1,'asesoria@hercas.net');
  await t.test('new Auth users are inactive, unprivileged and cannot activate themselves', async () => {
    const own = await asUser(uid(1),'select * from public.profiles');
    assert.equal(own.length,1);
    assert.equal(own[0].is_active,false);
    assert.equal(count(await asUser(uid(1),'select count(*) from public.user_roles')),0);
    await assert.rejects(asUser(uid(1),'update public.profiles set is_active=true'));
    await assert.rejects(asUser(uid(1),"insert into public.user_roles(user_id,role) values($1,'systems_admin')",[uid(1)]));
    await assert.rejects(asUser(uid(1),"insert into public.invitations(email,user_kind,role,scope) values('x@h.test','employee','systems_admin','staff')"));
  });

  await db.exec(bootstrap);
  await db.exec(bootstrap);
  const adminInvite = (await db.query("select id from public.invitations where email='asesoria@hercas.net'")).rows[0].id;
  await t.test('bootstrap is idempotent and grants nothing until verified acceptance',async () => {
    assert.equal(Number((await db.query('select count(*) from public.invitations')).rows[0].count),1);
    await assert.rejects(asUser(null,'select public.accept_invitation($1)',[adminInvite]));
    await accept(1,adminInvite);
    await accept(1,adminInvite);
    assert.equal(count(await asUser(uid(1),'select count(*) from public.user_roles')),1);
    assert.equal((await asUser(uid(1),"select private.has_permission('users.manage') as allowed"))[0].allowed,true);
    await assert.rejects(db.exec(bootstrap));
    await db.exec('rollback');
  });

  const accounts = (await db.query("insert into public.customer_accounts(name) values('Cliente A'),('Cliente B') returning id")).rows;
  for (const [n,email] of [[2,'a@client.test'],[3,'b@client.test'],[4,'a2@client.test']]) await addUser(n,email);
  await accept(2,await invitation('a@client.test','client','client_viewer',accounts[0].id));
  await accept(3,await invitation('b@client.test','client','client_viewer',accounts[1].id));
  await accept(4,await invitation('a2@client.test','client','client_viewer',accounts[0].id));

  await t.test('two companies are isolated; two members can access the same company',async () => {
    for (const [n,expected] of [[2,accounts[0].id],[3,accounts[1].id],[4,accounts[0].id]]) {
      const rows = await asUser(uid(n),'select id from public.customer_accounts');
      assert.deepEqual(rows,[{id:expected}]);
      assert.equal(count(await asUser(uid(n),'select count(*) from public.profiles')),1);
      assert.equal(count(await asUser(uid(n),'select count(*) from public.customer_memberships')),1);
      assert.equal(count(await asUser(uid(n),'select count(*) from public.invitations')),0);
      assert.equal(count(await asUser(uid(n),'select count(*) from public.audit_events')),0);
    }
    assert.equal(count(await asUser(uid(1),'select count(*) from public.customer_accounts')),2);
  });

  await t.test('client cannot self-assign membership or staff role',async () => {
    await assert.rejects(asUser(uid(2),'insert into public.customer_memberships(customer_account_id,user_id) values($1,$2)',[accounts[1].id,uid(2)]));
    await assert.rejects(asUser(uid(2),"update public.role_permissions set role='client_viewer'"));
    await assert.rejects(invitation('evil@test.dev','client','systems_admin',accounts[0].id));
  });

  await t.test('wrong email, unverified account and non-invited identity cannot claim',async () => {
    const target = await invitation('target@test.dev','employee','sales');
    await assert.rejects(accept(2,target));
    await addUser(5,'target@test.dev',false,true);
    await assert.rejects(accept(5,target));
    await db.query('update auth.users set email_confirmed_at=now(),invited_at=null where id=$1',[uid(5)]);
    await assert.rejects(accept(5,target));
  });

  await t.test('expired and revoked invitations are rejected',async () => {
    await addUser(6,'expired@test.dev');
    const expired = await invitation('expired@test.dev','employee','sales');
    await db.query("update public.invitations set created_at=now()-interval '2 days',expires_at=now()-interval '1 day' where id=$1",[expired]);
    await assert.rejects(accept(6,expired));
    const revoked = await invitation('expired@test.dev','employee','sales');
    await db.query('update public.invitations set revoked_at=now() where id=$1',[revoked]);
    await assert.rejects(accept(6,revoked));
  });

  await t.test('deactivation and membership revocation take effect without JWT refresh',async () => {
    await db.query('update public.customer_memberships set revoked_at=now() where user_id=$1',[uid(4)]);
    assert.equal(count(await asUser(uid(4),'select count(*) from public.customer_accounts')),0);
    await db.query('update public.customer_accounts set is_active=false where id=$1',[accounts[0].id]);
    assert.equal(count(await asUser(uid(2),'select count(*) from public.customer_accounts')),0);
    await db.query('update public.customer_accounts set is_active=true where id=$1',[accounts[0].id]);
    await db.query('update public.profiles set is_active=false where id=$1',[uid(2)]);
    assert.equal(count(await asUser(uid(2),'select count(*) from public.customer_accounts')),0);
    await assert.rejects(accept(2,await invitation('a@client.test','client','client_viewer',accounts[0].id)));
  });

  await t.test('pricing and availability roles are separate',async () => {
    await addUser(7,'pricing@test.dev'); await addUser(8,'availability@test.dev');
    await accept(7,await invitation('pricing@test.dev','employee','pricing_manager'));
    await accept(8,await invitation('availability@test.dev','employee','availability_manager'));
    for (const [n,yes,no] of [[7,'cotizador.pricing.manage','cotizador.availability.manage'],[8,'cotizador.availability.manage','cotizador.pricing.manage']]) {
      assert.equal((await asUser(uid(n),'select private.has_permission($1) as allowed',[yes]))[0].allowed,true);
      assert.equal((await asUser(uid(n),'select private.has_permission($1) as allowed',[no]))[0].allowed,false);
    }
    await db.query('update public.user_roles set revoked_at=now() where user_id=$1',[uid(7)]);
    assert.equal((await asUser(uid(7),"select private.has_permission('cotizador.pricing.manage') as allowed"))[0].allowed,false);
  });

  await t.test('audit is generated and not writable by authenticated admin',async () => {
    assert.ok(count(await asUser(uid(1),'select count(*) from public.audit_events'))>10);
    await assert.rejects(asUser(uid(1),'delete from public.audit_events'));
    await assert.rejects(asUser(uid(1),"insert into public.audit_events(action,entity,entity_id) values('INSERT','fake','fake')"));
  });

  await t.test('membership invitation cannot convert a client into an employee',async () => {
    const roleChange = await invitation('b@client.test','employee','systems_admin');
    await assert.rejects(accept(3,roleChange));
    assert.equal((await asUser(uid(3),"select private.has_permission('users.manage') as allowed"))[0].allowed,false);
  });

  await t.test('same client may belong to multiple companies only by invitation',async () => {
    await accept(3,await invitation('b@client.test','client','client_viewer',accounts[0].id));
    assert.equal(count(await asUser(uid(3),'select count(*) from public.customer_accounts')),2);
  });

  await t.test('replaying an accepted invitation does not restore a revoked grant',async () => {
    await addUser(9,'replay@test.dev');
    const id = await invitation('replay@test.dev','employee','sales');
    await accept(9,id);
    await db.query('update public.user_roles set revoked_at=now() where user_id=$1',[uid(9)]);
    await accept(9,id);
    assert.equal((await asUser(uid(9),"select private.has_permission('cotizador.calculate') as allowed"))[0].allowed,false);
  });

  await t.test('inactive customer cannot receive a new membership',async () => {
    await addUser(10,'inactive-customer@test.dev');
    const id = await invitation('inactive-customer@test.dev','client','client_viewer',accounts[1].id);
    await db.query('update public.customer_accounts set is_active=false where id=$1',[accounts[1].id]);
    await assert.rejects(accept(10,id));
    assert.equal((await db.query('select is_active from public.profiles where id=$1',[uid(10)])).rows[0].is_active,false);
  });

  await t.test('elevated triggers cannot be executed by API roles',async () => {
    for (const name of ['private.on_auth_user_created()','private.audit_identity_change()']) {
      assert.equal((await db.query("select has_function_privilege('authenticated',$1,'execute') as allowed",[name])).rows[0].allowed,false);
    }
  });
});
