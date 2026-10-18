# 2026-10-18: 광고 SDK(google_mobile_ads)가 끌고 오는 WorkManager가 Room 데이터베이스(WorkDatabase_Impl)를 리플렉션으로 만드는데,
# 릴리스 빌드의 R8이 이 클래스를 지워서 앱이 켜지자마자 "Failed to create an instance of androidx.work.impl.WorkDatabase"로 죽었음.
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class * extends androidx.room.RoomDatabase { *; }
-keep class androidx.work.** { *; }
-dontwarn androidx.work.**
