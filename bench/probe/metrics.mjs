import { readFileSync } from "node:fs";
const f = readFileSync(process.argv[2]);
const n = f.readUInt16BE(4); const tables={};
for (let i=0;i<n;i++){const o=12+i*16; tables[f.toString('latin1',o,o+4)]={off:f.readUInt32BE(o+8)};}
const head=tables.head.off, hhea=tables.hhea.off, os2=tables['OS/2'].off;
console.log("upem", f.readUInt16BE(head+18));
console.log("hhea asc/desc/gap", f.readInt16BE(hhea+4), f.readInt16BE(hhea+6), f.readInt16BE(hhea+8));
console.log("typo asc/desc/gap", f.readInt16BE(os2+68), f.readInt16BE(os2+70), f.readInt16BE(os2+72), "win", f.readUInt16BE(os2+74), f.readUInt16BE(os2+76), "fsSelection", f.readUInt16BE(os2+62).toString(2));
