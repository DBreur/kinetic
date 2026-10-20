# Spotify App Remote / Auth SDK (spotify_sdk): de SDK gebruikt reflectie en
# (de)serialisatie van zijn eigen klassen om met de Spotify-app te praten.
# Hernoemt R8 die klassen in de release-build, dan faalt het verbinden met
# "CouldNotFindSpotifyApp" — ook als Spotify gewoon geïnstalleerd is.
-keep class com.spotify.** { *; }
-keep interface com.spotify.** { *; }
-keepattributes Signature, *Annotation*, InnerClasses, EnclosingMethod
-dontwarn com.spotify.**
