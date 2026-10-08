import React from 'react'
import { X } from 'lucide-react'

export default function Modal({ open, title, subtitle, onClose, children, width='680px' }){
  if(!open) return null
  return (
    <div className="modal-backdrop" onMouseDown={e => e.target === e.currentTarget && onClose()}>
      <div className="modal-card" style={{maxWidth:width}}>
        <div className="modal-head">
          <div>
            <h3>{title}</h3>
            {subtitle && <p>{subtitle}</p>}
          </div>
          <button className="icon-btn" onClick={onClose}><X size={18}/></button>
        </div>
        {children}
      </div>
    </div>
  )
}
