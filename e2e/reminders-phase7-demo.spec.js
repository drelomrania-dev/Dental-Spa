import { test, expect } from '@playwright/test'

test('uses explicit consent and approved templates for fake reminders, then cancels on withdrawal',async({page})=>{
  test.skip(Boolean(process.env.E2E_BASE_URL||process.env.E2E_SUPABASE_URL),'Synthetic local-data check only')
  await page.goto('/')
  await page.evaluate(()=>{
    const start=new Date(Date.now()+12*3600000)
    const date=`${start.getFullYear()}-${String(start.getMonth()+1).padStart(2,'0')}-${String(start.getDate()).padStart(2,'0')}`
    const time=`${String(start.getHours()).padStart(2,'0')}:${String(start.getMinutes()).padStart(2,'0')}`
    localStorage.setItem('dentalflow:appointments',JSON.stringify([{id:'phase7-demo-appointment',patientId:'p1',doctorId:'d1',date,time,duration:30,reason:'PRIVATE CLINICAL NOTE',status:'Confirmé'}]))
    const due=new Date(Date.now()+24*3600000)
    const dueDate=`${due.getFullYear()}-${String(due.getMonth()+1).padStart(2,'0')}-${String(due.getDate()).padStart(2,'0')}`
    localStorage.setItem('dentalflow:financeAccounts',JSON.stringify([{id:'phase7-demo-account',patientId:'p1',treatmentId:'t1',total:100,paid:0,remaining:100,installments:[{id:'phase7-demo-installment',dueDate,remaining:100,status:'due'}]}]))
    localStorage.removeItem('dentalflow:reminders:v1')
  })
  await page.goto('/reminders')
  await expect(page.getByRole('heading',{name:'Rappels',exact:true})).toBeVisible()
  await page.getByRole('button',{name:'Préparer les rappels dus'}).click()
  await expect(page.getByText('0 rappel(s) mis en file')).toBeVisible()
  await page.getByLabel('Patient').selectOption('p1')
  await page.getByLabel('Preuve ou motif').fill('Accord synthétique signé')
  await page.getByRole('button',{name:'Enregistrer la préférence'}).click()
  await page.locator('.reminder-template-grid .reminder-editor').nth(0).getByRole('button',{name:'Approuver'}).click()
  await page.locator('.reminder-template-grid .reminder-editor').nth(2).getByRole('button',{name:'Approuver'}).click()
  await page.getByRole('button',{name:'Préparer les rappels dus'}).click()
  await expect(page.getByText('2 rappel(s) mis en file')).toBeVisible()
  await expect(page.locator('tbody tr')).toHaveCount(2)
  await expect(page.locator('tbody')).not.toContainText('PRIVATE CLINICAL NOTE')
  await page.locator('tbody tr').first().getByRole('button',{name:'Simuler un échec'}).click()
  await expect(page.locator('tbody').getByText('À réessayer')).toBeVisible()
  await page.getByLabel('Préférence').selectOption('no')
  await page.getByLabel('Preuve ou motif').fill('Retrait synthétique')
  await page.getByRole('button',{name:'Enregistrer la préférence'}).click()
  await expect(page.locator('tbody').getByText('Annulé')).toHaveCount(2)
  await expect(page.locator('.resource-row').filter({hasText:'Échec simulé'})).toBeVisible()
})
