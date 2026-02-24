#!/usr/bin/env python3
"""
Migrate global variables to container objects (GameSession, RenderState, InputManager).
This script does word-boundary replacements and removes old declarations.
"""

import re
import os
import sys

SRC_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       "Sources", "TiberianDawnMax")

# Files to NEVER modify (contain the new class definitions)
EXCLUDE_FILES = {"GameSession.swift", "RenderState.swift", "InputManager.swift"}

# ============================================================
# Variable mappings: old_name -> new_name
# ============================================================

SESSION_MAPPINGS = {
    "gameWorld": "session.world",
    "tickAccumulator": "session.tickAccumulator",
    "lastTickTime": "session.lastTickTime",
    "renderInterpolation": "session.renderInterpolation",
    "activeProjectiles": "session.activeProjectiles",
    "nextProjectileId": "session.nextProjectileId",
    "activeAnimations": "session.activeAnimations",
    "mapSmudges": "session.mapSmudges",
    "sidebarCredits": "session.sidebarCredits",
    "displayedCredits": "session.displayedCredits",
    "unitBuildQueue": "session.unitBuildQueue",
    "structureBuildQueue": "session.structureBuildQueue",
    "isPlacingStructure": "session.isPlacingStructure",
    "placementType": "session.placementType",
    "sidebarScrollOffset": "session.sidebarScrollOffset",
    "sidebarTab": "session.sidebarTab",
    "isRepairMode": "session.isRepairMode",
    "isSellMode": "session.isSellMode",
    "gameTriggers": "session.gameTriggers",
    "triggerWinState": "session.triggerWinState",
    "allowWinFlag": "session.allowWinFlag",
    "campaignState": "session.campaignState",
    "missionScore": "session.missionScore",
    "currentScenarioName": "session.currentScenarioName",
    "playerIonCannon": "session.playerIonCannon",
    "playerAirStrike": "session.playerAirStrike",
    "playerNukeStrike": "session.playerNukeStrike",
    "superWeaponTargeting": "session.superWeaponTargeting",
    "teamTypes": "session.teamTypes",
    "activeTeams": "session.activeTeams",
    "scenarioWaypoints": "session.scenarioWaypoints",
    "aiTickCounter": "session.aiTickCounter",
    "houseStates": "session.houseStates",
}

RENDER_MAPPINGS = {
    "gameCameraX": "renderState.gameCameraX",
    "gameCameraY": "renderState.gameCameraY",
    "gameZoomLevel": "renderState.gameZoomLevel",
    "icnCache": "renderState.icnCache",
    "tileTextureCache": "renderState.tileTextureCache",
    "mapFailedICNs": "renderState.mapFailedICNs",
    "terrainSHPCache": "renderState.terrainSHPCache",
    "terrainTextureCache": "renderState.terrainTextureCache",
    "terrainFailedSHPs": "renderState.terrainFailedSHPs",
    "objectSHPCache": "renderState.objectSHPCache",
    "objectTextureCache": "renderState.objectTextureCache",
    "objectFailedSHPs": "renderState.objectFailedSHPs",
    "selectSHP": "renderState.selectSHP",
    "selectTextures": "renderState.selectTextures",
    "pipsSHP": "renderState.pipsSHP",
    "pipsTextures": "renderState.pipsTextures",
    "mouseSHP": "renderState.mouseSHP",
    "mouseTextures": "renderState.mouseTextures",
    "uiSpritesLoaded": "renderState.uiSpritesLoaded",
    "cursorAnimFrame": "renderState.cursorAnimFrame",
    "cursorAnimTimer": "renderState.cursorAnimTimer",
    "systemCursorHidden": "renderState.systemCursorHidden",
    "remasteredTextureCache": "renderState.remasteredTextureCache",
    "hasRemasteredSprites": "renderState.hasRemasteredSprites",
    "animationFrame": "renderState.animationFrame",
    "showGrid": "renderState.showGrid",
    "showInfoPanel": "renderState.showInfoPanel",
    "showCellTriggers": "renderState.showCellTriggers",
    "showBaseList": "renderState.showBaseList",
    "perfShowOverlay": "renderState.perfShowOverlay",
    "spriteViewerIndex": "renderState.spriteViewerIndex",
    "spriteViewerFrame": "renderState.spriteViewerFrame",
    "currentSHP": "renderState.currentSHP",
    "spriteViewerAnimating": "renderState.spriteViewerAnimating",
    "spriteViewerFrameTimer": "renderState.spriteViewerFrameTimer",
    "windowWidth": "renderState.windowWidth",
    "windowHeight": "renderState.windowHeight",
    "gamePalette": "renderState.gamePalette",
}

