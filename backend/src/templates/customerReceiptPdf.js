const PDFDocument=require('pdfkit');
const fs=require('node:fs');
const path=require('node:path');
const PDF_TEMPLATE_VERSION=1;
let fonts;
function fontData(){if(!fonts)fonts={cjk:fs.readFileSync(path.join(__dirname,'../../assets/receipt-pdf/NotoSansCJKkr-Regular.otf')),thai:fs.readFileSync(path.join(__dirname,'../../assets/receipt-pdf/NotoSansThai.ttf'))};return fonts;}
function createReceiptPdf(model){
 return new Promise((resolve,reject)=>{
  const doc=new PDFDocument({size:'A4',margin:0,bufferPages:true,info:{Title:'T-Rider - '+model.title,Author:'T-Rider',Creator:'T-Rider',CreationDate:new Date()}}),parts=[];
  doc.on('data',b=>parts.push(b));doc.on('error',reject);doc.on('end',()=>resolve(Buffer.concat(parts)));
  try{
   const data=fontData();doc.registerFont('cjk',data.cjk);doc.registerFont('thai',data.thai);
   const face=c=>/[\u0e00-\u0e7f]/.test(c)?'thai':'cjk',cache=new Map(),segmenter=new Intl.Segmenter(model.locale||'en',{granularity:'grapheme'});
   function lines(text,width,size){const out=[];let line='',used=0;for(const {segment:c} of segmenter.segment(String(text||'').replace(/\r/g,''))){if(c==='\n'){out.push(line);line='';used=0;continue;}const key=face(c)+size+c;let w=cache.get(key);if(w===undefined){w=doc.font(face(c)).fontSize(size).widthOfString(c);cache.set(key,w);}if(used+w>width&&line){out.push(line);line='';used=0;}line+=c;used+=w;}if(line||!out.length)out.push(line);return out;}
   function text(line,x,y,size,color='#25393b'){const runs=String(line).match(/[\u0e00-\u0e7f]+|[^\u0e00-\u0e7f]+/g)||[''];doc.fillColor(color);runs.forEach((s,i)=>{doc.font(face(s)).fontSize(size);if(i===0)doc.text(s,x,y,{lineBreak:false,continued:i<runs.length-1});else doc.text(s,{lineBreak:false,continued:i<runs.length-1});});}
   function paragraph(ls,x,y,size,color){ls.forEach((l,i)=>text(l,x,y+i*(size+5),size,color));}
   let y=150;
   function header(){text('T-Rider',44,35,23,'#006a60');doc.moveTo(44,78).lineTo(551,78).lineWidth(2).strokeColor('#c79836').stroke();text(model.title,44,96,19,'#006a60');y=150;}
   function nextPage(){doc.addPage();header();}
   header();
   model.rows.forEach(([label,value],rowIndex)=>{
    const amount=rowIndex===model.rows.length-1,size=amount?13:10,labelSize=9;
    const ll=lines(label,145,labelSize),vl=lines(value,319,size);
    for(let offset=0;offset<vl.length;offset+=30){const chunk=vl.slice(offset,offset+30),h=Math.max(ll.length*14,chunk.length*(size+5))+24;
     if(y+h>735)nextPage();
     if(amount)doc.rect(44,y,507,h).fill('#e7f4ef');
     paragraph(ll,56,y+11,labelSize,'#5b6e70');paragraph(chunk,220,y+10,size,amount?'#006a60':'#25393b');
     doc.moveTo(44,y+h).lineTo(551,y+h).lineWidth(.5).strokeColor('#dce6e3').stroke();y+=h;
    }
   });
   const note=lines(model.statusNote,507,9);if(y+note.length*14+24>735)nextPage();paragraph(note,44,y+20,9,'#5b6e70');
   const range=doc.bufferedPageRange();for(let i=range.start;i<range.start+range.count;i++){doc.switchToPage(i);paragraph(lines(model.note,507,8),44,771,8,'#5b6e70');text('https://trider.taxi/support?lang='+model.locale,44,810,8,'#006a60');text((i+1)+' / '+range.count,518,810,8,'#5b6e70');}
   doc.end();
  }catch(e){reject(e);}
 });
}
async function withReceiptPdf(message){
 if(!message?.receiptPdfModel)return message;
 const {receiptPdfModel:model,...body}=message;
 const pdf=await createReceiptPdf(model),number=String(model.bookingNumber||'booking').replace(/[^A-Za-z0-9_-]/g,'_');
 return {...body,attachments:[{filename:'T-Rider-'+(model.kind==='RECEIPT'?'Receipt':'Statement')+'-'+number+'-'+model.locale+'.pdf',content:pdf.toString('base64'),encoding:'base64',contentType:'application/pdf',contentDisposition:'attachment'}]};
}
function withoutPdfModel(message){if(!message)return message;const {receiptPdfModel,...rest}=message;return rest;}
module.exports={createReceiptPdf,withReceiptPdf,withoutPdfModel,PDF_TEMPLATE_VERSION};
