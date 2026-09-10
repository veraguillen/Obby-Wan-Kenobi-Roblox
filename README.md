# Ninjas vs. Vaqueros: Retro Obbie Boss Royale

Proyecto de Roblox Studio gestionado con [Rojo](https://github.com/rojo-rbx/rojo) 7.7.0. Obbie competitivo 8/16-bit en el que dos equipos (Ninjas vs. Vaqueros) corren en paralelo por 5 mini-stages idénticos hasta enfrentar a un jefe final compartido.

El diseño completo está en [`GDD_Ninjas_vs_Vaqueros_Roblox.pdf`](./GDD_Ninjas_vs_Vaqueros_Roblox.pdf). Este README resume qué parte de ese diseño ya existe en el proyecto y qué falta.

## Getting Started

```bash
rojo build -o "Semillero Ninjas & vaqueros.rbxlx"
```

Abrir `Semillero Ninjas & vaqueros.rbxlx` en Roblox Studio y correr:

```bash
rojo serve
```

Más info en [la documentación de Rojo](https://rojo.space/docs).

## Visión del juego (GDD)

- **Competencia en paralelo**: dos pistas físicamente idénticas (Track_A = Ninjas, Track_B = Vaqueros), sin colisión entre equipos, con HUD que muestra el progreso del rival en vivo.
- **5 mini-stages temáticos** + jefe final ("El Shogun-Sheriff"): Pueblo del Dojo → Minas de Neón → Tren del Cañón → Valle de Sombras → Núcleo del Shogun-Sheriff, cada uno con obstáculos y objetivo propios (barriles, plataformas que desaparecen, cintas transportadoras, botones cooperativos, piso destruible).
- **Vidas y cooperación**: 5 vidas por partida, respawn en el checkpoint, revivir/donar vidas entre compañeros, escudos comprables.
- **Economía RPG**: NPC Host con diálogo tipo máquina de escribir que vende armas, consumibles y sabotajes (dinamita, shurikens que ciegan, terremotos) contra el equipo rival.
- **Jefe final**: barra de escudo + barra de vida, patrones de ataque (ondas de choque, proyectiles, minions), gana el equipo que lo derrote primero.
- **Persistencia (DataStoreService)**: monedas, skins/sombreros, victorias totales y récords guardados entre sesiones; vidas/monedas de la partida en memoria local.
- **Recompensas**: botín de carrera para el equipo ganador, tienda global de cosméticos, ítem exclusivo de avatar por rachas de victorias.

## Estado actual de la implementación

### Construido

- **Lobby y matchmaking** (`RoomManager.server.luau`): portales `Track_A`/`Track_B` (10 en total, con datos de `ServerIndex` en cada portal aunque la lógica de matchmaking todavía no los usa — hoy es una sola cola global por equipo), solo arranca cuando ambos equipos están balanceados, cuenta regresiva de 10s con barreras de inicio, HUD de estado (`RoomStatusClient.client.luau` + `RoomStatusEvent`).
- **Datos de sesión por jugador** (`PlayerDataModule.luau`): vidas (máx. 5), stage actual, checkpoint, pista asignada, y estado de derribo/espera de checkpoint (`IsDowned`, `DownedUntil`, `IsWaitingForCheckpoint`) — autoridad exclusiva del servidor, con el `Attribute` replicado sincronizado en los mismos puntos donde se actualiza el dato interno.
- **Checkpoints y progreso por pista** (`CheckpointSystem.server.luau`): detección de `Checkpoint_Pad` por stage, avance automático a la siguiente plataforma, teletransporte a la arena del jefe al completar el Stage 5, señal `CheckpointReached` (server-only) para que otros sistemas reaccionen al progreso del equipo.
- **Pérdida de vidas y respawn** (`LifeLossModule.luau`): caída al vacío o muerte real del `Humanoid` restan una vida y reaparecen al jugador en su último checkpoint (o en el Stage 1 / Lobby si no tiene pista asignada, o resetean el progreso si se quedó sin vidas); extraído a un módulo aparte para que el sistema de derribo/rescate reuse exactamente la misma lógica.
- **HUD de progreso rival** (`RivalCheckpointClient.client.luau`): muestra en pantalla el checkpoint alcanzado por el equipo contrario en tiempo real.
- **Sabotaje de dinamita** (`DynamiteSabotageSystem.server.luau`, `DynamiteState.luau`, `DynamiteButtonClient.client.luau`): el equipo Vaquero destruye temporalmente la plataforma equivalente del equipo Ninja; cargas por checkpoint alcanzado, cooldown de equipo, inmunidad post-respawn, mensaje en pantalla para cada resultado (éxito, rechazo por track/cargas, objetivo inmune o ya destruido).
- **Jefe — versión MVP** (`BossFightSystem.server.luau`): 1 fase, 1 barra de vida, 1 ataque (onda expansiva) — de las 3 fases planeadas en el diseño, solo existe esta primera.
- **Derribo y rescate** (`RescueSystem.luau`, `RescueState.luau`): el golpe del jefe derriba (no mata) 12-15s en vez de empujar fuera del área. Un compañero del mismo equipo puede reanimar sosteniendo un `ProximityPrompt` (con validación de equipo y mensaje de rechazo si corresponde); si nadie llega a tiempo, se gasta automáticamente una cuerda de equipo (3 por ronda) para respawnear en el último checkpoint restando 1 vida; sin cuerdas disponibles, el jugador espera al próximo checkpoint de su equipo, con un timeout de seguridad de 30s para no quedar congelado si es el único jugador de su equipo.
- **Greybox de las 5 stages en ambas pistas** (`default.project.json`): plataforma base, `Checkpoint_Pad`, escalera de prueba genérica y placeholder de `HostNPC` — sin geometría, obstáculos ni temática visual definitivos todavía.
- **Boss_Arena**: piso y plataformas de entrada creadas, con el jefe MVP funcionando arriba.
- Utilidad de debug (`DoubleJumpDebug.client.luau`) para probar el recorrido de las pistas sin depender del movimiento final.

### Falta por construir

- Obstáculos y arte temático real por stage (barriles, cactus, plataformas que desaparecen, sierras, cintas transportadoras, botones cooperativos, piso destruible) — hoy todas las stages son bloques grises intercambiables.
- NPC Host funcional: diálogo con efecto typewriter, tienda de armas/consumibles/escudos/sabotajes.
- Economía y monedas: recolectables en pista, recompensas por stage, botín de carrera.
- Persistencia con `DataStoreService` (monedas, skins, victorias, récords) — todo el estado actual vive solo en memoria del servidor.
- Tienda global de cosméticos e ítem exclusivo de avatar.
- Fases 2 y 3 del jefe "El Shogun-Sheriff" (hoy solo existe la fase 1: 1 barra de vida, 1 ataque) — patrones de ataque adicionales, barra de escudo, transiciones de fase, condición de victoria final.
- HUD de marcador en vivo: vidas propias, vidas del equipo rival, y vida del jefe visible para ambos equipos — hoy solo existe el HUD de checkpoint del rival (`RivalCheckpointClient`) y el de estado de matchmaking.
- Retirar los bloques de debug (`ALLOW_SOLO_DEBUG_START` en `RoomManager.server.luau`, `DoubleJumpDebug.client.luau`) una vez el diseño final de movimiento/parkour y las pruebas multijugador estén cerrados.
