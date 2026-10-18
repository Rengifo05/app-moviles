package co.nexofamilia.nexo_familia

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createSosChannel()
    }

    /**
     * Canal propio de las alertas SOS (ADR-005), con importancia alta para
     * que el aviso aparezca en pantalla. La persona puede ajustarlo aparte de
     * los demás avisos. Crearlo de nuevo no cambia lo que ella haya elegido.
     * Si el canal aún no existe (la app nunca se abrió), FCM usa su canal por
     * defecto.
     */
    private fun createSosChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            SOS_CHANNEL_ID,
            getString(R.string.sos_channel_name),
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = getString(R.string.sos_channel_description)
        }
        getSystemService(NotificationManager::class.java)
            ?.createNotificationChannel(channel)
    }

    companion object {
        /** Debe coincidir con `channelId` en functions/src/index.ts. */
        const val SOS_CHANNEL_ID = "sos_alerts"
    }
}
