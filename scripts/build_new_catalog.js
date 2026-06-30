const path=require('path');const fs=require('fs');const ROOT=process.cwd();
const drive=require(path.join(ROOT,'docs','video-catalog-audit','drive-videos.json'));
const FOLDER_EQUIP={dumbbells:'mancuerna',barbell:'barra',bodyweight:'peso_corporal',kettlebells:'pesa_rusa',cables:'polea',band:'banda',machine:'maquina',plate:'disco','smith-machine':'multipower','medicine-ball':'balon',trx:'trx',cardio:'cardio'};
const EQ_LABEL={mancuerna:'(Mancuerna)',barra:'(Barra)',polea:'(Polea)',maquina:'(Máquina)',pesa_rusa:'(Pesa rusa)',banda:'(Banda)',disco:'(Disco)',multipower:'(Multipower)',trx:'(TRX)',balon:'(Balón medicinal)',peso_corporal:'',cardio:''};
const EXCLUDE=new Set(['recovery','yoga','stretches','pilates','bosu-ball','vitruvian','medicineball']);
const NOISE=new Set(['braced','bayesian','staggered','rolling','spinal','jefferson','internally','rotated','eccentric','isometric','tempo','deficit','explosive','slalom','switch','silverback','rapunzel','bottoms','bradford','45','30','degree','prayer','semi','balance','outs','in','tip','toe-up','snatch-grip','trap','long','short','toes-up','palms','tibialis','around','jacks','gluteator','assault','stationary','bodybuilding','spoto','pop','saw','body','quick','feet','gauntlet','box-quick','copenhagen']);
const isView=t=>/^(side|front)$/.test(t);
function tokensOf(v){let t=v.title.replace(/\.mp4$/i,'').replace(/_[a-z0-9]+$/i,'').split('-').map(x=>x.toLowerCase()).filter(Boolean);
 if(t[0]==='female'||t[0]==='male')t.shift();while(t.length&&isView(t[t.length-1]))t.pop();
 const f=v.folder.toLowerCase();
 // quitar prefijos de carpeta/equipo repetidos
 while(t.length&&(t[0]===f||t[0]===f.replace(/s$/,'')||t[0]==='smithmachine'||t[0]==='bodyweight'||t[0]==='cardio'||t[0]==='dumbbell'||t[0]==='dumbbells'||t[0]==='barbell'||t[0]==='cable'||t[0]==='cables'||t[0]==='machine'||t[0]==='band'||t[0]==='kettlebell'||t[0]==='kettlebells'||t[0]==='plate'||t[0]==='trx'))t.shift();
 return t;}
// MÚSCULO contextual
function muscle(s){
 if(/\bcalf\b|\bcalve\b|calves/.test(s))return 'calves';
 if(/hamstring|nordic|stiff-leg|good-morning|romanian|leg-curl/.test(s))return 'hamstrings';
 if(/tricep|skullcrusher|pushdown|pressdown|close-grip|kickback.*tricep|tricep.*kickback|guillotine|overhead-tricep|french/.test(s)&&!/glute/.test(s))return 'triceps';
 if(/hip-thrust|glute|clamshell|hydrant|abduction|adduction|bridge|frog-pump|kickback/.test(s))return 'glutes';
 if(/squat|lunge|leg-press|leg-extension|step-up|sissy|pistol|wall-sit/.test(s))return 'quads';
 if(/curl/.test(s)&&!/leg|wrist|nordic/.test(s))return 'biceps';
 if(/bench-press|chest|pec|chest-fly|chest-press|push-up|pushup/.test(s))return 'chest';
 if(/lateral-raise|front-raise|rear-delt|reverse-fly|shoulder-press|overhead-press|military|upright|y-raise|halo|arnold|pike-press|pike-shrug|face-pull|delt/.test(s))return 'shoulders';
 if(/row|pulldown|pull-up|pullup|chin-up|chinup|pullover|shrug|lat-|superman/.test(s))return 'back';
 if(/crunch|sit-up|situp|plank|leg-raise|knee-raise|knee-tuck|twist|oblique|hollow|v-up|russian|pallof|wood-chop|jackknife|scissor|heel-touch|ab-|toes-to-bar|dragon|flutter|bicycle|dead-bug|bird-dog|side-bend/.test(s))return 'core';
 if(/clean|snatch|jerk|thruster|burpee|swing|turkish|carry|farmer|wall-ball|ball-slam|sled|high-pull|push-press|get-up/.test(s))return 'fullbody';
 if(/\bfly\b|\braise\b/.test(s))return 'shoulders';
 if(/\bpress\b|\bdip\b/.test(s))return 'chest';
 if(/\bextension\b/.test(s))return 'triceps';
 return 'fullbody';}
