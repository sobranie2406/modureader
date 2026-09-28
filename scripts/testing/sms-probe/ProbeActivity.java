package com.modu.reader.smsprobe;

import android.app.Activity;
import android.os.Bundle;

/** Explicit first launch lets OEM systems activate the disposable test app. */
public final class ProbeActivity extends Activity {
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        finish();
    }
}
