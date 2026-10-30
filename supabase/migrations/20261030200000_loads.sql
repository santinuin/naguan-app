-- Cargas: el peso con el que se hace un ejercicio (barra, kettlebell, lastre).
-- Ver docs/limitaciones-del-modelo.md («Cargas») y docs/modelo-de-datos.md.
--
-- Solo agrega: las Fraguas templadas antes quedan con load_kg en null (sin
-- carga) y siguen contando igual que siempre.

-- Si el ejercicio se hace con carga: la app pide el peso. En los demás el peso
-- es opcional (lastre: dominadas o fondos con una mochila). Los importadores lo
-- escriben al cargar el catálogo (backend/seed/ejercicios_con_carga.txt para
-- los del índice, «| carga» en los catálogos de cada plan); este update lo
-- pone en las bases que ya existen. En una base nueva corre antes de los
-- seeds, con exercise vacío, y no hace nada.
alter table exercise add column loaded boolean not null default false;

update exercise set loaded = true
where slug in (
  -- Índice de Mammoth Hunters.
  'abrazos-al-sol', 'arrancada-en-dos', 'caminata-del-grangero',
  'caminata-del-granjero', 'cargada-a-hombro', 'cargada-completa-con-kettlebell',
  'clean', 'cohete-con-carga', 'cohete-con-peso', 'crol',
  'desplante-adelante-con-peso', 'desplante-atras-con-peso',
  'desplante-lateral-con-peso', 'el-puente-con-carga',
  'el-puente-isometrico-con-carga', 'espalda', 'hip-thrust-con-carga',
  'hombro-a-hombro', 'lanzada-adelante', 'levantamiento-turco',
  'levantamiento-turco-con-peso', 'media-cargada', 'molino', 'molino-con-peso',
  'paladas', 'pendulo', 'pendulo-americano', 'peso-muerto',
  'peso-muerto-a-una-pierna-con-kettlebell', 'press', 'push-press', 'remo',
  'sentada-con-peso', 'sentadilla-bulgara-con-peso', 'sentadilla-con-peso',
  'sentadilla-con-peso-frontal', 'sentadilla-con-salto-con-carga',
  'squat-con-carga', 'step-up-con-peso', 'thruster-con-kettlebell',
  'zancada-con-salto-con-peso', 'zancadas-oh-con-peso',
  -- Efecto Kettlebell.
  'swing', 'swing-a-una-mano', 'power-swing', 'sentadilla-en-rack',
  'peso-muerto-maleta', 'peso-muerto-sumo', 'peso-muerto-con-remo-alto',
  'dead-clean', 'press-en-el-suelo', 'high-pull', 'snatch', 'dead-snatch',
  'renegade-row', 'russian-twist', 'around-the-world', 'el-ocho', 'halo',
  'around-the-world-y-ocho', 'clean-y-press', 'clean-y-push-press',
  'burpee-clean-y-press',
  -- Barra Libre.
  'sentadilla-con-barra', 'sentadilla-frontal-con-barra', 'press-de-banca',
  'press-militar', 'peso-muerto-con-barra', 'peso-muerto-rumano',
  'clean-con-barra', 'push-press-con-barra', 'remo-con-barra', 'press-jabalina',
  'encogimiento-con-barra', 'sit-up-con-barra', 'curl-de-biceps-con-barra',
  'curl-invertido-con-barra', 'desplante-con-barra',
  'elevacion-de-talones-con-barra'
);

-- El peso de cada serie, en kilos (hasta 999,99; de a 0,25 alcanza para los
-- discos de 1,25). Null: sin carga. Es por serie, no por Fragua: en las
-- series de aproximación el peso sube de una a otra.
alter table workout_item add column load_kg numeric(5, 2) check (load_kg > 0);
