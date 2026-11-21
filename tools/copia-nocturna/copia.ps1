# Aguilera Valencia - copia de seguridad nocturna de la app familiar.
# Guarda en la carpeta de destino:
#   <persona>\Armario\...                  fotos de su ropa
#   <persona>\Fotos personales\<album>\... fotos que subio esa persona
#   Datos\<fecha>\*.json    todos los datos (se guardan los ultimos 30 dias)
#   registro.txt            lo que hizo cada noche
param([string]$Destino = $PSScriptRoot)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Url = 'https://vbiujgaljwvlseqkqwhb.supabase.co'
$Key = 'sb_publishable_-v0BRkGJMbAhVTgFUi6HdA__kMLUKf8'
$Log = Join-Path $Destino 'registro.txt'

function Write-Log($msg) {
  $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm')  $msg"
  Add-Content -Path $Log -Value $line -Encoding UTF8
  Write-Host $line
}

function Get-SafeName([string]$s) {
  if (-not $s) { return 'sin nombre' }
  $t = ($s -replace '[\\/:*?"<>|]', '' -replace '\s+', ' ').Trim()
  if (-not $t) { return 'sin nombre' }
  if ($t.Length -gt 60) { $t = $t.Substring(0, 60) }
  return $t
}

function Get-Ext([string]$path) {
  $i = $path.LastIndexOf('.')
  if ($i -lt 0) { return 'jpg' }
  return $path.Substring($i + 1)
}

try {
  $cred = Import-Clixml (Join-Path $Destino 'cuenta.xml')
  $email = $cred.UserName
  $pass = $cred.GetNetworkCredential().Password

  # El cuerpo se manda en UTF-8 (PowerShell 5 usa otra codificacion y fallan tildes o la n).
  $body = [Text.Encoding]::UTF8.GetBytes((@{ email = $email.Trim(); password = $pass } | ConvertTo-Json -Compress))
  try {
    $login = Invoke-RestMethod -Method Post -Uri "$Url/auth/v1/token?grant_type=password" `
      -Headers @{ apikey = $Key } -ContentType 'application/json; charset=utf-8' -Body $body
  } catch {
    $detalle = ''
    try {
      $r = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream())
      $detalle = $r.ReadToEnd()
    } catch {}
    if ($detalle -match 'invalid_credentials|Invalid login') {
      throw 'Correo o contrasena incorrectos. Vuelve a abrir instalar.bat y escribelos otra vez.'
    }
    if ($detalle -match 'email_not_confirmed') {
      throw 'Ese correo aun no esta confirmado. Confirmalo desde el email de bienvenida.'
    }
    throw "No se pudo entrar con tu cuenta. $detalle"
  }
  $H = @{ apikey = $Key; Authorization = "Bearer $($login.access_token)" }

  function Get-Rows([string]$table, [string]$filter) {
    try {
      return @(Invoke-RestMethod -Uri "$Url/rest/v1/$($table)?select=*&$filter" -Headers $H)
    } catch {
      return @()   # modulo sin cargar o sin permiso
    }
  }

  $hogares = Get-Rows 'households' 'order=created_at'
  if ($hogares.Count -eq 0) { throw 'Esta cuenta no pertenece a ningun hogar.' }

  $hoy = Get-Date -Format 'yyyy-MM-dd'
  $nuevas = 0
  foreach ($h in $hogares) {
    $hid = $h.id
    $datos = Join-Path $Destino "Datos\$hoy"
    if ($hogares.Count -gt 1) { $datos = Join-Path $datos (Get-SafeName $h.name) }
    New-Item -ItemType Directory -Force -Path $datos | Out-Null

    $tablas = 'members','pantry_items','shopping_items','expenses','budget_limits',
              'events','garments','outfits','albums','photos'
    $t = @{}
    $h | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $datos 'households.json') -Encoding UTF8
    foreach ($tabla in $tablas) {
      $t[$tabla] = Get-Rows $tabla "household_id=eq.$hid"
      ConvertTo-Json -InputObject $t[$tabla] -Depth 10 |
        Set-Content -Path (Join-Path $datos "$tabla.json") -Encoding UTF8
    }

    $personas = @{}
    $porUsuario = @{}
    foreach ($m in $t['members']) {
      $personas[$m.id] = Get-SafeName $m.display_name
      if ($m.user_id) { $porUsuario[$m.user_id] = Get-SafeName $m.display_name }
    }
    $albumes = @{}
    foreach ($a in $t['albums']) { $albumes[$a.id] = Get-SafeName $a.name }

    $copiar = @()
    foreach ($g in $t['garments']) {
      if (-not $g.photo_path) { continue }
      $quien = $personas[$g.member_id]; if (-not $quien) { $quien = 'Otros' }
      $nombre = "$(Get-SafeName $g.name) - $($g.id.Substring(0, 8)).$(Get-Ext $g.photo_path)"
      $copiar += ,@('wardrobe', $g.photo_path, (Join-Path $Destino "$quien\Armario\$nombre"))
    }
    foreach ($p in $t['photos']) {
      $album = $albumes[$p.album_id]; if (-not $album) { $album = 'Sin album' }
      $quien = $porUsuario[$p.created_by]; if (-not $quien) { $quien = 'Familia' }
      $titulo = $p.taken_on; if ($p.caption) { $titulo = "$titulo $($p.caption)" }
      $nombre = "$(Get-SafeName $titulo) - $($p.id.Substring(0, 8)).$(Get-Ext $p.path)"
      $copiar += ,@('family-photos', $p.path, (Join-Path $Destino "$quien\Fotos personales\$album\$nombre"))
    }

    foreach ($c in $copiar) {
      $bucket, $ruta, $archivo = $c
      if (Test-Path -LiteralPath $archivo) { continue }   # ya estaba copiada
      New-Item -ItemType Directory -Force -Path (Split-Path $archivo) | Out-Null
      try {
        Invoke-WebRequest -UseBasicParsing -Uri "$Url/storage/v1/object/authenticated/$bucket/$ruta" `
          -Headers $H -OutFile $archivo
        $nuevas++
      } catch {
        Write-Log "No se pudo copiar $ruta"
      }
    }
  }

  # Solo se guardan los datos de los ultimos 30 dias.
  Get-ChildItem (Join-Path $Destino 'Datos') -Directory |
    Sort-Object Name -Descending | Select-Object -Skip 30 |
    Remove-Item -Recurse -Force

  Write-Log "Copia hecha. Fotos nuevas: $nuevas."
} catch {
  Write-Log "ERROR: $($_.Exception.Message)"
  exit 1
}
