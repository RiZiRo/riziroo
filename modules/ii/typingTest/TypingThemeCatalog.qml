pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick

QtObject {
    id: root

    property string themeName: "pure_black"
    property bool customTheme: false
    property var customColors: ({
        bg: "#000000", main: "#eeeeee", caret: "#ffffff", sub: "#505050",
        subAlt: "#101010", text: "#eeeeee", error: "#ca4754", errorExtra: "#7e2a33",
        colorfulError: "#ca4754", colorfulErrorExtra: "#7e2a33"
    })

    readonly property var presets: [
        palette("pure_black", "Pure Black", "#000000", "#eeeeee", "#ffffff", "#505050", "#101010", "#eeeeee", "#ca4754", "#7e2a33"),
        palette("dark", "Dark", "#111111", "#eeeeee", "#eeeeee", "#444444", "#191919", "#eeeeee", "#da3333", "#791717"),
        palette("serika_dark", "Serika Dark", "#323437", "#e2b714", "#e2b714", "#646669", "#2c2e31", "#d1d0c5", "#ca4754", "#7e2a33"),
        palette("vesper", "Vesper", "#101010", "#ffc799", "#99ffe4", "#a0a0a0", "#1c1c1c", "#ffffff", "#ff8080", "#b25959"),
        palette("terminal", "Terminal", "#191a1b", "#79a617", "#79a617", "#48494b", "#141516", "#e7eae0", "#a61717", "#731010"),
        palette("carbon", "Carbon", "#313131", "#f66e0d", "#f66e0d", "#616161", "#2b2b2b", "#f5e6c8", "#e72d2d", "#7e2a33"),
        palette("nord", "Nord", "#242933", "#88c0d0", "#eceff4", "#929aaa", "#2e3440", "#d8dee9", "#bf616a", "#793e44"),
        palette("catppuccin", "Catppuccin", "#1e1e2e", "#cba6f7", "#f2cdcd", "#7f849c", "#181825", "#cdd6f4", "#f38ba8", "#eba0ac"),
        palette("dracula", "Dracula", "#282a36", "#bd93f9", "#bd93f9", "#6272a4", "#20222c", "#f8f8f2", "#ff5555", "#f1fa8c"),
        palette("rose_pine", "Rose Pine", "#1f1d27", "#9ccfd8", "#f6c177", "#c4a7e7", "#282533", "#e0def4", "#eb6f92", "#ebbcba"),
        palette("gruvbox_dark", "Gruvbox Dark", "#282828", "#d79921", "#fabd2f", "#665c54", "#212121", "#ebdbb2", "#fb4934", "#cc241d"),
        palette("onedark", "One Dark", "#2f343f", "#61afef", "#61afef", "#eceff4", "#262b34", "#98c379", "#e06c75", "#d62436"),
        palette("modern_dolch", "Modern Dolch", "#2d2e30", "#7eddd3", "#7eddd3", "#54585c", "#242527", "#e3e6eb", "#d36a7b", "#994154"),
        palette("stealth", "Stealth", "#010203", "#383e42", "#e25303", "#5e676e", "#121212", "#899095", "#e25303", "#73280c"),
        palette("material", "Material", "#263238", "#80cbc4", "#80cbc4", "#4c6772", "#2e3c43", "#e6edf3", "#fb4934", "#cc241d"),
        palette("solarized_dark", "Solarized Dark", "#002b36", "#859900", "#dc322f", "#2aa198", "#00222b", "#268bd2", "#d33682", "#9b225c")
    ]

    // Not part of `presets` because it is a live binding: picking it makes the
    // typing test recolor along with the wallpaper-derived shell theme.
    readonly property var shellPalette: palette("shell", "Follow shell colors",
        String(Appearance.colors.colLayer0Base),
        String(Appearance.colors.colPrimary),
        String(Appearance.colors.colPrimary),
        String(Appearance.colors.colOnLayer1Inactive),
        String(Appearance.colors.colLayer1),
        String(Appearance.colors.colOnLayer0),
        String(Appearance.colors.colError),
        String(Appearance.colors.colErrorContainer))

    readonly property var selectableThemes: [shellPalette].concat(presets)

    readonly property var active: customTheme && validatePalette(customColors).valid
        ? normalized(customColors)
        : (themeName === "shell" ? shellPalette : preset(themeName))

    function palette(key, label, bg, main, caret, sub, subAlt, text, error, errorExtra) {
        return {
            key, label, bg, main, caret, sub, subAlt, text, error, errorExtra,
            colorfulError: error, colorfulErrorExtra: errorExtra
        };
    }

    function preset(name) {
        for (let i = 0; i < presets.length; ++i)
            if (presets[i].key === name) return presets[i];
        return presets[0];
    }

    function isHex(value) {
        return typeof value === "string" && /^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(value);
    }

    function normalized(value) {
        const fallback = preset("pure_black");
        const result = {key: "custom", label: "Custom"};
        const fields = ["bg", "main", "caret", "sub", "subAlt", "text", "error", "errorExtra", "colorfulError", "colorfulErrorExtra"];
        for (let i = 0; i < fields.length; ++i) {
            const field = fields[i];
            result[field] = isHex(value?.[field]) ? value[field] : fallback[field];
        }
        return result;
    }

    function luminance(hex) {
        if (!isHex(hex)) return 0;
        let raw = hex.slice(1);
        if (raw.length === 3) raw = raw.split("").map(c => c + c).join("");
        const channels = [0, 2, 4].map(offset => {
            const value = parseInt(raw.slice(offset, offset + 2), 16) / 255;
            return value <= 0.03928 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
        });
        return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722;
    }

    function contrast(a, b) {
        const first = luminance(a);
        const second = luminance(b);
        return (Math.max(first, second) + 0.05) / (Math.min(first, second) + 0.05);
    }

    function validatePalette(value) {
        const fields = ["bg", "main", "caret", "sub", "subAlt", "text", "error", "errorExtra", "colorfulError", "colorfulErrorExtra"];
        const invalid = fields.filter(field => !isHex(value?.[field]));
        if (invalid.length > 0) return {valid: false, message: `Invalid colors: ${invalid.join(", ")}`};
        const textContrast = contrast(value.text, value.bg);
        const subContrast = contrast(value.sub, value.bg);
        return {
            valid: true,
            warning: textContrast < 4.5 || subContrast < 2.2,
            textContrast,
            subContrast,
            message: textContrast < 4.5 ? "Text contrast is too low for comfortable typing." : (subContrast < 2.2 ? "Untyped text may be difficult to see." : "Palette contrast is readable.")
        };
    }

    function exportJson() {
        return JSON.stringify(normalized(customTheme ? customColors : active), null, 2);
    }

    function importJson(text) {
        try {
            const parsed = JSON.parse(text);
            const validation = validatePalette(parsed);
            if (!validation.valid) return validation;
            customColors = normalized(parsed);
            customTheme = true;
            return validation;
        } catch (error) {
            return {valid: false, message: `Invalid JSON: ${error}`};
        }
    }

    function resetCustomFromPreset() {
        customColors = normalized(themeName === "shell" ? shellPalette : preset(themeName));
    }
}
