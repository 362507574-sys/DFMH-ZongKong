import { mkdtemp, readFile, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { initializeDfmh } from './plugins/dfmh-zongkong/scripts/bootstrap.mjs';
const root=await mkdtemp(path.join(os.tmpdir(),'dfmh-zongkong-install-'));
try{
 const first=await initializeDfmh({codexHome:root});
 const second=await initializeDfmh({codexHome:root});
 const state=JSON.parse(await readFile(path.join(root,'dfmh-zongkong','state.json'),'utf8'));
 if(first.created!==true||second.created!==false||state.telemetry!==false||state.feishu!=='not_configured') throw new Error('install state invalid');
 console.log('PASS: DFMH-ZongKong clean install simulation; feishu=not_configured; idempotent=true; telemetry=false');
}finally{await rm(root,{recursive:true,force:true});}
