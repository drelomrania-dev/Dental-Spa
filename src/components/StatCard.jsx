import React from 'react'

export default function StatCard({ icon:Icon, label, value, foot, tone='violet' }){
  return (
    <div className={`stat-card tone-${tone}`}>
      <div className="stat-icon"><Icon size={22}/></div>
      <div className="stat-label">{label}</div>
      <div className="stat-value">{value}</div>
      {foot && <div className="stat-foot">{foot}</div>}
      <div className="mini-wave" aria-hidden="true"><span></span><span></span><span></span><span></span><span></span></div>
    </div>
  )
}
