import {test,expect,hasTwoAccountConfig,missingTwoAccountConfigReason} from './fixtures.js'

test.describe('reporting permissions on local Auth',()=>{
  test.skip(!hasTwoAccountConfig,missingTwoAccountConfigReason)
  test('admin can request audited detail export; assistant cannot access finance reports or history',async({adminPage,assistantPage})=>{
    await adminPage.goto('/')
    await expect(adminPage.getByRole('heading',{name:'Encaissements opérationnels'})).toBeVisible()
    await expect(adminPage.getByRole('heading',{name:'Conversion CRM'})).toBeVisible()
    await adminPage.goto('/payment-history')
    const download=adminPage.waitForEvent('download')
    await adminPage.getByRole('button',{name:'Export CSV'}).click()
    expect((await download).suggestedFilename()).toBe('historique-paiements.csv')
    await assistantPage.goto('/reports')
    await expect(assistantPage.getByRole('heading',{name:'Accès refusé'})).toBeVisible()
    await assistantPage.goto('/payment-history')
    await expect(assistantPage.getByRole('heading',{name:'Accès refusé'})).toBeVisible()
  })
})
