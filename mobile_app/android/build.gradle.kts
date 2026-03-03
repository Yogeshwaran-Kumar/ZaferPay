allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.layout.buildDirectory.set(rootProject.projectDir.parentFile.resolve("build"))

subprojects {
    project.layout.buildDirectory.set(rootProject.layout.buildDirectory.get().asFile.resolve(project.name))

    // Fix namespace EARLY — before AGP creates variant instances
    project.plugins.whenPluginAdded {
        if (this.javaClass.name == "com.android.build.gradle.LibraryPlugin") {
            project.extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)?.let { android ->
                if (android.namespace.isNullOrEmpty()) {
                    val manifestFile = project.file("src/main/AndroidManifest.xml")
                    if (manifestFile.exists()) {
                        val manifest = groovy.xml.XmlSlurper().parse(manifestFile)
                        val packageName = manifest.getProperty("@package")?.toString()
                        if (!packageName.isNullOrEmpty()) {
                            android.namespace = packageName
                        }
                    }
                }
            }
        }
    }

    afterEvaluate {
        if (project.plugins.hasPlugin("com.android.library")) {
            val android = project.extensions.getByName("android") as com.android.build.gradle.LibraryExtension

            // Bump compileSdk for old plugins that have compileSdk < 33
            if (android.compileSdkVersion != null) {
                val currentSdk = android.compileSdkVersion!!.removePrefix("android-").toIntOrNull() ?: 0
                if (currentSdk < 33) {
                    android.compileSdk = 33
                }
            }

            // Fix JVM target mismatch - force Java 17 in Android compileOptions
            android.compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
        }

        // Also fix Kotlin JVM target for all subprojects
        try {
            tasks.withType(org.jetbrains.kotlin.gradle.tasks.KotlinCompile::class.java).configureEach {
                compilerOptions {
                    jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
                }
            }
        } catch (_: Exception) {
            // Skip if Kotlin plugin not applied
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
