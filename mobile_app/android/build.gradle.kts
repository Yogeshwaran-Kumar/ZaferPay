

import org.jetbrains.kotlin.gradle.tasks.KotlinCompile
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// Fix for plugins: missing namespace, compileSdk, and JVM target inconsistency
// Force Java 17 + Kotlin JVM 17 + compileSdk 34 on all subprojects (except :app).
subprojects {
    if (name == "app") return@subprojects
    afterEvaluate {
        if (project.hasProperty("android")) {
            val android = project.extensions.getByName("android")
            // Fix missing namespace
            if (android is com.android.build.gradle.LibraryExtension) {
                if (android.namespace == null) {
                    android.namespace = project.group.toString()
                }
            }
            // Force compileSdk and Java 17 compile options on all plugin subprojects
            if (android is com.android.build.gradle.BaseExtension) {
                if (android.compileSdkVersion == null || android.compileSdkVersion!!.substringAfter("android-", "0").toIntOrNull() ?: 0 < 34) {
                    android.compileSdkVersion(34)
                }
                android.compileOptions.sourceCompatibility = JavaVersion.VERSION_17
                android.compileOptions.targetCompatibility = JavaVersion.VERSION_17
            }
            // Force Kotlin JVM 17 target
            tasks.withType<KotlinCompile>().configureEach {
                compilerOptions {
                    jvmTarget.set(JvmTarget.JVM_17)
                }
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
