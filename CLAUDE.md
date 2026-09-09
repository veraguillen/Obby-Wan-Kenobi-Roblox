# Ninjas vs. Vaqueros — guía del proyecto

Proyecto de Roblox Studio gestionado con [Rojo](https://rojo.space/) 7.7.0. Diseño completo en `GDD_Ninjas_vs_Vaqueros_Roblox.pdf`; estado de implementación resumido en `README.md`.

## Arquitectura Rojo (mapeo carpeta → Roblox)

Definido en `default.project.json`:

| Carpeta          | Ubicación en Roblox                              |
|-------------------|---------------------------------------------------|
| `src/server`       | `ServerScriptService.Server`                       |
| `src/client`       | `StarterPlayer.StarterPlayerScripts.Client`        |
| `src/modules`      | `ReplicatedStorage.Modules`                        |
| `src/shared`       | `ReplicatedStorage.Shared`                         |

`ReplicatedStorage.RemoteEvents` (carpeta) no tiene `$path` — sus 5 eventos están declarados directamente en `default.project.json`, no en `src/`.

## RemoteEvents existentes

Todos viven en `ReplicatedStorage.RemoteEvents`:

- **`RoomStatusEvent`** — HUD de estado de matchmaking/lobby (`RoomManager.server.luau` → `RoomStatusClient.client.luau`).
- **`CheckpointProgressEvent`** — progreso de checkpoint por equipo; alimenta el HUD del rival (`CheckpointSystem.server.luau` → `RivalCheckpointClient.client.luau`).
- **`DynamiteActivateEvent`** — el cliente pide detonar dinamita (`DynamiteButtonClient.client.luau` → `DynamiteSabotageSystem.server.luau`).
- **`DynamiteStatusEvent`** — estado de cargas/cooldown de dinamita, servidor → cliente.
- **`DynamiteMessageEvent`** — mensajes puntuales de dinamita (ej. "Objetivo ya destruido"), servidor → cliente.

## Sistemas ya construidos

Base: sección "Estado actual de la implementación" de `README.md`, actualizada con lo agregado en sesiones recientes.

- **Lobby y matchmaking** (`RoomManager.server.luau`): portales `Track_A`/`Track_B` (10 en total vía `ServerIndex`), colas por equipo, arranque solo con equipos balanceados, countdown de 10s con barreras de inicio, dispara `RoundStarted` (ver abajo) al iniciar la cuenta regresiva.
- **Selección de pista y fix de spawn** (`TrackSelectionSystem.server.luau`): fuerza el spawn en `LobbySpawn` mientras el jugador no tenga `AssignedTrack` asignado (evita aparecer en una stage sin pista). `RoomManager` es el único responsable de asignar la pista, vía `PlayerDataModule.SetAssignedTrack` + atributo `player:SetAttribute("AssignedTrack", ...)`, una vez que arranca el countdown.
- **Datos de sesión por jugador** (`PlayerDataModule.luau`): vidas (máx. 5), stage actual, checkpoint, pista asignada — autoridad exclusiva del servidor, copias defensivas para el cliente.
- **Checkpoints y progreso por pista** (`CheckpointSystem.server.luau`): detección de `Checkpoint_Pad` por stage, avance automático, teletransporte a `Boss_Arena` al completar Stage 5, dispara `CheckpointProgressEvent` y setea `LastRespawnTime` (usado por el sistema de dinamita para inmunidad post-respawn).
- **HUD del rival** (`RivalCheckpointClient.client.luau`): muestra en pantalla el checkpoint del equipo contrario en tiempo real, escuchando `CheckpointProgressEvent`; solo visible una vez que el jugador alcanzó su primer checkpoint (`HasReachedFirstCheckpoint`).
- **Sabotaje con dinamita** (`DynamiteSabotageSystem.server.luau` + `DynamiteState.luau` + `DynamiteButtonClient.client.luau`): el equipo Vaquero (`Track_B`) destruye temporalmente la plataforma de stage equivalente en `Track_A`. Cargas por checkpoint alcanzado, cooldown de equipo, inmunidad post-respawn (`LastRespawnTime`), se resetea al inicio de cada ronda vía `RoundStarted`.
- **Jefe final — versión MVP** (`BossFightSystem.server.luau`): 1 fase, 1 barra de vida (`BOSS_MAX_HEALTH = 100`), 1 ataque (onda expansiva de empuje). Sin muros perimetrales en `Boss_Arena`: un empujón fuerte puede sacar a un jugador al vacío, y el respawn ya lo maneja `CheckpointSystem.server.luau` sin lógica adicional. Se resetea al inicio de cada ronda vía `RoundStarted`.
- **Pérdida de vidas y respawn**: caída al vacío o muerte del `Humanoid` restan una vida y reaparecen al jugador en su último checkpoint (o Stage 1 / Lobby si no tiene pista); sin vidas, se resetea el progreso de la pista.
- **Greybox de las 5 stages en ambas pistas** (`default.project.json`): plataforma base, `Checkpoint_Pad`, escalera de prueba, placeholder de `HostNPC` — sin geometría/temática definitiva.
- **Debug**: `DoubleJumpDebug.client.luau`, flag `ALLOW_SOLO_DEBUG_START` (pendientes de retirar antes de release).

Lo que falta por construir sigue documentado en `README.md` (no se repite acá para evitar que quede desactualizado en dos lugares).

## Convenciones de nombres

- Scripts de servidor: `*.server.luau` (en `src/server`).
- Scripts de cliente: `*.client.luau` (en `src/client`).
- Módulos (`ModuleScript`, sin sufijo `.server`/`.client`): PascalCase, ej. `PlayerDataModule.luau`, `DynamiteState.luau`.

## Archivos que requieren confirmación explícita antes de tocar

- **`default.project.json`** — scaffolding de las 10 stages (5 por pista × 2 pistas). Es fácil romper otra stage por error al editar una sola; confirmar antes de modificar estructura, no solo agregar contenido dentro de una `Stage_N` existente.
- **`Semillero Ninjas & vaqueros.rbxlx`** — nunca se edita a mano. Se regenera con `rojo build -o "Semillero Ninjas & vaqueros.rbxlx"`. Cualquier cambio manual se pierde en el próximo build.

## Nota: `RoundStarted` sí existe (pero no es un RemoteEvent)

`RoundStarted` **no** está en `ReplicatedStorage.RemoteEvents` ni en `default.project.json`. Es un `BindableEvent` creado en tiempo de ejecución dentro de `RoomManager.server.luau`:

```lua
local RoundStarted = Instance.new("BindableEvent")
RoundStarted.Name = "RoundStarted"
RoundStarted.Parent = script
```

Se dispara (`RoundStarted:Fire()`) cuando arranca el countdown de la ronda. Otros scripts de servidor lo consumen vía `RoomManagerScript:WaitForChild("RoundStarted")` para resetear su propio estado sin acoplarse a `RoomManager`:

- `DynamiteSabotageSystem.server.luau` → resetea cargas de dinamita (`DynamiteState.ResetCharges()`).
- `BossFightSystem.server.luau` → resetea el estado del jefe.

Es exclusivamente server-side (BindableEvent, no RemoteEvent) — no está pensado para ser escuchado desde el cliente. Antes de asumir su forma o comportamiento en una sesión futura, verificar contra `RoomManager.server.luau` porque puede evolucionar.

## Regla de trabajo: consultas sobre stages/checkpoints

Para preguntas sobre la estructura de una stage o checkpoint puntual en `default.project.json` (1350 líneas), usar `Grep` acotado a la sección `Stage_N` correspondiente en lugar de leer el archivo completo. Ejemplo:

```
Grep pattern:"\"Stage_3\": \{" -A 80 -- default.project.json
```
