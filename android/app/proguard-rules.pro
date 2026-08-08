# Flutter's own engine classes are referenced from native code, which R8 cannot
# see.
-keep class io.flutter.** { *; }

# Google Sign-In goes through the credential/identity libraries, which resolve
# a good deal reflectively.
-keep class com.google.android.gms.auth.** { *; }
-keep class com.google.android.libraries.identity.googleid.** { *; }

# The Flutter engine ships support for Play Store deferred components, so it
# references the Play Core library whether or not an app uses that feature.
# This one does not, so those classes are genuinely absent and R8 fails the
# build over the dangling references. Silencing the warning is the documented
# answer: the code paths that would need them are never reached.
-dontwarn com.google.android.play.core.**
