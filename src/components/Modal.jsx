import React, { useEffect, useRef } from 'react'
import { X } from 'lucide-react'

export default function Modal({ open, title, subtitle, onClose, children, width='680px' }){
  const dialogRef = useRef(null)
  const onCloseRef = useRef(onClose)
  onCloseRef.current = onClose
  useEffect(() => {
    if (!open) return
    const previousFocus = document.activeElement
    const dialog = dialogRef.current
    const focusable = () => [...dialog.querySelectorAll('a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])')]
      .filter(element => element.getClientRects().length > 0)
    ;(dialog.querySelector('input:not([disabled]), select:not([disabled]), textarea:not([disabled])') || focusable()[0] || dialog).focus()
    function onKeyDown(event) {
      if (event.key === 'Escape') { event.preventDefault(); onCloseRef.current(); return }
      if (event.key !== 'Tab') return
      const items = focusable()
      if (!items.length) { event.preventDefault(); dialog.focus(); return }
      const first = items[0], last = items[items.length - 1]
      if (event.shiftKey && (document.activeElement === first || !dialog.contains(document.activeElement))) { event.preventDefault(); last.focus() }
      else if (!event.shiftKey && (document.activeElement === last || !dialog.contains(document.activeElement))) { event.preventDefault(); first.focus() }
    }
    document.addEventListener('keydown', onKeyDown)
    return () => { document.removeEventListener('keydown', onKeyDown); previousFocus?.focus?.() }
  }, [open])
  if(!open) return null
  return (
    <div className="modal-backdrop" onMouseDown={e => e.target === e.currentTarget && onClose()}>
      <div ref={dialogRef} className="modal-card" role="dialog" aria-modal="true" aria-label={title} tabIndex={-1} style={{maxWidth:width}}>
        <div className="modal-head">
          <div>
            <h3>{title}</h3>
            {subtitle && <p>{subtitle}</p>}
          </div>
          <button className="icon-btn" aria-label="Fermer" onClick={onClose}><X size={18}/></button>
        </div>
        {children}
      </div>
    </div>
  )
}
