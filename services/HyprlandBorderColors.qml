pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common
import qs.services

/**
 * Keeps Hyprland's window border colors in sync with the shell palette.
 *
 * Border colors normally come from matugen, which writes hypr/hyprland/colors.lua.
 * hyprland.lua sources the shell overrides file *after* that one, so writing
 * general:col:* there wins without touching the generated file. Turning the
 * option off removes the keys again and matugen's colors take over.
 *
 * What gets stored is a palette *role*, not a literal color, so borders follow
 * the wallpaper: Appearance.m3colors updates on every colorgen run and the
 * bindings below re-apply on their own. A role of "custom" uses the stored hex
 * instead, which deliberately does not follow the wallpaper.
 *
 * Roles resolve against m3colors (the raw generated palette) rather than
 * Appearance.colors, whose entries are composited for use inside the shell:
 * several carry an alpha that encodes a layer opacity, which would make a
 * window border translucent or invisible for reasons that have nothing to do
 * with the opacity set here.
 */
Singleton {
    id: root

    readonly property string activeKey: "general:col:active_border"
    readonly property string inactiveKey: "general:col:inactive_border"

    readonly property var opts: Config.options?.hyprland?.general?.borderColor ?? null
    readonly property bool enabled: root.opts?.enable ?? false

    readonly property string activeRgba: root.toHyprColor(
        root.resolve(root.opts?.activeRole ?? "", root.opts?.activeCustom ?? ""),
        root.opts?.activeOpacity ?? 1)
    readonly property string inactiveRgba: root.toHyprColor(
        root.resolve(root.opts?.inactiveRole ?? "", root.opts?.inactiveCustom ?? ""),
        root.opts?.inactiveOpacity ?? 1)

    // Singletons are lazily loaded, so shell.qml calls this to force init.
    function load() {}

    function isValidHex(hex) {
        return /^#?([0-9a-fA-F]{6}|[0-9a-fA-F]{3})$/.test(String(hex).trim())
    }

    /**
     * Resolves a stored role to an actual color. Returns "" when a custom hex
     * is selected but not (yet) valid, so a half-typed value is never written
     * out to Hyprland.
     */
    // Palette roles offered for borders, in the order the settings page shows them.
    readonly property var roles: [
        "outlineVariant", "outline", "primary", "secondary", "tertiary",
        "primaryContainer", "secondaryContainer", "tertiaryContainer",
        "surfaceContainerLow", "surfaceContainerHigh", "onSurface", "error"
    ]

    function resolve(role, customHex) {
        if (role === "custom") {
            return root.isValidHex(customHex) ? String(customHex).trim() : ""
        }
        if (!role || role.length === 0) return ""
        const resolved = Appearance.m3colors["m3" + role]
        return resolved === undefined ? "" : resolved
    }

    function pad2(value) {
        const clamped = Math.max(0, Math.min(255, Math.round(value)))
        return (clamped < 16 ? "0" : "") + clamped.toString(16)
    }

    /**
     * Hyprland wants rgba(RRGGBBAA) with no leading '#'. The color's own alpha
     * is multiplied in so palette roles that are already translucent stay so.
     */
    function toHyprColor(colorValue, opacity) {
        if (!colorValue || String(colorValue).length === 0) return ""
        const c = Qt.color(colorValue)
        const a = Math.max(0, Math.min(1, opacity)) * c.a
        return `rgba(${root.pad2(c.r * 255)}${root.pad2(c.g * 255)}${root.pad2(c.b * 255)}${root.pad2(a * 255)})`
    }

    function apply() {
        if (!Config.ready || !root.enabled) return
        let entries = ({})
        if (root.activeRgba.length > 0) entries[root.activeKey] = root.activeRgba
        if (root.inactiveRgba.length > 0) entries[root.inactiveKey] = root.inactiveRgba
        if (Object.keys(entries).length > 0) HyprlandConfig.setMany(entries)
    }

    function clear() {
        if (!Config.ready) return
        HyprlandConfig.resetMany([root.activeKey, root.inactiveKey])
    }

    // A colorgen run updates every palette role at once, and each update would
    // otherwise spawn its own configurator process.
    Timer {
        id: applyDebounce
        interval: 150
        repeat: false
        onTriggered: root.apply()
    }

    onActiveRgbaChanged: applyDebounce.restart()
    onInactiveRgbaChanged: applyDebounce.restart()

    onEnabledChanged: {
        applyDebounce.stop()
        if (root.enabled) root.apply()
        else root.clear()
    }

    // Config loads asynchronously, so the first apply has to wait for it.
    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready && root.enabled) applyDebounce.restart()
        }
    }
}
