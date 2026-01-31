# Draft: Incremental Game ASCII UI Content

## Current State Understanding

### Existing Systems
- **Resources**: 4 types (food, wood, stone, gold) - DONE
- **Upgrades**: 12 defined (click multipliers, passive rates, creature stats, etc.) - DONE
- **UI Panels**: ImGui-based (resource_panel.lua, upgrade_panel.lua) - DONE but needs visual overhaul
- **Terrain**: 30x20 tile grid, procedural generation - DONE
- **Creatures**: GOAP-based foragers with Wander/Forage/Idle - DONE

### UI System Available
- **C++ UIElementTemplateNode**: Builder pattern, hierarchical
- **Types**: ROOT, VERTICAL_CONTAINER, HORIZONTAL_CONTAINER, SCROLL_PANE, TEXT, RECT_SHAPE, OBJECT, FILLER
- **Features**: 9-patch borders, rounded rectangles, sprites, tooltips, progress bars, buttons, hover effects
- **Rendering**: command_buffer.queueDrawSpriteTopLeft (batch rendering)

### ASCII Sprites Available
- **CP437 tileset**: 256 characters at 20x20 pixels
- **ASCII sprites**: Pre-packed in atlas (ascii_sprites_data.json)
- **Dungeon tileset**: d437_* sprites imported for terrain

## Requirements (confirmed)
- [x] Adapt existing ImGui UI to match game's ASCII aesthetic
- [x] UI should look like it conforms to the grid (tile-aligned, 20px multiples)
- [x] Show resources and upgrades
- [x] Add achievements/milestones system
- [x] Add more creature types

## Technical Decisions (confirmed)
- **UI Approach**: Coexist - Keep ImGui for debug, add ASCII UI for gameplay
- **Border Style**: Single-line box (┌─┐│└┘) using CP437/dungeon sprites, CONFIGURABLE
- **Layout**: Overlay with transparent background (game visible behind)
- **Grid Alignment**: Strictly grid-aligned (all positions/sizes in 20px multiples)

## Open Questions (answered)
1. **Creature types**: 4 new types - Miner, Lumberjack, Collector, Builder
2. **Achievements**: 4 categories - Resource thresholds, Upgrade milestones, Creature population, Time-based
3. **Icons**: Yes, ASCII sprites alongside text
4. **Upgrade layout**: Scrollable list
5. **Phasing**: Full scope in one plan
6. **Builder structures**: Simple decorative (no gameplay effect)
7. **Resolution**: Resize window to fit UI, keep 30x20 tile grid
8. **Achievement popups**: Yes, brief toast notifications

## Final Decisions
- **Color scheme**: Earthy/forest tones (browns, greens, gold)
- **Test strategy**: TDD for data systems (achievements, creature logic), manual for visual
- **Resource panel**: Top-left corner
- **Upgrade panel**: Right sidebar

## Scope Boundaries
- INCLUDE: 
  - ASCII-styled resource panel (native UI, grid-aligned, icons + text)
  - ASCII-styled upgrade panel (scrollable list, grid-aligned)
  - Achievement/milestone system (4 categories, toast notifications)
  - 4 creature types: Miner (stone), Lumberjack (wood), Collector (ground pickup), Builder (decorative structures)
  - Configurable border style system (CP437 single-line, swappable)
  - Window resize to accommodate UI (keep 30x20 tile grid)
- EXCLUDE: 
  - Removing ImGui (keep for debugging)
  - Functional structures (just decorative)
  - Sound/music integration
  - Complex nested UI hierarchies
