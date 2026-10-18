# 2026-10-18: 광고 SDK(google_mobile_ads)가 끌고 오는 WorkManager가 Room 데이터베이스(WorkDatabase_Impl)를 리플렉션으로 만드는데,
# 릴리스 빌드의 R8이 이 클래스를 지워서 앱이 켜지자마자 "Failed to create an instance of androidx.work.impl.WorkDatabase"로 죽었음.
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class * extends androidx.room.RoomDatabase { *; }
-keep class androidx.work.** { *; }
-dontwarn androidx.work.**
# 홈 화면 위젯(WeatherWidget.kt): 위젯 제공자는 매니페스트가, 동기화 작업(WidgetSyncWorker)은 WorkManager가 클래스 이름 문자열로 다시 만듦
# (앱을 업데이트해도 예약된 작업이 살아 있으려면 이름이 안 바뀌어야 함) → 이름·생성자를 보존
-keep class com.dailycut.dailycut.** { *; }
