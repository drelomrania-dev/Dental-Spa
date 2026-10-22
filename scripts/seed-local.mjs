import { randomBytes } from 'node:crypto'
import { writeFile } from 'node:fs/promises'
import { createClient } from '@supabase/supabase-js'

const url = process.env.LOCAL_SUPABASE_URL
const anonKey = process.env.LOCAL_SUPABASE_ANON_KEY
const serviceKey = process.env.LOCAL_SUPABASE_SERVICE_ROLE_KEY
const target = new URL(url || 'https://invalid.example')
if (!['127.0.0.1', 'localhost'].includes(target.hostname) || target.port !== '54321' || !anonKey || !serviceKey) {
  throw new Error('Refusing to seed anything except the local Supabase API on port 54321')
}

const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } })
const password = randomBytes(18).toString('base64url') + 'A1!'
const accounts = [
  { key: 'admin', email: 'local-admin@dentalspa.invalid', name: 'Local Administrator', role: 'administrator', clinic: 'A' },
  { key: 'assistant', email: 'local-assistant@dentalspa.invalid', name: 'Local Assistant', role: 'assistant', clinic: 'A' },
  { key: 'practitioner', email: 'local-practitioner@dentalspa.invalid', name: 'Local Practitioner', role: 'practitioner', clinic: 'A' },
  { key: 'otherAdmin', email: 'local-other-admin@dentalspa.invalid', name: 'Other Clinic Administrator', role: 'administrator', clinic: 'B' }
]

function value(result, label) {
  if (result.error) throw new Error(`${label}: ${result.error.message}`)
  return result.data
}

async function ensureUser(account) {
  const users = value(await admin.auth.admin.listUsers({ page: 1, perPage: 100 }), 'List local Auth users').users
  const existing = users.find(user => user.email === account.email)
  if (existing) {
    value(await admin.auth.admin.updateUserById(existing.id, { password, email_confirm: true }), 'Update local Auth user')
    return existing.id
  }
  return value(await admin.auth.admin.createUser({
    email: account.email, password, email_confirm: true, user_metadata: { full_name: account.name }
  }), 'Create local Auth user').user.id
}

async function ensureClinic(name) {
  const existing = value(await admin.from('clinics').select('id').eq('name', name).limit(1), 'Find local clinic')[0]
  if (existing) return existing.id
  return value(await admin.from('clinics').insert({ name, currency: 'MAD', timezone: 'Africa/Casablanca', address: 'LOCAL TEST ONLY' }).select('id').single(), 'Create local clinic').id
}

async function upsert(table, record, conflict) {
  value(await admin.from(table).upsert(record, { onConflict: conflict }), `Upsert ${table}`)
}

const clinics = {
  A: await ensureClinic('LOCAL TEST Clinic A'),
  B: await ensureClinic('LOCAL TEST Clinic B')
}

for (const account of accounts) {
  account.id = await ensureUser(account)
  await upsert('staff_profiles', {
    id: account.id, clinic_id: clinics[account.clinic], display_name: account.name, role: account.role, active: true
  }, 'id')
}

const permissionCheck = value(await admin.from('role_permissions').select('permission').eq('clinic_id', clinics.A).eq('role', 'assistant').eq('permission', 'appointments.view'), 'Check local permissions')
if (!permissionCheck.length) throw new Error('New-clinic role permissions are absent; reset the local database and apply migration 029')

await upsert('patients', {
  clinic_id: clinics.A, app_id: 'local-patient-a', first_name: 'Test', last_name: 'Patient A',
  phone: '+212600000001', email: 'local-patient-a@example.invalid', status: 'Actif'
}, 'clinic_id,app_id')
await upsert('patients', {
  clinic_id: clinics.B, app_id: 'local-patient-b', first_name: 'Test', last_name: 'Patient B',
  phone: '+212600000002', email: 'local-patient-b@example.invalid', status: 'Actif'
}, 'clinic_id,app_id')

await upsert('practitioners', {
  clinic_id: clinics.A, app_id: 'local-doctor', staff_id: accounts[2].id,
  name: 'Dr. Local Test', specialty: 'General dentistry', active: true
}, 'clinic_id,app_id')
await upsert('services', {
  clinic_id: clinics.A, app_id: 'local-consultation', name: 'Consultation', category: 'Diagnostic',
  standard_price: 350, duration_minutes: 30, active: true, booking_eligible: true
}, 'clinic_id,app_id')

for (const [collection, id, data] of [
  ['doctors', 'local-doctor', { id: 'local-doctor', name: 'Dr. Local Test', active: true }],
  ['treatments', 'local-consultation', { id: 'local-consultation', name: 'Consultation', price: 350, duration: 30, active: true, bookingEligible: true }],
  ['bookingLinks', 'local-booking', { id: 'local-booking', slug: 'local-consultation', title: 'Local consultation', treatmentId: 'local-consultation', doctorId: 'local-doctor', roomId: 'chair-1', duration: 30, published: true, confirmationPolicy: 'auto' }]
]) {
  await upsert('app_records', { clinic_id: clinics.A, collection, id, data }, 'clinic_id,collection,id')
}

const fixture = {
  notice: 'Synthetic local accounts only. Delete this file or reset the local database after testing.',
  baseUrl: 'http://127.0.0.1:4173', supabaseUrl: url, anonKey,
  accounts: Object.fromEntries(accounts.map(account => [account.key, { email: account.email, password, id: account.id }])),
  clinics
}
await writeFile('.local-fixtures.json', JSON.stringify(fixture, null, 2) + '\n', { mode: 0o600 })
console.log('Local synthetic fixtures are ready in ignored .local-fixtures.json')
