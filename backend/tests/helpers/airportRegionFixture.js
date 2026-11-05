const fs = require('node:fs');
const path = require('node:path');
module.exports = () => {
  const sql=fs.readFileSync(path.join(__dirname,'../../../database/75_region_fixed_fare_proposal.sql'),'utf8');
  return ['BKK','DMK','UTP'].map(code => {
    const m=sql.match(new RegExp("\\('"+code+"','"+code+"','"+code+"','([^']+)'"));
    if(!m) throw Error('Missing approved airport geometry '+code);
    return {airport_iata:code,is_active:1,geometry:JSON.parse(m[1])};
  });
};
