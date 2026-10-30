const copy = require('./customer-receipt.json');
function receiptDocument(n, {locale, labels, pickupAt, issuedAt, escapeHtml}) {
  const t=copy[locale];
  const raw=n.booking_total_amount;
  const amount=raw==null || String(raw).trim()==='' ? null : Number(raw);
  const validAmount=Number.isFinite(amount) && amount>=0 && n.booking_currency==='THB';
  const paid=n.booking_payment_status==='PAID' && validAmount
    && ['SETTLEMENT_PENDING','COMPLETED'].includes(n.booking_status);
  let metadata=n.booking_metadata;
  if(typeof metadata==='string'){try{metadata=JSON.parse(metadata)}catch{metadata={}}}
  const method=metadata?.customerPayment?.method || n.booking_payment_method;
  const paymentLabel=t.methods[String(method||'').trim().toUpperCase()] || t.unknown;
  const title=paid?t.receipt:t.statement;
  const number=String(n.booking_number||n.payload?.bookingNumber||'');
  const route=[n.origin_address,n.destination_address].filter(Boolean).join(' → ');
  const rows=[
    [labels.booking,number],
    ...(issuedAt?[[t.issued,issuedAt]]:[]),
    ...(pickupAt?[[labels.pickup,pickupAt]]:[]),
    ...(route?[[labels.route,route]]:[]),
    ...(labels.vehicles?.[n.booking_vehicle_type]?[[labels.vehicle,labels.vehicles[n.booking_vehicle_type]]]:[]),
    [t.status,paid?t.paid:t.unconfirmed],
    [t.method,paymentLabel],
    [paid?t.paidAmount:t.amount,validAmount?new Intl.NumberFormat(locale,{maximumFractionDigits:2}).format(amount)+' '+labels.currency:t.unknown],
  ];
  const lines=['T-Rider · '+title,...rows.map(([k,v])=>k+': '+v),paid?t.paidNote:t.pendingNote,t.note];
  const e=escapeHtml;
  const html='<section style="border:1px solid #d8e4e1;border-radius:12px;padding:24px;margin-bottom:24px"><div style="color:#006a60;font-size:24px;font-weight:bold">T-Rider</div><h2>'+e(title)+'</h2><table style="width:100%;border-collapse:collapse">'+rows.map(([k,v])=>'<tr><th style="text-align:left;vertical-align:top;padding:10px;border-bottom:1px solid #edf1ef">'+e(k)+'</th><td style="padding:10px;border-bottom:1px solid #edf1ef;overflow-wrap:anywhere">'+e(v)+'</td></tr>').join('')+'</table>'+('<p>'+e(paid?t.paidNote:t.pendingNote)+'</p>')+'<p style="font-size:12px">'+e(t.note)+'</p></section>';
  return {kind:paid?'RECEIPT':'STATEMENT',subject:'T-Rider · '+title+' · '+number,lines,html};
}
module.exports={receiptDocument,copy};
