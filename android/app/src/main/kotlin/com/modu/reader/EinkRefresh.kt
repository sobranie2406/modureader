package com.modu.reader

import android.content.Context
import java.lang.reflect.Method

/** One-shot OEM refresh only: never change persistent waveform/system settings.
 * RK35xx firmware exposes android.os.EinkManager.sendOneFullFrame(). Probe the
 * service AND method, not the manufacturer name (firmware capabilities differ).
 * Interface reference: KOReader android-luajit-launcher, RK35xxEPDController.
 */
internal class EinkRefresh(context: Context) {
    private var service: Any? = null
    private var refresh: Method? = null

    init {
        try {
            val type = Class.forName("android.os.EinkManager")
            val instance = context.getSystemService("eink")
            if (instance != null && type.isInstance(instance)) {
                refresh = type.getMethod("sendOneFullFrame")
                service = instance
            }
        } catch (_: Exception) {
            // Ordinary Android and restricted OEM firmware are unsupported.
        } catch (_: LinkageError) {
        }
    }

    fun supported(): Boolean = service != null && refresh != null

    fun request(): Boolean = try {
        if (!supported()) false else refresh!!.invoke(service) != false
    } catch (_: Exception) {
        false
    } catch (_: LinkageError) {
        false
    }
}
