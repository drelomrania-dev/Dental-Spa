import { test, expect } from '@playwright/test'
import { createClient } from '@supabase/supabase-js'

const localUrl = process.env.E2E_SUPABASE_URL || ''
const localTarget = /^https?:\/\/(127\.0\.0\.1|localhost)(:\d+)?\/?$/i.test(localUrl) && Boolean(process.env.E2E_SUPABASE_ANON_KEY)
const localBookingSlug = 'local-consultation'

test('two anonymous clients cannot take the same practitioner and chair slot', async () => {
  test.skip(!localTarget, 'Requires the synthetic local Supabase target')
  const first = createClient(localUrl, process.env.E2E_SUPABASE_ANON_KEY, { auth: { persistSession: false } })
  const second = createClient(localUrl, process.env.E2E_SUPABASE_ANON_KEY, { auth: { persistSession: false } })
  const { data: page, error: pageError } = await first.rpc('public_booking_page', { p_slug: localBookingSlug })
  expect(pageError).toBeNull()
  const serviceId = page?.services?.[0]?.id
  expect(serviceId).toBeTruthy()
  let chosen = null
  for (let offset = 10; offset <= 70; offset++) {
    const candidate = new Date(Date.now() + offset * 86400000).toISOString().slice(0, 10)
    const { data: slots, error } = await first.rpc('public_available_slots_for_service', { p_slug: localBookingSlug, p_date: candidate, p_service_app_id: serviceId })
    expect(error).toBeNull()
    if (slots?.length) { chosen = { date: candidate, time: slots[0] }; break }
  }
  expect(chosen, 'A local fixture slot must be available').toBeTruthy()
  const nonce = String(Date.now()).slice(-8)
  const details = index => ({
    p_slug: localBookingSlug, p_service_app_id: serviceId, p_reason: 'Test simultané synthétique',
    p_date: chosen.date, p_time: chosen.time, p_first_name: 'Race', p_last_name: `Client${index}`,
    p_phone: `060${nonce}${index}`, p_email: `race-${nonce}-${index}@example.invalid`
  })
  let successes = []
  try {
    const results = await Promise.all([first.rpc('public_create_booking_v2', details(1)), second.rpc('public_create_booking_v2', details(2))])
    successes = results.filter(result => !result.error)
    expect(successes).toHaveLength(1)
    expect(results.filter(result => result.error)).toHaveLength(1)
    expect(results.find(result => result.error).error.message).toContain('Slot unavailable')
  } finally {
    for (const result of successes) {
      if (result.data?.manageToken) await first.rpc('public_cancel_booking', { p_token: result.data.manageToken, p_reason: 'Fin du test synthétique' })
    }
  }
})
