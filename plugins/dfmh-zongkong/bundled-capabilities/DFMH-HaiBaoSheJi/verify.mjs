import { createHash } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import path from 'node:path';

const root=process.cwd();
const manifest=JSON.parse(await readFile(path.join(root,'PACKAGE_MANIFEST.json'),'utf8'));
if(manifest.repoName!=='DFMH-HaiBaoSheJi'||manifest.publicSkillId!=='public.promotional-poster'||manifest.maturity!=='operational') throw new Error('Package manifest binding mismatch');
for(const item of manifest.files){const bytes=await readFile(path.join(root,item.relativePath));const hash=createHash('sha256').update(bytes).digest('hex');if(bytes.length!==item.bytes||hash!==item.sha256) throw new Error('Package file hash mismatch: '+item.relativePath);}
const registry=JSON.parse(await readFile(path.join(root,'public-skills','registry.json'),'utf8'));
if(registry.publicSkills?.length!==1||registry.publicSkills[0].id!=='public.promotional-poster'||registry.publicSkills[0].maturity!=='operational') throw new Error('Public skill registry mismatch');
const denied=new Set(['temp','outputs','enterprises','issues','fixtures']);
async function walk(dir){for(const entry of await readdir(dir,{withFileTypes:true})){if(entry.isDirectory()){if(denied.has(entry.name)) throw new Error('Denied directory: '+entry.name);await walk(path.join(dir,entry.name));}}}
await walk(root);
console.log('PASS: DFMH-HaiBaoSheJi package integrity; maturity=operational');
