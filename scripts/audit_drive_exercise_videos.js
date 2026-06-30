#!/usr/bin/env node
'use strict';

/**
 * Audits a public Google Drive exercise-video folder against TREINO's local
 * exercise catalog sources.
 *
 * This is report-only. It does not download videos, upload to Firebase, or
 * write Firestore docs.
 *
 * Usage:
 *   node scripts/audit_drive_exercise_videos.js
 *   DRIVE_FOLDER_ID=... node scripts/audit_drive_exercise_videos.js
 */

const childProcess = require('child_process');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const DEFAULT_FOLDER_ID = '1eoEXi-QH1NYiEKbgzJDDbUHpdgZD_QlQ';
const DRIVE_FOLDER_ID = process.env.DRIVE_FOLDER_ID || DEFAULT_FOLDER_ID;
const OUT_DIR = path.join(ROOT, 'docs', 'video-catalog-audit');
const { equipmentMap } = require('./_equipment_map.js');

const VIDEO_EXT_RE = /\.(mp4|mov|m4v|webm)$/i;
const VIEW_SUFFIXES = new Set(['front', 'side']);
const GENDERS = new Set(['male', 'female']);
const EQUIPMENT_ALIASES = new Map([
  ['band', ['band', 'bands', 'resistance-band']],
  ['barbell', ['barbell', 'barbells']],
  ['bodyweight', ['bodyweight', 'body-weight']],
  ['bosu-ball', ['bosu-ball', 'bosu']],
  ['cables', ['cables', 'cable']],
  ['cardio', ['cardio']],
  ['dumbbells', ['dumbbells', 'dumbbell']],
  ['kettlebells', ['kettlebells', 'kettlebell']],
  ['machine', ['machine']],
  ['medicine-ball', ['medicine-ball', 'medicineball', 'med-ball']],
  ['medicineball', ['medicine-ball', 'medicineball', 'med-ball']],
  ['pilates', ['pilates']],
  ['plate', ['plate']],
  ['recovery', ['recovery']],
  ['smith-machine', ['smith-machine', 'smith']],
  ['stretches', ['stretches', 'stretch']],
  ['trx', ['trx', 'suspension']],
  ['vitruvian', ['vitruvian']],
  ['yoga', ['yoga']],
]);

const NOISE_TOKENS = new Set([
  'barbell',
  'dumbbell',
  'dumbbells',
  'cable',
  'cables',
  'machine',
  'bodyweight',
  'body',
  'weight',
  'band',
  'bands',
  'kettlebell',
  'kettlebells',
  'plate',
  'smith',
  'trx',
  'suspension',
]);

const MODIFIER_TOKENS = new Set([
  'assisted',
  'banded',
  'weighted',
  'pause',
  'paused',
  'deficit',
  'incline',
  'decline',
  'seated',
  'standing',
  'single',
  'double',
  'staggered',
]);

const FOLDER_EQUIPMENT = new Map([
  ['Band', 'banda'],
  ['Barbell', 'barra'],
  ['Bodyweight', 'peso_corporal'],
  ['Bosu-Ball', 'bosu'],
  ['Cables', 'cable'],
  ['Cardio', 'cardio'],
  ['Dumbbells', 'mancuerna'],
  ['Kettlebells', 'otro'],
  ['Machine', 'maquina'],
  ['Medicine-Ball', 'otro'],
  ['Medicineball', 'otro'],
  ['Pilates', 'otro'],
  ['Plate', 'otro'],
  ['Recovery', 'otro'],
  ['Smith-Machine', 'maquina'],
  ['Stretches', 'peso_corporal'],
  ['TRX', 'suspension'],
  ['Vitruvian', 'maquina'],
  ['Yoga', 'peso_corporal'],
]);

