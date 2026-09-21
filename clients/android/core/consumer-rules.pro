# Rules that travel with :core to whatever consumes it.
#
# THE JNI BOUNDARY MUST KEEP ITS NAMES.
#
# `mozz_jni.c` binds by symbol name, the way the JVM resolves `external fun` by
# default: the C side exports `Java_com_thatcube_mozz_core_MozzNative_nativeOpen`
# and the runtime looks for exactly that string, derived from the class's fully
# qualified name and the method's name. R8 does not know this. Left to itself it
# renames `MozzNative` to something like `a.a.a.b` and the lookup fails with
# `UnsatisfiedLinkError` on the first call.
#
# That first call is `nativeOpen`, which opens the catalogue — so the failure is
# not a degraded feature, it is the whole app, and only in release builds. Debug
# does not minify, so this is invisible until the APK someone downloaded is the
# one that crashes.
-keepclasseswithmembernames,includedescriptorclasses class com.thatcube.mozz.core.MozzNative {
    native <methods>;
}
-keep class com.thatcube.mozz.core.MozzNative { *; }

# Any other native method anywhere, same reasoning, for whatever is added next.
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}
