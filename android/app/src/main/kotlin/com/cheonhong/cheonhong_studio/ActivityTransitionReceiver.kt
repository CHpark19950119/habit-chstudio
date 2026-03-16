package com.cheonhong.cheonhong_studio

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.android.gms.location.ActivityTransition
import com.google.android.gms.location.ActivityTransitionResult
import com.google.android.gms.location.DetectedActivity
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.SetOptions
import java.util.Calendar

/**
 * Activity Recognition → Firestore 기록
 *
 * BixbyNotificationListener가 외출 감지 시 등록,
 * 귀가 시 해제. 이동/정지 전환만 기록.
 */
class ActivityTransitionReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "ActivityReceiver"
        private const val UID = "sJ8Pxusw9gR0tNR44RhkIge7OiG2"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (!ActivityTransitionResult.hasResult(intent)) return
        val result = ActivityTransitionResult.extractResult(intent) ?: return
        val iotRef = FirebaseFirestore.getInstance().document("users/$UID/data/iot")

        for (event in result.transitionEvents) {
            val activityType = when (event.activityType) {
                DetectedActivity.STILL -> "still"
                DetectedActivity.WALKING -> "moving"
                DetectedActivity.RUNNING -> "moving"
                DetectedActivity.IN_VEHICLE -> "moving"
                DetectedActivity.ON_BICYCLE -> "moving"
                else -> continue
            }

            // ENTER 전환만 기록
            if (event.transitionType != ActivityTransition.ACTIVITY_TRANSITION_ENTER) continue

            val timeStr = timeStr()
            val dateStr = todayKey()

            Log.d(TAG, "Activity: $activityType at $timeStr")

            // Firestore 기록 (dot notation → 기존 movement 필드 보존)
            iotRef.update(
                mapOf(
                    "activity.current" to activityType,
                    "activity.date" to dateStr,
                    "activity.updatedAt" to FieldValue.serverTimestamp(),
                    "activity.transitions" to FieldValue.arrayUnion(
                        hashMapOf("type" to activityType, "time" to timeStr)
                    )
                )
            ).addOnFailureListener { e ->
                Log.e(TAG, "update failed, fallback set: ${e.message}")
                // 문서가 없는 경우 fallback (거의 발생 안 함)
                iotRef.set(
                    hashMapOf(
                        "activity" to hashMapOf(
                            "current" to activityType,
                            "date" to dateStr,
                            "updatedAt" to FieldValue.serverTimestamp(),
                            "transitions" to listOf(
                                hashMapOf("type" to activityType, "time" to timeStr)
                            )
                        )
                    ),
                    SetOptions.merge()
                )
            }
        }
    }

    private fun timeStr(): String {
        val cal = Calendar.getInstance()
        return String.format(
            "%02d:%02d",
            cal.get(Calendar.HOUR_OF_DAY),
            cal.get(Calendar.MINUTE)
        )
    }

    private fun todayKey(): String {
        val cal = Calendar.getInstance()
        if (cal.get(Calendar.HOUR_OF_DAY) < 4) {
            cal.add(Calendar.DAY_OF_MONTH, -1)
        }
        return String.format(
            "%d-%02d-%02d",
            cal.get(Calendar.YEAR),
            cal.get(Calendar.MONTH) + 1,
            cal.get(Calendar.DAY_OF_MONTH)
        )
    }
}