// NÚCLEO (token clave → traducción ES, va primero)
const NUCLEUS=[['hip-abduction','Abducción de cadera'],['hip-adduction','Aducción de cadera'],['arm-circle','Círculo de brazos'],['step-down','Bajada del cajón'],['skullcrusher','Rompecráneos'],['bench-press','Press de banca'],['chestpress','Press de pecho'],['chest-press','Press de pecho'],['pec-fly','Apertura de pecho'],['rear-delt-fly','Apertura de deltoides posterior'],['reverse-fly','Apertura inversa'],['front-raise','Elevación frontal'],['lateral-raise','Elevación lateral'],['chest-fly','Apertura de pecho'],['overhead-press','Press militar'],['shoulder-press','Press de hombros'],['leg-press','Prensa de piernas'],['leg-extension','Extensión de cuádriceps'],['leg-curl','Curl femoral'],['calf-raise','Elevación de gemelos'],['hip-thrust','Empuje de cadera'],['glute-bridge','Puente de glúteo'],['face-pull','Jalón al rostro'],['pull-up','Dominada'],['pullup','Dominada'],['chin-up','Dominada supina'],['chinup','Dominada supina'],['push-up','Flexión'],['pushup','Flexión'],['pushdown','Empuje de tríceps'],['pulldown','Jalón al pecho'],['lat-pulldown','Jalón al pecho'],['good-morning','Buenos días'],['step-up','Subida al cajón'],['box-jump','Salto al cajón'],['wall-ball','Wall ball'],['ball-slam','Golpe con balón'],['turkish-get-up','Levantada turca'],['get-up','Levantada turca'],['russian-twist','Giro ruso'],['wood-chopper','Leñador'],['pallof','Press Pallof'],['v-up','V-up'],['sit-up','Abdominal'],['situp','Abdominal'],['mountain-climber','Escalador'],['dead-bug','Dead bug'],['bird-dog','Bird dog'],['curl','Curl'],['press','Press'],['squat','Sentadilla'],['deadlift','Peso muerto'],['row','Remo'],['lunge','Estocada'],['raise','Elevación'],['fly','Apertura'],['extension','Extensión'],['crunch','Crunch'],['plank','Plancha'],['dip','Fondo'],['dips','Fondos'],['shrug','Encogimiento'],['swing','Swing'],['clean','Cargada'],['snatch','Arranque'],['jerk','Envión'],['thruster','Thruster'],['kickback','Patada'],['twist','Giro'],['pullover','Pullover'],['pull','Tirón'],['burpee','Burpee'],['carry','Caminata']];
const MOD={incline:'inclinado',decline:'declinado',seated:'sentado',standing:'de pie',kneeling:'arrodillado',lying:'tumbado',laying:'tumbado',reverse:'inverso',hammer:'martillo',preacher:'predicador',spider:'araña',concentration:'concentrado',romanian:'rumano',sumo:'sumo',front:'frontal',lateral:'lateral',rear:'posterior',delt:'deltoides',close:'cerrado',wide:'abierto',grip:'agarre',overhead:'sobre la cabeza',bulgarian:'búlgara',split:'búlgara',goblet:'goblet',zottman:'Zottman',pike:'pike',diamond:'diamante',clapping:'con palmada',jump:'con salto',jumping:'con salto',box:'al cajón',single:'a un',arm:'brazo',leg:'pierna',drag:'de arrastre',upright:'al mentón',pec:'',deck:'pec deck',neutral:'neutro',hex:'hex',svend:'svend',meadows:'Meadows',pendlay:'Pendlay',zercher:'Zercher',cossack:'cosaco',curtsy:'cruzada',walking:'caminando',forward:'',alternating:'alterna',weighted:'con peso',assisted:'asistida',banded:'con banda',landmine:'landmine',bench:'en banco',floor:'en el suelo',ring:'en anillas',supinated:'supino',pronated:'prono','rope':'con cuerda',bar:'con barra',crossover:'cruce',oblique:'oblicuo',bicycle:'bicicleta',flutter:'de tijera',scissor:'tijera',hollow:'hollow',russian:'ruso',superman:'Superman',nordic:'nórdico',sissy:'sissy',pistol:'pistol',hack:'hack',pendulum:'péndulo',belt:'con cinturón',horizontal:'horizontal',vertical:'vertical',bicep:'',biceps:'',tricep:'tríceps',flys:'',flyes:'',ups:'',up:'',calve:'gemelo',chest:'de pecho',full:'',half:'',renegade:'renegado',gorilla:'gorila',wrist:'de muñeca',twisting:'con giro',waiter:'camarero',pinwheel:'molinete',high:'alto',low:'bajo',seal:'seal',deadbug:'',roll:'',squeeze:'de presión',guillotine:'guillotina',lunges:'',raises:'',mornings:'',situps:'',crunches:'',rows:'',presses:'',curls:'',extensions:'',double:'doble',power:'de potencia',hold:'isométrico',loaded:'',hip:'de cadera',abduction:'de cadera',adduction:'de cadera',frog:'rana',anterior:'',ham:'e isquios',muscle:'',quick:'',feet:'',circle:'círculo',backward:'',hangs:'',hang:'colgado',raised:'elevado',toe:'puntas',touch:'toque',heel:'talón',knee:'rodilla',tuck:'',raise:'Elevación',bench:'en banco',deadlift:'Peso muerto',down:'',bike:'',brazo:'de brazos',deltoid:'',hip:''};
function nameES(eqES,mv){let toks=[...mv];let nuc=null,nucIdx=-1;
 for(const [k,es] of NUCLEUS){const i=toks.indexOf(k);const j=toks.join('-').indexOf(k);
  if(toks.includes(k)){nuc=es;toks=toks.filter(t=>t!==k);nucIdx=i;break;}
  // compound nucleus (bench-press)
  if(k.includes('-')&&toks.join('-').includes(k)){nuc=es;const parts=k.split('-');toks=toks.filter(t=>!parts.includes(t));break;}}
 if(!nuc){nuc=toks.shift()||'';nuc=nuc.charAt(0).toUpperCase()+nuc.slice(1);}
 const mods=toks.map(t=>MOD[t]!==undefined?MOD[t]:t).filter(Boolean);
 let name=(nuc+' '+mods.join(' ')).replace(/\s+/g,' ').trim();
 // quitar palabras duplicadas consecutivas (ej "tríceps tríceps")
 name=name.split(' ').filter((w,i,a)=>w.toLowerCase()!==(a[i-1]||'').toLowerCase()).join(' ');
 const lbl=EQ_LABEL[eqES]||'';
 return (name.charAt(0).toUpperCase()+name.slice(1)+(lbl?' '+lbl:'')).trim();}
