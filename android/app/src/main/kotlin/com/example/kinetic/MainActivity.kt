package com.example.kinetic

import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Ook naast de camera-uitsparing tekenen. Zonder dit laat Android in
        // volledig-scherm-modus (systeemknoppen verborgen) een zwarte balk
        // bovenaan; Flutter krijgt de uitsparing gewoon als veilige zone door.
        // Geen (halfdoorzichtige) achtergrond achter de navigatieknoppen: die
        // verdween bij het verbergen eerder dan de knoppen zelf.
        @Suppress("DEPRECATION")
        window.navigationBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = false
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes = window.attributes.apply {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
    }
}
