# Universal Life AI

La app de tu hogar: despensa, compra, presupuesto y recetas para toda la familia, con un administrador que decide qué puede ver y hacer cada miembro.

Uso familiar y gratuito. Todo funciona con planes gratuitos (Flutter, Supabase, GitHub y la capa gratuita de la IA). No se publica en tiendas de pago: en Android se instala con un APK y el resto de la familia la usa desde el navegador.

## Qué hay ahora (fase 1: base)

- Cuentas con correo y contraseña (Supabase Auth).
- Hogares con un administrador. El administrador invita a la familia con un código de 8 caracteres que caduca en 7 días.
- Perfiles de adulto, adolescente, niño e invitado, con permisos por módulo: ver, crear, editar, eliminar y aprobar.
- Panel del administrador: miembros, cambiar perfil, suspender, eliminar, invitaciones y registro de cambios.
- Seguridad en la base de datos con Row Level Security: aunque alguien modifique la app, solo ve lo que su perfil permite.

## Despensa

- Productos por ubicación (nevera, congelador, despensa, otros), con cantidad, caducidad y precio.
- Añadir escaneando el código de barras con la cámara: el nombre, la marca y la foto se rellenan solos desde [Open Food Facts](https://world.openfoodfacts.org) (gratis).
- Lo que caduca en 3 días o menos aparece primero y en color, con un aviso arriba.
- Botón para "gastar uno" y sincronización en tiempo real entre toda la familia.
- Cada perfil solo ve, añade, edita o borra lo que su permiso de "Despensa" le deja.

## Armario

- Un armario por persona, con fotos desde la cámara o la galería (almacenamiento privado de Supabase).
- Cada prenda guarda tipo, color, estaciones, cuánto abriga y estilo. Se puede compartir con la familia.
- **Hoy**: propuesta de ropa según el tiempo de la ciudad del hogar ([Open-Meteo](https://open-meteo.com), gratis y sin clave), con avisos de lluvia y de cambio de temperatura.
- **Conjuntos**: crear, guardar y marcar favoritos.
- Cada uno ve y edita solo su armario; el administrador ve el de toda la familia. Las prendas compartidas las ven todos.

Lista de la compra, Presupuesto y Recetas aparecen en el panel como "Próximamente".

## Puesta en marcha

### 1. Crear el proyecto de Supabase (gratis)

1. Entra en [supabase.com](https://supabase.com) y crea un proyecto nuevo (plan Free).
2. En **SQL Editor**, pega y ejecuta, en orden, cada archivo de `supabase/migrations/`.
3. En **Project Settings → API Keys**, copia la URL del proyecto y la **publishable key**. Nunca uses la `secret` / `service_role` key en la app.

### 2. Configurar la app

```bash
cp config/dev.example.json config/dev.json
# Rellena SUPABASE_URL y SUPABASE_PUBLISHABLE_KEY en config/dev.json
```

`config/dev.json` está en `.gitignore` y no se sube al repositorio.

### 3. Ejecutar

```bash
flutter pub get
flutter run -d chrome --dart-define-from-file=config/dev.json   # navegador
flutter run --dart-define-from-file=config/dev.json             # móvil Android conectado
```

### 4. Generar el APK para Android

```bash
flutter build apk --release --dart-define-from-file=config/dev.json
# El archivo queda en build/app/outputs/flutter-apk/app-release.apk
```

## Estructura

```
lib/
  core/                  configuración, tema y rutas
  features/
    auth/                inicio de sesión y registro
    household/
      data/              modelos, acceso a Supabase y providers (Riverpod)
      ui/                selector de hogar, panel, administración y permisos
supabase/
  migrations/            esquema, funciones y políticas RLS
  tests/                 pruebas de seguridad de la base de datos
test/                    pruebas de la app
```

Tecnología: Flutter 3.47, Material 3, Riverpod, GoRouter y Supabase.

## Pruebas

```bash
flutter analyze
flutter test
DB_URL=postgres://postgres@localhost/postgres supabase/tests/run.sh   # requiere PostgreSQL 16 local
```

Las pruebas de base de datos comprueban, entre otras cosas, que un desconocido no ve nada, que un adolescente no puede subirse permisos, que un perfil suspendido pierde el acceso y que el administrador no puede quedarse sin acceso.

## Próximos pasos

1. Lista de la compra compartida en tiempo real.
2. Presupuesto del hogar.
3. Recetas con IA gratuita usando lo que hay en la despensa.
