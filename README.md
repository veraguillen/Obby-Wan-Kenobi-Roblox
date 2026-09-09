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

- **Lobby y matchmaking** (`RoomManager.server.luau`): portales `Track_A`/`Track_B` (10 en total, multi-sala vía `ServerIndex`), colas por equipo, solo arranca cuando ambos equipos están balanceados, cuenta regresiva de 10s con barreras de inicio, HUD de estado (`RoomStatusClient.client.luau` + `RoomStatusEvent`).
- **Datos de sesión por jugador** (`PlayerDataModule.luau`): vidas (máx. 5), stage actual, checkpoint, pista asignada — con autoridad exclusiva del servidor y copias defensivas para el cliente.
- **Checkpoints y progreso por pista** (`CheckpointSystem.server.luau`): detección de `Checkpoint_Pad` por stage, avance automático a la siguiente plataforma, teletransporte a la arena del jefe al completar el Stage 5.
- **Pérdida de vidas y respawn**: caída al vacío o muerte del `Humanoid` restan una vida y reaparecen al jugador en su último checkpoint (o en el Stage 1 / Lobby si no tiene pista asignada); al quedarse sin vidas se resetea el progreso de la pista.
- **Greybox de las 5 stages en ambas pistas** (`default.project.json`): plataforma base, `Checkpoint_Pad`, escalera de prueba genérica y placeholder de `HostNPC` — sin geometría, obstáculos ni temática visual definitivos todavía.
- **Boss_Arena**: piso y plataformas de entrada creadas, sin jefe ni lógica de combate.
- Utilidad de debug (`DoubleJumpDebug.client.luau`) para probar el recorrido de las pistas sin depender del movimiento final.

### Falta por construir

- Obstáculos y arte temático por stage (barriles, cactus, plataformas que desaparecen, sierras, cintas transportadoras, dinamita con tiempo, botones cooperativos, piso destruible) — hoy todas las stages son bloques grises intercambiables.
- NPC Host real: diálogo con efecto typewriter, tienda de armas/consumibles/escudos/sabotajes.
- Sistema de sabotaje entre equipos (dinamita, shurikens que ciegan, terremotos).
- Revivir/donar vidas entre compañeros de equipo.
- Escudos comprables y sistema de daño/combate en general.
- HUD de marcador en vivo del equipo rival (stage, vidas, vida del jefe) — hoy solo existe el HUD de estado de matchmaking.
- Jefe final "El Shogun-Sheriff": modelo, máquina de estados, barra de escudo/vida, patrones de ataque, condición de victoria.
- Economía y monedas: recolectables en pista, recompensas por stage, botín de carrera.
- Persistencia con `DataStoreService` (monedas, skins, victorias, récords) — todo el estado actual vive solo en memoria del servidor.
- Tienda global de cosméticos e ítem exclusivo de avatar.
- Retirar los bloques de debug (`ALLOW_SOLO_DEBUG_START`, `DoubleJumpDebug.client.luau`) una vez el diseño final de movimiento/parkour y las pruebas multijugador estén listos.
