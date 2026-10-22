import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { createClient } from '@supabase/supabase-js'

const fixture = JSON.parse(await readFile('.local-fixtures.json', 'utf8'))
const { supabaseUrl: url, anonKey, accounts, clinics } = fixture
const target = new URL(url)
assert.ok(['127.0.0.1', 'localhost'].includes(target.hostname) && target.port === '54321', 'Only the local Supabase API is allowed')
assert.ok(anonKey && accounts?.admin && accounts?.assistant && accounts?.practitioner && accounts?.otherAdmin)

async function signedIn(account) {
  const client = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } })
  const { data, error } = await client.auth.signInWithPassword(account)
  assert.ifError(error)
  assert.equal(data.user.id, account.id)
  return { client, accessToken: data.session.access_token }
}

async function rpc(client, name) {
  const { data, error } = await client.rpc(name)
  assert.ifError(error)
  return data
}

const sessions = {}
for (const [name, account] of Object.entries(accounts)) {
  sessions[name] = await signedIn(account)
  const context = await rpc(sessions[name].client, 'current_access_context')
  assert.equal(context.id, account.id, `${name} Auth identity did not match its staff profile`)
  assert.equal(context.clinicId, clinics[name === 'otherAdmin' ? 'B' : 'A'], `${name} is in the wrong clinic`)
}

const aPatients = await rpc(sessions.admin.client, 'patients_snapshot')
const assistantPatients = await rpc(sessions.assistant.client, 'patients_snapshot')
const bPatients = await rpc(sessions.otherAdmin.client, 'patients_snapshot')
const practitionerPatients = await rpc(sessions.practitioner.client, 'patients_snapshot')
for (const rows of [aPatients, assistantPatients]) {
  assert.ok(rows.some(row => row.id === 'local-patient-a'), 'Clinic A fixture patient is missing')
  assert.ok(rows.every(row => row.id !== 'local-patient-b'), 'Clinic B patient leaked to clinic A')
}
assert.ok(bPatients.some(row => row.id === 'local-patient-b'), 'Clinic B fixture patient is missing')
assert.ok(bPatients.every(row => row.id !== 'local-patient-a'), 'Clinic A patient leaked to clinic B')
assert.ok(practitionerPatients.every(row => row.id !== 'local-patient-b'), 'Clinic B patient leaked to practitioner')

const serviceKey = process.env.LOCAL_SUPABASE_SERVICE_ROLE_KEY
assert.ok(serviceKey, 'Local service key is required in process memory for the Storage check')
const serviceClient = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } })
const { data: buckets, error: storageError } = await serviceClient.storage.listBuckets()
assert.ifError(storageError)
assert.ok(buckets.some(bucket => bucket.id === 'lead-media' && !bucket.public), 'Private local Storage bucket is missing')

const edgeResponse = await fetch(`${url}/functions/v1/staff-invite-link`, {
  method: 'POST',
  headers: {
    apikey: anonKey,
    authorization: `Bearer ${sessions.admin.accessToken}`,
    origin: 'http://127.0.0.1:4173',
    'content-type': 'application/json'
  },
  body: JSON.stringify({ token: 'invalid', redirectTo: 'http://127.0.0.1:4173/join/invalid' })
})
assert.equal(edgeResponse.status, 400, `Local staff-invite-link did not validate an invalid token (HTTP ${edgeResponse.status})`)
assert.equal(edgeResponse.headers.get('access-control-allow-origin'), 'http://127.0.0.1:4173')

console.log('Local Auth, two-clinic patient isolation, private Storage, and staff Edge Function checks passed.')
