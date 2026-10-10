package com.modu.reader;

import java.util.HashSet;
import java.util.Set;
import java.util.Map;
import java.util.HashMap;
import java.util.List;

/** Android key codes, kept independent of Activity for deterministic tests. */
final class ReaderPageKeys {
    static final int PASS = 0;
    static final int CONSUME = 2;
    private final Set<Long> pressed = new HashSet<>();
    private Map<Integer, Integer> shortcuts;

    void configure(List<Map<String, Number>> bindings) {
        if (bindings == null) { shortcuts = null; return; }
        shortcuts = new HashMap<>();
        for (Map<String, Number> binding : bindings) {
            Number key = binding.get("keyCode"), modifiers = binding.get("modifiers"), action = binding.get("action");
            if (key == null || modifiers == null || action == null) continue;
            int a = action.intValue(), m = modifiers.intValue(), k = key.intValue();
            if (k < 0 || k > 300 || m < 0 || m > 15 || (a != -1 && a != 1 && (a < 3 || a > 7))) continue;
            shortcuts.put((k << 4) | m, a);
        }
    }

    int handle(int key, int action, int repeat, int device, boolean active,
               boolean volumeEnabled, boolean modified) {
        return handle(key, action, repeat, device, active, volumeEnabled, modified ? -1 : 0);
    }

    int handle(int key, int action, int repeat, int device, boolean active,
               boolean volumeEnabled, int modifiers) {
        long identity = ((long) device << 32) | (key & 0xffffffffL);
        // Finish a consumed press even if a dialog opens before key-up.
        if (action == 1) return pressed.remove(identity) ? CONSUME : PASS;
        if (action != 0) return PASS;
        if (pressed.contains(identity)) return CONSUME;
        if (!active || repeat != 0) return PASS;
        if (shortcuts != null && modifiers >= 0) {
            Integer shortcut = shortcuts.get((key << 4) | modifiers);
            if (shortcut != null) { pressed.add(identity); return shortcut; }
            if (key != 24 && key != 25) return PASS;
        }
        if (modifiers != 0) return PASS;
        int direction;
        switch (key) {
            case 19: // DPAD_UP
            case 21: // DPAD_LEFT
            case 92: // PAGE_UP
                direction = -1;
                break;
            case 20: // DPAD_DOWN
            case 22: // DPAD_RIGHT
            case 93: // PAGE_DOWN
                direction = 1;
                break;
            case 24: // VOLUME_UP
            case 25: // VOLUME_DOWN
                if (!volumeEnabled) return PASS;
                direction = key == 24 ? -1 : 1;
                break;
            default:
                return PASS;
        }
        pressed.add(identity);
        return direction;
    }

    void reset() { pressed.clear(); }
}