const NAME_EQUIPMENT = [
  { re: /\bbarbell\b|\(barbell\)/i, equipment: 'barra' },
  { re: /\bdumbbell\b|\(dumbbell\)/i, equipment: 'mancuerna' },
  { re: /\bcable\b|\(cable\)/i, equipment: 'cable' },
  { re: /\bband\b|\(band\)/i, equipment: 'banda' },
  { re: /\bbodyweight\b|\(bodyweight\)/i, equipment: 'peso_corporal' },
  { re: /\bmachine\b|\(machine\)/i, equipment: 'maquina' },
  { re: /\bsmith\b|\(smith machine\)/i, equipment: 'maquina' },
  { re: /\bsuspension\b|\(suspension\)|\btrx\b/i, equipment: 'suspension' },
  { re: /\bkettlebell\b|\(kettlebell\)|\btrap bar\b|\bmedicine ball\b|\bplate\b|\bbosu\b/i, equipment: 'otro' },
];

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function htmlDecode(value) {
  return String(value)
    .replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>');
}

function normalize(value) {
  return String(value || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/&/g, ' and ')
    .replace(/[()]/g, ' ')
    .replace(/[^a-z0-9]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function slug(value) {
  return normalize(value).replace(/\s+/g, '-');
}

function unique(values) {
  return [...new Set(values.filter(Boolean))];
}

function csvEscape(value) {
  const s = value == null ? '' : String(value);
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

function writeCsv(fileName, rows, columns) {
  const lines = [columns.join(',')];
  for (const row of rows) {
    lines.push(columns.map((c) => csvEscape(row[c])).join(','));
  }
  fs.writeFileSync(path.join(OUT_DIR, fileName), `${lines.join('\n')}\n`);
}

function fetchEmbeddedFolder(folderId) {
  const url = `https://drive.google.com/embeddedfolderview?id=${folderId}#list`;
  const result = childProcess.spawnSync('curl', ['-fsSL', url], {
    encoding: 'utf8',
    maxBuffer: 64 * 1024 * 1024,
  });
  if (result.status !== 0) {
    throw new Error(`Could not fetch Drive folder ${folderId}: ${result.stderr}`);
  }
  return result.stdout;
}

function parseEmbeddedEntries(html) {
  const re =
    /<div class="flip-entry" id="entry-([^"]+)"[\s\S]*?<a href="([^"]+)"[\s\S]*?<div class="flip-entry-title">([^<]+)<\/div>/g;
  const entries = [];
  let match;
  while ((match = re.exec(html))) {
    const id = htmlDecode(match[1]);
    const href = htmlDecode(match[2]);
    const title = htmlDecode(match[3]);
    entries.push({
      id,
      href,
      title,
      kind: href.includes('/drive/folders/') ? 'folder' : 'file',
    });
  }
  return entries;
}

function listDriveTree(rootFolderId) {
  const queue = [{ id: rootFolderId, path: [] }];
  const visited = new Set();
  const folders = [];
  const videos = [];

  while (queue.length > 0) {
    const folder = queue.shift();
    if (visited.has(folder.id)) continue;
    visited.add(folder.id);

    const html = fetchEmbeddedFolder(folder.id);
    const entries = parseEmbeddedEntries(html);
    folders.push({ id: folder.id, path: folder.path.join('/'), entries: entries.length });

    for (const entry of entries) {
      if (entry.kind === 'folder') {
        queue.push({ id: entry.id, path: [...folder.path, entry.title] });
        continue;
      }
      if (!VIDEO_EXT_RE.test(entry.title)) continue;
      videos.push({
        id: entry.id,
        title: entry.title,
        href: entry.href,
        folder: folder.path.join('/'),
        folderLeaf: folder.path.at(-1) || '',
      });
    }
  }
  return { folders, videos };
}

function extractSeedExercises() {
  const file = path.join(ROOT, 'scripts', 'seed_workout_catalog.js');
  const source = fs.readFileSync(file, 'utf8');
  const start = source.indexOf('const exercises = [');
  const end = source.indexOf('// -- ROUTINES DATA');
  if (start === -1 || end === -1) return [];
  const arrayStart = source.indexOf('[', start);
  const arrayEnd = source.lastIndexOf('];', end) + 1;
  const literal = source.slice(arrayStart, arrayEnd);
  return Function(`return ${literal};`)().map((exercise) => ({
    ...exercise,
    source: 'seed',
  }));
}

function toImportedId(nameEn) {
  return String(nameEn || '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

function loadCatalog() {
  const byId = new Map();

  for (const exercise of extractSeedExercises()) {
    byId.set(exercise.id, {
      id: exercise.id,
      name: exercise.name,
      nameEn: '',
      aliases: exercise.aliases || [],
      muscleGroup: exercise.muscleGroup || '',
      source: 'seed',
    });
  }

  const imported = JSON.parse(
    fs.readFileSync(path.join(ROOT, 'docs', 'exercises_catalog.json'), 'utf8'),
  ).exercises;
  for (const exercise of imported) {
    const id = toImportedId(exercise.name_en);
    if (!id) continue;
    const existing = byId.get(id);
    byId.set(id, {
      id,
      name: exercise.name_es || existing?.name || '',
      nameEn: exercise.name_en || existing?.nameEn || '',
      aliases: unique([...(existing?.aliases || []), exercise.name_es, exercise.name_en, exercise.source_id]),
      muscleGroup: exercise.muscle_es || existing?.muscleGroup || '',
      source: existing ? `${existing.source}+catalog-json` : 'catalog-json',
    });
  }

  const technique = JSON.parse(
    fs.readFileSync(path.join(ROOT, 'docs', 'exercise_technique.json'), 'utf8'),
  ).technique;
  for (const id of Object.keys(technique || {})) {
    const existing = byId.get(id);
    if (existing) {
      existing.hasTechnique = true;
    } else {
      byId.set(id, {
        id,
        name: '',
        nameEn: id.replace(/-/g, ' '),
        aliases: [],
        muscleGroup: '',
        source: 'technique-only',
        hasTechnique: true,
      });
    }
  }

  return [...byId.values()].map((exercise) => ({
    ...exercise,
    hasTechnique: Boolean(exercise.hasTechnique),
    equipment: expectedExerciseEquipment(exercise),
  }));
}

function expectedExerciseEquipment(exercise) {
  if (equipmentMap[exercise.id]) return equipmentMap[exercise.id];
  const haystack = [exercise.id, exercise.name, exercise.nameEn, ...(exercise.aliases || [])].join(' ');
  for (const hint of NAME_EQUIPMENT) {
    if (hint.re.test(haystack)) return hint.equipment;
  }
  return '';
}

function catalogKeys(exercise) {
  const keys = [
    { key: exercise.id, kind: 'id' },
    { key: slug(exercise.name), kind: 'name_es' },
    { key: slug(exercise.nameEn), kind: 'name_en' },
  ];
  for (const alias of exercise.aliases || []) {
    keys.push({ key: slug(alias), kind: 'alias' });
  }
  return keys.filter((item) => item.key);
}

function stripExt(fileName) {
  return String(fileName).replace(VIDEO_EXT_RE, '');
}

function folderEquipmentTokens(folderLeaf) {
  const key = slug(folderLeaf);
  const aliases = EQUIPMENT_ALIASES.get(key) || [key];
  return new Set(aliases.flatMap((alias) => slug(alias).split('-')));
}

function cleanVideoTokens(video) {
  let tokens = slug(stripExt(video.title)).split('-').filter(Boolean);
  if (GENDERS.has(tokens[0])) tokens = tokens.slice(1);
  if (VIEW_SUFFIXES.has(tokens.at(-1))) tokens = tokens.slice(0, -1);

  const folderTokens = folderEquipmentTokens(video.folderLeaf);
  while (tokens.length && folderTokens.has(tokens[0])) tokens = tokens.slice(1);
  while (tokens.length > 1 && tokens[0] === tokens[1]) tokens = tokens.slice(1);

  return tokens;
}

function videoEquipment(video) {
  return FOLDER_EQUIPMENT.get(video.folderLeaf) || '';
}

function videoCandidates(video) {
  const tokens = cleanVideoTokens(video);
  const candidates = [];
  const add = (parts, kind, score) => {
    const key = parts.filter(Boolean).join('-');
    if (key) candidates.push({ key, kind, score });
  };

  add(tokens, 'video_clean', 1);

  if (tokens.length > 1 && NOISE_TOKENS.has(tokens[0])) {
    add(tokens.slice(1), 'drop_leading_equipment', 0.93);
    add([...tokens.slice(1), tokens[0]], 'move_equipment_to_end', 0.96);
  }

  const noNoise = tokens.filter((token) => !NOISE_TOKENS.has(token));
  add(noNoise, 'drop_equipment', 0.86);

  const noModifiers = tokens.filter((token) => !MODIFIER_TOKENS.has(token));
  add(noModifiers, 'drop_modifiers', 0.78);
  add(noModifiers.filter((token) => !NOISE_TOKENS.has(token)), 'drop_equipment_and_modifiers', 0.72);

  return unique(candidates.map((c) => `${c.key}|${c.kind}|${c.score}`)).map((raw) => {
    const [key, kind, score] = raw.split('|');
    return { key, kind, score: Number(score) };
  });
}

function tokenSimilarity(a, b) {
  const aa = new Set(String(a).split('-').filter(Boolean));
  const bb = new Set(String(b).split('-').filter(Boolean));
  if (!aa.size || !bb.size) return 0;
  let intersection = 0;
  for (const token of aa) {
    if (bb.has(token)) intersection += 1;
  }
  return intersection / Math.max(aa.size, bb.size);
}

function matchVideosToCatalog(videos, catalog) {
  const keyIndex = new Map();
  for (const exercise of catalog) {
    for (const key of catalogKeys(exercise)) {
      const bucket = keyIndex.get(key.key) || [];
      bucket.push({ exercise, kind: key.kind });
      keyIndex.set(key.key, bucket);
    }
  }

  const matches = [];
  for (const video of videos) {
    const candidates = videoCandidates(video);
    const seen = new Set();
    const videoMatches = [];

    for (const candidate of candidates) {
      const hits = keyIndex.get(candidate.key) || [];
      for (const hit of hits) {
        const id = `${video.id}:${hit.exercise.id}`;
        if (seen.has(id)) continue;
        seen.add(id);
        const keyLength = candidate.key.split('-').filter(Boolean).length;
        let keyMultiplier = 0.98;
        if (hit.kind === 'id') keyMultiplier = 1;
        if (hit.kind === 'name_en') keyMultiplier = 0.98;
        if (hit.kind === 'name_es') keyMultiplier = 0.92;
        if (hit.kind === 'alias') keyMultiplier = keyLength <= 2 ? 0.62 : 0.78;
        const score = applyEquipmentPenalty(
          candidate.score * keyMultiplier,
          video,
          hit.exercise,
        );
        videoMatches.push({ video, exercise: hit.exercise, score, reason: `${candidate.kind}:${hit.kind}` });
      }
    }

    if (videoMatches.length === 0) {
      let best = null;
      const primary = candidates[0]?.key || '';
      for (const exercise of catalog) {
        for (const key of catalogKeys(exercise)) {
          const sim = tokenSimilarity(primary, key.key);
          if (sim < 0.7) continue;
          const current = {
            video,
            exercise,
            score: applyEquipmentPenalty(sim * 0.68, video, exercise),
            reason: `token_similarity:${key.kind}`,
          };
          if (!best || current.score > best.score) best = current;
        }
      }
      if (best) videoMatches.push(best);
    }

    videoMatches.sort((a, b) => b.score - a.score || a.exercise.id.localeCompare(b.exercise.id));
    const top = videoMatches[0];
    if (top) {
      matches.push({
        ...top,
        confidence: top.score >= 0.95 ? 'high' : top.score >= 0.8 ? 'medium' : 'low',
      });
    } else {
      matches.push({ video, exercise: null, score: 0, confidence: 'none', reason: 'unmatched' });
    }
  }
  return matches;
}

function applyEquipmentPenalty(score, video, exercise) {
  const expected = exercise.equipment || '';
  const actual = videoEquipment(video);
  if (!expected || !actual) return score;
  if (expected === actual) return score;
  return score * 0.52;
}

function duplicateFamilies(catalog) {
  const families = new Map();
  for (const exercise of catalog) {
    const name = exercise.nameEn || exercise.name || exercise.id;
    const base = slug(name.replace(/\(.*?\)/g, ''));
    if (!base) continue;
    const bucket = families.get(base) || [];
    bucket.push(exercise);
    families.set(base, bucket);
  }
  return [...families.entries()]
    .filter(([, items]) => items.length > 1)
    .map(([family, items]) => ({
      family,
      count: items.length,
      ids: items.map((e) => e.id).join('|'),
      names: items.map((e) => e.nameEn || e.name || e.id).join('|'),
      sources: unique(items.map((e) => e.source)).join('|'),
    }))
    .sort((a, b) => b.count - a.count || a.family.localeCompare(b.family));
}

function duplicateEquipmentReview(catalog) {
  return duplicateFamilies(catalog).map((family) => {
    const ids = family.ids.split('|');
    const items = ids.map((id) => catalog.find((exercise) => exercise.id === id)).filter(Boolean);
    const equipmentGroups = new Map();
    for (const item of items) {
      const key = item.equipment || 'unknown';
      const bucket = equipmentGroups.get(key) || [];
      bucket.push(item);
      equipmentGroups.set(key, bucket);
    }

    const sameEquipmentGroups = [...equipmentGroups.entries()]
      .filter(([, group]) => group.length > 1)
      .map(([equipment, group]) => `${equipment}:${group.map((item) => item.id).join('|')}`);
    const knownEquipmentCount = [...equipmentGroups.keys()].filter((key) => key !== 'unknown').length;
    const hasUnknown = equipmentGroups.has('unknown');

    let classification = 'valid_equipment_variants';
    let action = 'keep_as_variants';
    if (sameEquipmentGroups.length > 0) {
      classification = 'review_same_equipment_duplicates';
      action = 'manual_review_same_equipment';
    } else if (hasUnknown && knownEquipmentCount > 0) {
      classification = 'review_generic_or_missing_equipment';
      action = 'decide_default_variant_or_fill_equipment';
    } else if (hasUnknown) {
      classification = 'needs_equipment_mapping';
      action = 'fill_equipment_before_dedup';
    }

    return {
      family: family.family,
      count: family.count,
      classification,
      action,
      equipment_groups: [...equipmentGroups.entries()]
        .map(([equipment, group]) => `${equipment}:${group.map((item) => item.id).join('|')}`)
        .join('; '),
      same_equipment_groups: sameEquipmentGroups.join('; '),
      ids: family.ids,
      names: family.names,
      sources: family.sources,
    };
  });
}

function groupRecommendations(matches) {
  const byExercise = new Map();
  for (const match of matches) {
    if (!match.exercise || match.confidence === 'none') continue;
    const bucket = byExercise.get(match.exercise.id) || [];
    bucket.push(match);
    byExercise.set(match.exercise.id, bucket);
  }

  const rows = [];
  for (const [exerciseId, group] of byExercise) {
    group.sort((a, b) => {
      const sideA = /-side\./i.test(a.video.title) ? 1 : 0;
      const sideB = /-side\./i.test(b.video.title) ? 1 : 0;
      const scoreDelta = b.score - a.score;
      if (Math.abs(scoreDelta) > 0.01) return scoreDelta;
      return sideB - sideA || a.video.title.localeCompare(b.video.title);
    });
    const best = group[0];
    rows.push({
      exercise_id: exerciseId,
      exercise_name: best.exercise.name || best.exercise.nameEn || exerciseId,
      source: best.exercise.source,
      confidence: best.confidence,
      score: best.score.toFixed(3),
      recommended_video: best.video.title,
      drive_file_id: best.video.id,
      drive_url: best.video.href,
      folder: best.video.folder,
      matched_variants: group.length,
      reason: best.reason,
    });
  }
  return rows.sort((a, b) => {
    const conf = { high: 0, medium: 1, low: 2, none: 3 };
    return conf[a.confidence] - conf[b.confidence] || a.exercise_id.localeCompare(b.exercise_id);
  });
}

function main() {
  ensureDir(OUT_DIR);
  const { folders, videos } = listDriveTree(DRIVE_FOLDER_ID);
  const catalog = loadCatalog();
  const matches = matchVideosToCatalog(videos, catalog);
  const recommendations = groupRecommendations(matches);
  const duplicates = duplicateFamilies(catalog);
  const duplicateReview = duplicateEquipmentReview(catalog);

  fs.writeFileSync(
    path.join(OUT_DIR, 'drive-videos.json'),
    JSON.stringify({ rootFolderId: DRIVE_FOLDER_ID, folders, videos }, null, 2),
  );
  fs.writeFileSync(
    path.join(OUT_DIR, 'video-match-details.json'),
    JSON.stringify(matches.map((m) => ({
      video: m.video,
      exercise: m.exercise,
      score: Number(m.score.toFixed(3)),
      confidence: m.confidence,
      reason: m.reason,
    })), null, 2),
  );

  writeCsv('video-recommendations.csv', recommendations, [
    'exercise_id',
    'exercise_name',
    'source',
    'confidence',
    'score',
    'recommended_video',
    'drive_file_id',
    'drive_url',
    'folder',
    'matched_variants',
    'reason',
  ]);
  writeCsv('video-recommendations-high-confidence.csv',
    recommendations.filter((row) => row.confidence === 'high'),
    [
      'exercise_id',
      'exercise_name',
      'source',
      'confidence',
      'score',
      'recommended_video',
      'drive_file_id',
      'drive_url',
      'folder',
      'matched_variants',
      'reason',
    ],
  );
  writeCsv('video-recommendations-review-needed.csv',
    recommendations.filter((row) => row.confidence !== 'high'),
    [
      'exercise_id',
      'exercise_name',
      'source',
      'confidence',
      'score',
      'recommended_video',
      'drive_file_id',
      'drive_url',
      'folder',
      'matched_variants',
      'reason',
    ],
  );
  writeCsv('catalog-duplicate-families.csv', duplicates, [
    'family',
    'count',
    'ids',
    'names',
    'sources',
  ]);
  writeCsv('catalog-duplicate-equipment-review.csv', duplicateReview, [
    'family',
    'count',
    'classification',
    'action',
    'equipment_groups',
    'same_equipment_groups',
    'ids',
    'names',
    'sources',
  ]);
  writeCsv('unmatched-videos.csv',
    matches.filter((m) => !m.exercise).map((m) => ({
      title: m.video.title,
      drive_file_id: m.video.id,
      folder: m.video.folder,
      drive_url: m.video.href,
    })),
    ['title', 'drive_file_id', 'folder', 'drive_url'],
  );

  const summary = [
    '# Video Catalog Audit',
    '',
    `- Drive folders scanned: ${folders.length}`,
    `- Drive videos found: ${videos.length}`,
    `- Catalog exercises considered: ${catalog.length}`,
    `- Recommended exercise video matches: ${recommendations.length}`,
    `- High confidence recommendations: ${recommendations.filter((r) => r.confidence === 'high').length}`,
    `- Medium confidence recommendations: ${recommendations.filter((r) => r.confidence === 'medium').length}`,
    `- Low confidence recommendations: ${recommendations.filter((r) => r.confidence === 'low').length}`,
    `- Unmatched videos: ${matches.filter((m) => !m.exercise).length}`,
    `- Duplicate catalog families: ${duplicates.length}`,
    `- Duplicate families that look like valid equipment variants: ${duplicateReview.filter((r) => r.classification === 'valid_equipment_variants').length}`,
    `- Duplicate families needing same-equipment review: ${duplicateReview.filter((r) => r.classification === 'review_same_equipment_duplicates').length}`,
    `- Duplicate families needing generic/equipment review: ${duplicateReview.filter((r) => r.classification === 'review_generic_or_missing_equipment').length}`,
    '',
    '## Outputs',
    '',
    '- `drive-videos.json`: raw Drive inventory.',
    '- `video-match-details.json`: one best match per video.',
    '- `video-recommendations.csv`: one recommended video per exercise.',
    '- `video-recommendations-high-confidence.csv`: safe first batch candidates.',
    '- `video-recommendations-review-needed.csv`: candidates that need human review.',
    '- `catalog-duplicate-families.csv`: possible duplicate families.',
    '- `catalog-duplicate-equipment-review.csv`: duplicate families classified by equipment.',
    '- `unmatched-videos.csv`: videos with no catalog match.',
    '',
    '## Notes',
    '',
    '- This audit is report-only.',
    '- Use only high-confidence rows automatically.',
    '- Medium/low-confidence rows need human review before backfill.',
    '- Drive URLs should not be used directly in the app. Upload approved files to Firebase Storage and persist those download URLs in `videoUrl`.',
    '',
  ];
  fs.writeFileSync(path.join(OUT_DIR, 'README.md'), `${summary.join('\n')}\n`);

  console.log(summary.slice(0, 10).join('\n'));
}

main();
