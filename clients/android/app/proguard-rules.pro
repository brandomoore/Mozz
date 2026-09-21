# R8 rules for the release build.
#
# The release build type minifies and shrinks resources; debug does not. Every
# rule here is therefore about something that works in development and would
# break only in the APK a user downloads.
#
# The JNI keeps live in `core/consumer-rules.pro`, beside the code they protect,
# so they apply to anything that consumes :core rather than only to this app.

# --- kotlinx.serialization ---------------------------------------------------
#
# The compiler plugin generates a `$$serializer` for each `@Serializable` class
# and `Companion.serializer()` finds it reflectively. The library ships consumer
# rules that cover the common paths; these are the explicit backstop, because a
# stripped serializer presents as a runtime `SerializationException` naming a
# class that R8 renamed — which reads as a wire-format bug and is not one.
-keepattributes *Annotation*, InnerClasses, Signature, RuntimeVisibleAnnotations
-dontnote kotlinx.serialization.**

-keepclassmembers class kotlinx.serialization.json.** {
    *** Companion;
}
-keepclasseswithmembers class kotlinx.serialization.json.** {
    kotlinx.serialization.KSerializer serializer(...);
}

-if @kotlinx.serialization.Serializable class **
-keepclassmembers class <1> {
    static <1>$Companion Companion;
    static **$* *;
}
-if @kotlinx.serialization.Serializable class **$*
-keepclassmembers class <1>$<2> {
    kotlinx.serialization.KSerializer serializer(...);
}
-keepclassmembers class * {
    *** Companion;
    kotlinx.serialization.KSerializer serializer(...);
}

# --- Media3 / ExoPlayer ------------------------------------------------------
#
# Renderers, extractors and the audio processors are instantiated reflectively
# by name in places, and the DSP chain is one of them: a shrunk-away
# `MozzAudioProcessor` costs the equaliser and ReplayGain silently, with audio
# still playing, which is the hardest kind of regression to notice.
-keep class androidx.media3.** { *; }
-dontwarn androidx.media3.**
-keep class com.thatcube.mozz.playback.** { *; }

# --- Line numbers ------------------------------------------------------------
#
# A stack trace from a user is the only diagnostic a self-hosted app gets. Keep
# the table and rename the file, so traces stay readable without shipping the
# original source paths.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