INPUT_MAPPINGS = {
    "selectionBoxStartX": "input.selectionBoxStartX",
    "selectionBoxStartY": "input.selectionBoxStartY",
    "selectionBoxEndX": "input.selectionBoxEndX",
    "selectionBoxEndY": "input.selectionBoxEndY",
    "isDragging": "input.isDragging",
    "mouseWorldX": "input.mouseWorldX",
    "mouseWorldY": "input.mouseWorldY",
}

# These are in main.swift and need special handling (mapped to input.*)
MAIN_ONLY_INPUT = {
    "mouseX": "input.mouseX",
    "mouseY": "input.mouseY",
    "mousePanning": "input.isPanning",
    "lastMouseX": "input.lastMouseX",
    "lastMouseY": "input.lastMouseY",
}

# MapRenderer-specific: cameraX/cameraY/zoomLevel are map viewer camera
# Only used in MapRenderer.swift and main.swift
MAP_VIEWER_CAMERA = {
    "cameraX": "renderState.cameraX",
    "cameraY": "renderState.cameraY",
    "zoomLevel": "renderState.zoomLevel",
}

# ============================================================
# Declaration patterns to remove (file -> list of patterns)
# ============================================================

# These are the lines declaring the globals that are being moved.
# We match the beginning of the line (with optional leading whitespace).
DECLARATIONS_TO_REMOVE = {
    "GameState.swift": [
        r"^var gameWorld: GameWorld\?",
        r"^// Module-level game world",
    ],
    "GameLoop.swift": [
        r"^var tickAccumulator",
        r"^var lastTickTime",
        r"^var renderInterpolation",
        r"^// session\.tickAccumulator",
    ],
    "GameProjectiles.swift": [
        r"^var activeProjectiles",
        r"^private var nextProjectileId",
    ],
    "GameAnimation.swift": [
        r"^var mapSmudges",
        r"^var activeAnimations",
    ],
    "GameSidebar.swift": [
        r"^var sidebarCredits",
        r"^var displayedCredits",
        r"^var unitBuildQueue",
        r"^var structureBuildQueue",
        r"^var isPlacingStructure",
        r"^var placementType",
        r"^var sidebarScrollOffset",
        r"^var sidebarTab",
        r"^var isRepairMode",
        r"^var isSellMode",
    ],
    "GameTrigger.swift": [
        r"^var gameTriggers",
        r"^var triggerWinState",
        r"^var allowWinFlag",
    ],
    "GameCampaign.swift": [
        r"^var campaignState\b",
        r"^var missionScore\b",
        r"^var currentScenarioName",
    ],
    "GameSuperWeapons.swift": [
        r"^var playerIonCannon",
        r"^var playerAirStrike",
        r"^var playerNukeStrike",
        r"^var superWeaponTargeting",
    ],
    "GameTeam.swift": [
        r"^var teamTypes",
        r"^var activeTeams",
        r"^var scenarioWaypoints",
    ],
    "GameAI.swift": [
        r"^var aiTickCounter",
    ],
    "GameHouse.swift": [
        r"^var houseStates",
    ],
    "GameRenderer.swift": [
        r"^var gameCameraX",
        r"^var gameCameraY",
        r"^var gameZoomLevel",
        r"^var selectionBoxStartX",
        r"^var selectionBoxStartY",
        r"^var selectionBoxEndX",
        r"^var selectionBoxEndY",
        r"^var isDragging",
        r"^var selectSHP",
        r"^var selectTextures",
        r"^var pipsSHP",
        r"^var pipsTextures",
        r"^var mouseSHP",
        r"^var mouseTextures",
        r"^var uiSpritesLoaded",
        r"^var cursorAnimFrame",
        r"^var cursorAnimTimer",
        r"^var systemCursorHidden",
    ],
    "MapRenderer.swift": [
        r"^var cameraX: Int",
        r"^var cameraY: Int",
        r"^var zoomLevel: Double",
        r"^var icnCache",
        r"^var tileTextureCache",
        r"^var mapFailedICNs",
        r"^var terrainSHPCache",
        r"^var terrainTextureCache",
        r"^var terrainFailedSHPs",
        r"^var objectSHPCache",
        r"^var objectTextureCache",
        r"^var objectFailedSHPs",
        r"^var showGrid",
        r"^var showInfoPanel",
        r"^var showCellTriggers",
        r"^var showBaseList",
        r"^var mouseWorldX",
        r"^var mouseWorldY",
        r"^var animationFrame",
    ],
    "RemasteredSprites.swift": [
        r"^var remasteredTextureCache",
        r"^var hasRemasteredSprites",
    ],
    "PerfMonitor.swift": [
        r"^var perfShowOverlay",
    ],
    "SpriteViewer.swift": [
        r"^var spriteViewerIndex",
        r"^var spriteViewerFrame",
        r"^var currentSHP",
        r"^var spriteViewerAnimating",
        r"^var spriteViewerFrameTimer",
    ],
    "main.swift": [
        r"^var mouseX: Int32",
        r"^var mouseY: Int32",
        r"^var mousePanning\b",
        r"^var lastMouseX",
        r"^var lastMouseY",
        r"^var windowWidth",
        r"^var windowHeight",
        r"^var gamePalette\b",
    ],
    "GameEconomy.swift": [
        r"^var tiberiumCells",
    ],
    "GameFog.swift": [
        r"^var fogState",
    ],
}


