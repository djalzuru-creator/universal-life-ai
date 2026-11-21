// Aguilucho IA: propone ropa y recetas con Google Gemini (capa gratuita).
// La clave GEMINI_API_KEY vive solo en los secretos de Supabase, nunca en la app.
// Los datos se leen con la sesión de quien llama, así que las reglas de permisos
// (RLS) siguen mandando: nadie ve ropa ni despensa que no le toca.

const MODEL = 'gemini-flash-latest';
const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const clean = (v: unknown, max: number) =>
  String(v ?? '').replace(/[\u0000-\u001f]/g, ' ').trim().slice(0, max);
const num = (v: unknown, min: number, max: number) => {
  const n = Number(v);
  return Number.isFinite(n) ? Math.min(max, Math.max(min, Math.round(n))) : 0;
};

async function rest(req: Request, path: string) {
  const url = Deno.env.get('SUPABASE_URL')!;
  const apikey = req.headers.get('apikey') ?? Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  const r = await fetch(`${url}/rest/v1/${path}`, {
    headers: { apikey, Authorization: req.headers.get('Authorization') ?? '' },
  });
  if (!r.ok) throw new Error(`datos ${r.status}`);
  return (await r.json()) as Record<string, unknown>[];
}

async function gemini(prompt: string) {
  const key = Deno.env.get('GEMINI_API_KEY');
  if (!key) throw new Error('sin_clave');
  const r = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-goog-api-key': key },
      body: JSON.stringify({
        contents: [{ role: 'user', parts: [{ text: prompt }] }],
        generationConfig: { responseMimeType: 'application/json', temperature: 0.8 },
      }),
    },
  );
  if (r.status === 429) throw new Error('limite');
  if (!r.ok) throw new Error(`gemini ${r.status}`);
  const data = await r.json();
  const text = data?.candidates?.[0]?.content?.parts?.[0]?.text ?? '{}';
  return JSON.parse(text);
}

async function outfit(req: Request, body: Record<string, unknown>) {
  const memberId = String(body.member_id ?? '');
  if (!uuid.test(memberId)) return json({ error: 'datos' }, 400);
  const garments = await rest(
    req,
    `garments?member_id=eq.${memberId}&select=id,name,category,color,seasons,styles,warmth&limit=200`,
  );
  if (garments.length === 0) return json({ error: 'sin_ropa' }, 400);
  const w = (body.weather ?? {}) as Record<string, unknown>;
  const list = garments
    .map((g) =>
      `- id=${g.id} | ${clean(g.name, 80)} | ${g.category} | color ${clean(g.color, 30)} | ` +
      `abrigo ${g.warmth}/3 | estilos ${(g.styles as string[]).join(',') || '-'}`,
    )
    .join('\n');
  const prompt = `Eres Aguilucho, el asistente de moda de una familia. Habla en español, cercano y breve.
Elige UN conjunto solo con prendas de esta lista (usa sus id exactos):
${list}

Tiempo hoy: ${num(w.current, -30, 50)} grados (sensación ${num(w.feels_like, -30, 50)}), mínima ${num(w.min, -30, 50)}, máxima ${num(w.max, -30, 50)}, lluvia ${num(w.rain, 0, 100)}%.
Estación: ${clean(body.season, 10)}. Ocasión: ${clean(body.occasion, 40) || 'día a día'}.
Normas: una prenda de arriba y una de abajo (o un vestido), calzado si hay, abrigo si hace fresco. Colores que combinen.
Responde SOLO este JSON: {"garment_ids": ["id", ...], "why": "2 o 3 frases explicando la elección", "tip": "un consejo corto"}`;
  const out = await gemini(prompt);
  const valid = new Set(garments.map((g) => g.id));
  const ids = (Array.isArray(out.garment_ids) ? out.garment_ids : [])
    .map(String)
    .filter((id: string) => valid.has(id))
    .slice(0, 8);
  return json({ garment_ids: ids, why: clean(out.why, 600), tip: clean(out.tip, 300) });
}

async function recipes(req: Request, body: Record<string, unknown>) {
  const hid = String(body.household_id ?? '');
  if (!uuid.test(hid)) return json({ error: 'datos' }, 400);
  const items = await rest(
    req,
    `pantry_items?household_id=eq.${hid}&quantity=gt.0&select=name,quantity,unit,expires_on&limit=200`,
  );
  if (items.length === 0) return json({ error: 'sin_despensa' }, 400);
  const list = items
    .map((i) =>
      `- ${clean(i.name, 120)} (${i.quantity} ${i.unit}${i.expires_on ? `, caduca ${i.expires_on}` : ''})`,
    )
    .join('\n');
  const prompt = `Eres Aguilucho, el cocinero de una familia española. Hoy es ${new Date().toISOString().slice(0, 10)}.
Despensa:
${list}

Peticion: ${clean(body.wish, 80) || 'comida casera y sencilla'}.
Propón 3 recetas que usen sobre todo lo de la despensa, priorizando lo que caduca antes. Puedes dar por hecho sal, aceite, agua y especias básicas.
Responde SOLO este JSON: {"recipes": [{"name": "", "minutes": 30, "ingredients": ["cantidad y nombre"], "missing": ["lo que falta comprar"], "steps": ["paso"]}]}`;
  const out = await gemini(prompt);
  const strs = (v: unknown, n: number, max: number) =>
    (Array.isArray(v) ? v : []).slice(0, n).map((s) => clean(s, max)).filter(Boolean);
  const list2 = (Array.isArray(out.recipes) ? out.recipes : []).slice(0, 3).map(
    (r: Record<string, unknown>) => ({
      name: clean(r.name, 80),
      minutes: num(r.minutes, 5, 300),
      ingredients: strs(r.ingredients, 20, 120),
      missing: strs(r.missing, 10, 80),
      steps: strs(r.steps, 12, 400),
    }),
  );
  return json({ recipes: list2 });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ error: 'metodo' }, 405);
  try {
    const body = await req.json();
    if (body.mode === 'outfit') return await outfit(req, body);
    if (body.mode === 'recipes') return await recipes(req, body);
    return json({ error: 'modo' }, 400);
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    const code = msg === 'sin_clave' || msg === 'limite' ? msg : 'fallo';
    console.error(msg);
    return json({ error: code }, code === 'limite' ? 429 : 500);
  }
});
