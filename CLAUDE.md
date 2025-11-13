# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Factorio Mod Development

This is a **Factorio mod** written in Lua that implements a transport drone system. Understanding Factorio's modding API and lifecycle is essential for working with this codebase.

### Factorio Mod Lifecycle

Factorio mods follow a three-stage loading process:

1. **Settings Stage** (`settings.lua`) - Defines mod configuration parameters
2. **Data Stage** (`data.lua`, `data-final-fixes.lua`) - Creates game prototypes (entities, technologies, recipes)
3. **Runtime Stage** (`control.lua`) - Handles game events and logic during gameplay

### Key Files and Their Purposes

- `control.lua` - Main runtime entry point, registers event handlers
- `data.lua` - Data stage entry point, defines game prototypes
- `shared.lua` - Shared constants and configuration used across stages
- `info.json` - Mod metadata and dependencies
- `script/` - Runtime logic modules
- `data/` - Data stage definitions (entities, technologies, graphics)

## Architecture Overview

### Event-Driven Architecture

The mod uses a centralized event handling system (`event_handler`) where modules register for specific Factorio events:

```lua
-- In control.lua
handler.add_lib(require("script/road_network"))
handler.add_lib(require("script/depot_common"))
```

Each module exports an `events` table mapping event types to handler functions.

### Core Systems

1. **Road Network (`script/road_network.lua`)** - Manages the pathfinding network and depot connectivity
2. **Depot System (`script/depot_common.lua`)** - Central depot management and update scheduling
3. **Drone Logic (`script/transport_drone.lua`)** - Individual drone AI and state machine
4. **Transport Technologies (`script/transport_technologies.lua`)** - Technology effects and bonuses

### Depot Types

Located in `script/depots/`:

- **Supply Depot** - Provides items to the network from containers
- **Request Depot** - Requests items from the network
- **Buffer Depot** - Temporary storage and sorting
- **Fuel Depot** - Provides fuel for drones
- **Fluid Depot** - Handles fluid transport
- **Mining Depot** - Automated mining operations

### Entity Architecture

Each depot type follows a consistent pattern:

```lua
depot.new(entity, tags) -- Constructor
depot:update() -- Called periodically
depot:add_to_network() -- Network registration
depot:remove_from_network() -- Cleanup
```

## Key Factorio APIs Used

Understanding these APIs is crucial for working with this mod:

- `surface.create_entity()` - Creates game entities (drones, depots)
- `entity.set_command()` - Controls unit movement and AI
- `inventory.insert/remove()` - Item manipulation
- `defines.events.*` - Event type constants
- `script.register_on_object_destroyed()` - Entity cleanup tracking
- `rendering.draw_*()` - UI overlay rendering

## Development Patterns

### Entity Lifecycle Management

The mod carefully manages entity creation and destruction:

1. Entities are registered for destruction tracking
2. Depot objects maintain references to multiple related entities
3. Cleanup is performed in `on_removed()` methods

### Performance Considerations

- Update buckets distribute depot updates across multiple ticks
- Network caching minimizes pathfinding calculations
- Item tracking uses efficient lookup tables

### Circuit Network Integration

Depots can connect to Factorio's circuit network for:
- Item count monitoring (`circuit_reader`)
- Conditional operation (`circuit_writer`)
- Logistics network integration

## Working with the Codebase

### Making Changes to Depot Logic

1. Locate the appropriate depot file in `script/depots/`
2. Understand the depot's update cycle and network interactions
3. Test with both items and fluids if applicable
4. Consider circuit network integration

### Adding New Entity Types

1. Define prototypes in `data/entities/`
2. Add sprite assets to appropriate subdirectories
3. Register in `depot_common.lua` if it's a depot type
4. Implement required interface methods

### Debugging

The mod includes debug output via:
- `depot:say(message)` for entity-specific messages
- Alert system for user notifications
- Rendering system for visual debugging

### Mod Compatibility

The mod supports integration with:
- PickerDollies (entity moving)
- Quality mod (item quality system)
- Various other mods via optional dependencies

## File Structure Patterns

```
script/
├── depot_common.lua          # Central depot management
├── road_network.lua          # Pathfinding and network logic
├── transport_drone.lua       # Drone AI and behavior
└── depots/                   # Individual depot implementations
    ├── supply_depot.lua
    ├── request_depot.lua
    └── ...

data/
├── entities/                 # Entity prototype definitions
├── technologies/             # Research tree definitions
└── tips/                     # In-game help system
```

This structure separates runtime logic (`script/`) from data definitions (`data/`), following Factorio modding conventions.