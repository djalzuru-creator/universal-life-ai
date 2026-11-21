# Instala la copia nocturna: crea la carpeta, guarda tu cuenta (cifrada, solo
# la puede leer tu usuario de Windows) y programa la copia cada noche a las 3:00.
$ErrorActionPreference = 'Stop'
$Destino = 'D:\Aguilera-Copias'

Write-Host ''
Write-Host '=== Copia de seguridad de la app de la familia ===' -ForegroundColor Magenta
if (-not (Test-Path 'D:\')) {
  Write-Host 'No encuentro el disco D:. Conectalo y vuelve a abrir este instalador.' -ForegroundColor Red
  Read-Host 'Pulsa Enter para salir'
  exit 1
}
New-Item -ItemType Directory -Force -Path $Destino | Out-Null
Copy-Item -Force (Join-Path $PSScriptRoot 'copia.ps1') (Join-Path $Destino 'copia.ps1')

Write-Host 'Escribe el correo y la contrasena con los que entras en la app.'
Write-Host '(Al escribir la contrasena no se ven las letras: es normal. Pulsa Enter al terminar.)'
$correo = (Read-Host 'Correo').Trim()
$clave = Read-Host 'Contrasena' -AsSecureString
if (-not $correo) { Write-Host 'Falta el correo.' -ForegroundColor Red; Read-Host 'Pulsa Enter para salir'; exit 1 }
$cred = New-Object System.Management.Automation.PSCredential ($correo, $clave)
$cred | Export-Clixml (Join-Path $Destino 'cuenta.xml')

$accion = New-ScheduledTaskAction -Execute 'powershell.exe' `
  -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Destino\copia.ps1`" -Destino `"$Destino`""
$cuando = New-ScheduledTaskTrigger -Daily -At 3am
# Si el portatil estaba apagado a las 3, la hace en cuanto se encienda.
$ajustes = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName 'Copia familia Aguilera' -Action $accion -Trigger $cuando `
  -Settings $ajustes -Force | Out-Null

Write-Host 'Haciendo la primera copia ahora...' -ForegroundColor Magenta
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$Destino\copia.ps1" -Destino $Destino
Write-Host ''
if ($LASTEXITCODE -eq 0) {
  Write-Host "Listo. Tus copias estan en $Destino" -ForegroundColor Green
  Write-Host 'Cada noche a las 3:00 se guardaran solas.'
} else {
  Write-Host 'La primera copia ha fallado (mira el mensaje de arriba).' -ForegroundColor Red
  Write-Host 'Haz una foto de esta ventana y mandasela a Claude.'
}
Start-Process explorer.exe $Destino
Read-Host 'Pulsa Enter para cerrar'
