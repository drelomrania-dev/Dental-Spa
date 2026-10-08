export const money = value => `${Number(value || 0).toLocaleString('fr-MA', {maximumFractionDigits:2})} DH`
export const todayISO = () => {
  const now = new Date()
  return `${now.getFullYear()}-${String(now.getMonth()+1).padStart(2,'0')}-${String(now.getDate()).padStart(2,'0')}`
}
export const prettyDate = value => value ? new Date(value + 'T12:00:00').toLocaleDateString('fr-FR', {day:'2-digit',month:'short',year:'numeric'}) : '—'
export const statusClass = s => `pill pill-${String(s||'').toLowerCase().replaceAll(' ','-').replaceAll('é','e').replaceAll('è','e')}`
