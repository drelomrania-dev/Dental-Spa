const PAGE_WIDTH=595.28
const PAGE_HEIGHT=841.89

function binaryBytes(value){const bytes=new Uint8Array(value.length);for(let i=0;i<value.length;i+=1)bytes[i]=value.charCodeAt(i)&255;return bytes}
function cleanText(value,max=64){
  const normalized=String(value??'').replace(/[–—‑]/g,'-').replace(/[’‘]/g,"'").replace(/\s+/g,' ').trim()
  const latin=Array.from(normalized).map(char=>char.charCodeAt(0)<=255?char:'?').join('')
  return latin.length>max?`${latin.slice(0,Math.max(0,max-3))}...`:latin
}
function pdfString(value,max){return `(${cleanText(value,max).replace(/\\/g,'\\\\').replace(/\(/g,'\\(').replace(/\)/g,'\\)')})`}
function money(value){return `${Number(value||0).toFixed(2).replace('.',',')} MAD`}
function dateLabel(value){
  const parts=String(value||'').slice(0,10).split('-')
  return parts.length===3?`${parts[2]}/${parts[1]}/${parts[0]}`:cleanText(value||'')
}

export function buildPaymentReceiptPdfBytes({receipt,patientName,treatmentName,clinic={}}){
  const isCorrection=receipt?.kind==='refund'||Number(receipt?.paid||0)<0
  const title=isCorrection?'Avoir de paiement':'Reçu de paiement'
  const rows=[
    ['Patient',patientName||'Patient'],['Soin',treatmentName||'Soin'],['Montant reçu',money(Math.abs(Number(receipt?.paid||0)))],
    ['Mode de paiement',receipt?.method||'Non précisé'],['Solde après opération',money(receipt?.remaining||0)]
  ]
  const text=(x,y,size,font,value,color='0.15 0.17 0.22')=>`${color} rg BT /${font} ${size} Tf 1 0 0 1 ${x} ${y} Tm ${pdfString(value)} Tj ET\n`
  let content='q\n0.459 0.341 0.961 rg\n0 720 595.28 121.89 re f\nQ\n'
  content+=text(62,780,21,'F2',cleanText(clinic?.name||'Dental Spa',34),'1 1 1')
  content+=text(62,756,10,'F1',title,'1 1 1')
  content+=text(62,670,16,'F2',isCorrection?'Correction enregistrée':'Paiement enregistré')
  content+=text(62,646,9,'F1',`Référence ${receipt?.reference||'—'}  |  ${dateLabel(receipt?.date)}`,'0.45 0.49 0.57')
  content+='q\n0.969 0.961 1 rg\n50 410 495 190 re f\nQ\n'
  let y=566
  rows.forEach(([label,value])=>{content+=text(68,y,9,'F1',label,'0.45 0.49 0.57');content+=text(345,y,9,'F2',value);y-=34})
  content+='0.89 0.88 0.96 RG 0.7 w 50 94 m 545 94 l S\n'
  content+=text(50,68,8,'F1','Document de paiement - ne remplace pas une facture fiscale.','0.45 0.49 0.57')
  content+=text(50,50,8,'F1',`${clinic?.name||'Dental Spa'} - ${clinic?.address||'Casablanca'} - ${clinic?.timezone||'Africa/Casablanca'}`,'0.45 0.49 0.57')

  const objects=[null,
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${PAGE_WIDTH} ${PAGE_HEIGHT}] /Resources << /Font << /F1 4 0 R /F2 5 0 R >> >> /Contents 6 0 R >>`,
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>',
    `<< /Length ${content.length} >>\nstream\n${content}endstream`
  ]
  let pdf='%PDF-1.4\n%âãÏÓ\n';const offsets=[0]
  for(let i=1;i<objects.length;i+=1){offsets[i]=pdf.length;pdf+=`${i} 0 obj\n${objects[i]}\nendobj\n`}
  const xref=pdf.length
  pdf+=`xref\n0 ${objects.length}\n0000000000 65535 f \n`
  for(let i=1;i<objects.length;i+=1)pdf+=`${String(offsets[i]).padStart(10,'0')} 00000 n \n`
  pdf+=`trailer\n<< /Size ${objects.length} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`
  return binaryBytes(pdf)
}

export function downloadPaymentReceiptPdf(details){
  const bytes=buildPaymentReceiptPdfBytes(details)
  const url=URL.createObjectURL(new Blob([bytes],{type:'application/pdf'}))
  const anchor=document.createElement('a');anchor.href=url;anchor.download=`recu-${cleanText(details.receipt?.reference||'paiement',40).replace(/[^a-zA-Z0-9_-]+/g,'-')}.pdf`;anchor.click()
  window.setTimeout(()=>URL.revokeObjectURL(url),1000)
}
