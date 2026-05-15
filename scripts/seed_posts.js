'use strict';

/**
 * scripts/seed_posts.js
 *
 * Seeds 10 sample posts into Firestore (emulator by default).
 * Doc IDs are deterministic: seed_post_001 through seed_post_010.
 *
 * Covers all three privacy levels (public, friends, gym) per REQ-PFM-011.
 *
 * Usage:
 *   FIRESTORE_EMULATOR_HOST=localhost:8080 node scripts/seed_posts.js
 *
 * Or point at production (careful!):
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json node scripts/seed_posts.js
 */

const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

// ---------------------------------------------------------------------------
// Seed data — 10 posts, mix of privacy levels
// ---------------------------------------------------------------------------

const NOW = new Date('2026-01-15T10:00:00Z');

// Author display name / avatar mapping (design §7.3)
// seed_user_001 → Martín L.   (has avatar)
// seed_user_002 → Sofía R.    (has avatar)
// seed_user_003 → Mateo Q.    (null — initials fallback)
// seed_user_004 → Camila P.   (has avatar)
// seed_user_005 → Diego F.    (null — initials fallback)
const AUTHOR_META = {
  seed_user_001: {
    authorDisplayName: 'Martín L.',
    authorAvatarUrl: 'https://images.unsplash.com/photo-1539571696357-5a69c17a67c6?w=80&h=80&fit=crop',
  },
  seed_user_002: {
    authorDisplayName: 'Sofía R.',
    authorAvatarUrl: 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=80&h=80&fit=crop',
  },
  seed_user_003: {
    authorDisplayName: 'Mateo Q.',
    authorAvatarUrl: null,
  },
  seed_user_004: {
    authorDisplayName: 'Camila P.',
    authorAvatarUrl: 'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=80&h=80&fit=crop',
  },
  seed_user_005: {
    authorDisplayName: 'Diego F.',
    authorAvatarUrl: null,
  },
};

const posts = [
  // --- public (4 posts) ---------------------------------------------------
  {
    id: 'seed_post_001',
    authorUid: 'seed_user_001',
    ...AUTHOR_META['seed_user_001'],
    authorGymId: 'seed_gym_001',
    text: 'Acabo de terminar mi primer entrenamiento del año. ¡Vamos!',
    routineTag: null,
    privacy: 'public',
    createdAt: admin.firestore.Timestamp.fromDate(new Date('2026-01-15T08:00:00Z')),
  },
  {
    id: 'seed_post_002',
    authorUid: 'seed_user_002',
    ...AUTHOR_META['seed_user_002'],
    authorGymId: 'seed_gym_001',
    text: 'PR en sentadilla: 120 kg. La constancia da resultados.',
    routineTag: {
      routineId: 'lower-strength',
      routineName: 'Lower Strength',
    },
    privacy: 'public',
    createdAt: admin.firestore.Timestamp.fromDate(new Date('2026-01-15T09:00:00Z')),
  },
  {
    id: 'seed_post_003',
    authorUid: 'seed_user_003',
    ...AUTHOR_META['seed_user_003'],
    authorGymId: 'seed_gym_002',
    text: 'Rutina de cardio completada. 5 km en 22 minutos.',
    routineTag: null,
    privacy: 'public',
    createdAt: admin.firestore.Timestamp.fromDate(new Date('2026-01-14T07:30:00Z')),
  },
  {
    id: 'seed_post_004',
    authorUid: 'seed_user_001',
    ...AUTHOR_META['seed_user_001'],
    authorGymId: 'seed_gym_001',
    text: 'Bench press 100 kg × 5 reps. Progreso sostenido.',
    routineTag: {
      routineId: 'upper-strength',
      routineName: 'Upper Strength',
    },
    privacy: 'public',
    createdAt: admin.firestore.Timestamp.fromDate(new Date('2026-01-13T10:00:00Z')),
  },

  // --- friends (3 posts) --------------------------------------------------
  {
    id: 'seed_post_005',
    authorUid: 'seed_user_002',
    ...AUTHOR_META['seed_user_002'],
    authorGymId: 'seed_gym_001',
    text: 'Entrené con resaca, no me pregunten cómo salió.',
    routineTag: null,
    privacy: 'friends',
    createdAt: admin.firestore.Timestamp.fromDate(new Date('2026-01-12T08:15:00Z')),
  },
  {
    id: 'seed_post_006',
    authorUid: 'seed_user_004',
    ...AUTHOR_META['seed_user_004'],
    authorGymId: 'seed_gym_003',
    text: 'Lesión leve en el hombro. Tomando la semana tranquilo.',
    routineTag: null,
    privacy: 'friends',
    createdAt: admin.firestore.Timestamp.fromDate(new Date('2026-01-11T16:00:00Z')),
  },
  {
    id: 'seed_post_007',
    authorUid: 'seed_user_003',
    ...AUTHOR_META['seed_user_003'],
    authorGymId: 'seed_gym_002',
    text: 'Probé una rutina nueva de hipertrofia. Muy buena.',
    routineTag: {
      routineId: 'hypertrophy-full',
      routineName: 'Full Body Hypertrophy',
    },
    privacy: 'friends',
    createdAt: admin.firestore.Timestamp.fromDate(new Date('2026-01-10T11:00:00Z')),
  },

  // --- gym (3 posts) -------------------------------------------------------
  {
    id: 'seed_post_008',
    authorUid: 'seed_user_001',
    ...AUTHOR_META['seed_user_001'],
    authorGymId: 'seed_gym_001',
    text: 'Los viernes a las 7am somos cuatro gatos. Mejor horario.',
    routineTag: null,
    privacy: 'gym',
    createdAt: admin.firestore.Timestamp.fromDate(new Date('2026-01-10T07:10:00Z')),
  },
  {
    id: 'seed_post_009',
    authorUid: 'seed_user_005',
    ...AUTHOR_META['seed_user_005'],
    authorGymId: 'seed_gym_001',
    text: 'Clase de spinning con el profe Martín. Brutal como siempre.',
    routineTag: null,
    privacy: 'gym',
    createdAt: admin.firestore.Timestamp.fromDate(new Date('2026-01-09T18:00:00Z')),
  },
  {
    id: 'seed_post_010',
    authorUid: 'seed_user_002',
    ...AUTHOR_META['seed_user_002'],
    authorGymId: 'seed_gym_001',
    text: '¿Alguien más probó el nuevo rack de mancuernas? Una joya.',
    routineTag: null,
    privacy: 'gym',
    createdAt: admin.firestore.Timestamp.fromDate(new Date('2026-01-08T09:30:00Z')),
  },
];

// ---------------------------------------------------------------------------
// Seeder
// ---------------------------------------------------------------------------

async function seedPosts() {
  console.log(`Seeding ${posts.length} posts...`);
  for (const post of posts) {
    const { id, ...data } = post;
    await db.collection('posts').doc(id).set(data);
    console.log(`  Seeded: ${id} (privacy=${data.privacy})`);
  }
  console.log(`Done. ${posts.length} posts written.`);
}

// ---------------------------------------------------------------------------
// Entrypoint
// ---------------------------------------------------------------------------

seedPosts().catch((err) => {
  console.error('Seed failed:', err);
  process.exit(1);
});
