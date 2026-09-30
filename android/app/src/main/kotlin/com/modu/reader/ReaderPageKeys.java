package com.modu.reader;

import java.util.HashSet;
import java.util.Set;

/** Android key codes, kept independent of Activity for deterministic tests. */
final class ReaderPageKeys {
    static final int PASS = 0;
    static final int CONSUME = 2;
    private final Set<Long> pressed = new HashSet<>();

    int handle(int key, int action, int repeat, int device, boolean active,
               boolean volumeEnabled, boolean modified) {
        long identity = ((long) device << 32) | (key & 0xffffffffL);
        // Finish a consumed press even if a dialog opens before key-up.
        if (action == 1) return pressed.remove(identity) ? CONSUME : PASS;
        if (action != 0) return PASS;
        if (pressed.contains(identity)) return CONSUME;
        if (!active || modified || repeat != 0) return PASS;
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
