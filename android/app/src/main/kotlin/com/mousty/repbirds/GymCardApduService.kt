package com.mousty.repbirds

import android.content.Context
import android.nfc.cardemulation.HostApduService
import android.os.Bundle
import android.util.Base64
import org.json.JSONObject
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * The gym card over NFC (HCE): when the gym's reader selects [AID], answers with the
 * current card code, the same one shown as QR. Same formula as lib/core/gym/card_code.dart
 * and GymCardService in repbirds-api: `RBG1.{cardId}.{window}.{first 16 of base64url(HMAC-SHA256)}`.
 * Android runs it with the screen on even when the app is closed, and it needs no network.
 * The card comes from Dart through `repbirds/gym_nfc` (see MainActivity).
 */
class GymCardApduService : HostApduService() {

    override fun processCommandApdu(commandApdu: ByteArray, extras: Bundle?): ByteArray {
        if (!isSelectAid(commandApdu)) return SW_UNKNOWN
        val code = currentCode(this) ?: return SW_NOT_FOUND
        return code.toByteArray(Charsets.US_ASCII) + SW_OK
    }

    override fun onDeactivated(reason: Int) {}

    companion object {
        /** Proprietary AID: F0 + "RBGYM1". Must match res/xml/gym_card_apduservice.xml. */
        val AID = byteArrayOf(0xF0.toByte(), 0x52, 0x42, 0x47, 0x59, 0x4D, 0x31)
        val SW_OK = byteArrayOf(0x90.toByte(), 0x00)
        private val SW_NOT_FOUND = byteArrayOf(0x6A, 0x82.toByte())
        private val SW_UNKNOWN = byteArrayOf(0x6F, 0x00)
        private const val PREFS = "repbirds_gym_card"
        private const val KEY = "card"

        /** SELECT by name of our AID: 00 A4 04 00 Lc AID [Le]. */
        fun selectApdu(): ByteArray = byteArrayOf(0x00, 0xA4.toByte(), 0x04, 0x00, AID.size.toByte()) + AID + byteArrayOf(0x00)

        private fun isSelectAid(apdu: ByteArray): Boolean {
            if (apdu.size < 5 + AID.size) return false
            if (apdu[0] != 0x00.toByte() || apdu[1] != 0xA4.toByte() || apdu[2] != 0x04.toByte()) return false
            val length = apdu[4].toInt() and 0xFF
            return length == AID.size && apdu.copyOfRange(5, 5 + length).contentEquals(AID)
        }

        fun saveCard(context: Context, json: String?) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            if (json == null) prefs.remove(KEY) else prefs.putString(KEY, json)
            prefs.apply()
        }

        fun currentCode(context: Context, nowMillis: Long = System.currentTimeMillis()): String? {
            val json = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null) ?: return null
            return try {
                val card = JSONObject(json)
                code(card.getString("cardId"), card.getString("secret"), card.optInt("periodSeconds", 30), nowMillis)
            } catch (e: Exception) {
                null
            }
        }

        fun code(cardId: String, secret: String, periodSeconds: Int, nowMillis: Long): String {
            val window = nowMillis / 1000 / periodSeconds
            val key = Base64.decode(secret, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
            val mac = Mac.getInstance("HmacSHA256").apply { init(SecretKeySpec(key, "HmacSHA256")) }
            val digest = mac.doFinal("$cardId.$window".toByteArray(Charsets.UTF_8))
            val signature = Base64.encodeToString(digest, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP).substring(0, 16)
            return "RBG1.$cardId.$window.$signature"
        }
    }
}