const seen=new Map();
for(const v of drive.videos){const f=v.folder.toLowerCase();if(EXCLUDE.has(f))continue;
 const eqES=FOLDER_EQUIP[f]||'otro';const mv=tokensOf(v);if(!mv.length)continue;
 if(mv.length>3)continue;if(mv.some(t=>NOISE.has(t)))continue;
 const key=eqES+'|'+mv.slice().sort().join('-');const isSide=/side/.test(v.title);
 if(!seen.has(key)||isSide)seen.set(key,{eqES,mv,fileId:v.id,filename:v.title});}
const cat=[];const byMg={};const usedId=new Set();const usedName=new Set();
for(const e of seen.values()){const s=e.mv.join('-');const mg=muscle(s);
 const name=nameES(e.eqES,e.mv);
 if(usedName.has(name.toLowerCase()))continue; // dedup por nombre final
 usedName.add(name.toLowerCase());
 let id=(e.mv.join('-')+'-'+e.eqES).replace(/[^a-z0-9-]/g,'').replace(/-+/g,'-');while(usedId.has(id))id+='-2';usedId.add(id);
 cat.push({id,name,muscleGroup:mg,equipoES:e.eqES,filename:e.filename,fileId:e.fileId});byMg[mg]=(byMg[mg]||0)+1;}
cat.sort((a,b)=>a.muscleGroup.localeCompare(b.muscleGroup)||a.name.localeCompare(b.name,'es'));
fs.writeFileSync(path.join(ROOT,'docs','video-catalog-audit','NUEVO-catalogo.json'),JSON.stringify(cat,null,2));
console.log('TOTAL:',cat.length,'| Por grupo:',JSON.stringify(byMg));
