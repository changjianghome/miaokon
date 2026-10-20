plugins {
    id("com.android.application")
}

android {
    namespace = "site.miaokon.android"
    compileSdk = 35

    defaultConfig {
        applicationId = "site.miaokon.android"
        minSdk = 26
        targetSdk = 34
        versionCode = 7
        versionName = "1.2.4"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}