def should_remove_line(line, filename):
    """Check if this line is a global declaration that should be removed."""
    stripped = line.lstrip()
    patterns = DECLARATIONS_TO_REMOVE.get(filename, [])
    for pattern in patterns:
        if re.match(pattern, stripped):
            return True
    return False


def apply_replacements(line, filename, all_mappings):
    """Apply all variable replacements to a line."""
    for old_name, new_name in all_mappings.items():
        # Match old_name as a whole word, but NOT if preceded by a dot
        # (which would mean it's already a property access like renderState.gameCameraX)
        # (?<!\w) = not preceded by word char
        # (?<!\.) = not preceded by dot
        # (?!\w) = not followed by word char
        pattern = r'(?<!\w)(?<!\.)' + re.escape(old_name) + r'(?!\w)'
        line = re.sub(pattern, new_name, line)
    return line


def process_file(filepath, filename):
    """Process a single Swift file."""
    with open(filepath, 'r') as f:
        lines = f.readlines()

    # Build the combined mapping for this file
    all_mappings = {}
    all_mappings.update(SESSION_MAPPINGS)
    all_mappings.update(RENDER_MAPPINGS)
    all_mappings.update(INPUT_MAPPINGS)

    # Only apply main-only input mappings to files that use them
    # mouseX/mouseY are tricky — they're also used as parameter names in many functions
    # We need to be conservative: only replace them in main.swift
    if filename == "main.swift":
        all_mappings.update(MAIN_ONLY_INPUT)

    # Map viewer camera: only replace in MapRenderer.swift and main.swift
    if filename in ("MapRenderer.swift", "main.swift"):
        all_mappings.update(MAP_VIEWER_CAMERA)

    new_lines = []
    removed_count = 0
    replaced_count = 0

    for line in lines:
        # Check if this is a declaration to remove
        if should_remove_line(line, filename):
            removed_count += 1
            continue

        # Apply replacements
        new_line = apply_replacements(line, filename, all_mappings)
        if new_line != line:
            replaced_count += 1
        new_lines.append(new_line)

    if removed_count > 0 or replaced_count > 0:
        with open(filepath, 'w') as f:
            f.writelines(new_lines)
        print(f"  {filename}: removed {removed_count} declarations, {replaced_count} lines updated")
    else:
        print(f"  {filename}: no changes")


def main():
    print("Migrating globals to container objects...")
    print(f"Source directory: {SRC_DIR}")
    print()

    swift_files = sorted(f for f in os.listdir(SRC_DIR) if f.endswith('.swift'))

    for filename in swift_files:
        if filename in EXCLUDE_FILES:
            print(f"  {filename}: SKIPPED (container file)")
            continue

        filepath = os.path.join(SRC_DIR, filename)
        process_file(filepath, filename)

    print()
    print("Migration complete! Run 'swift build' to check for errors.")


if __name__ == "__main__":
    main()
