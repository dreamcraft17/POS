allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

subprojects {
    // Hanya apply ke Android Library modules
    plugins.withId("com.android.library") {
        // Konfigurasi extension "android" bertipe LibraryExtension (AGP 7/8)
        extensions.configure<com.android.build.api.dsl.LibraryExtension>("android") {
            // Jika namespace belum diset, infer dari package di AndroidManifest.xml
            if (namespace.isNullOrBlank()) {
                val manifestFile = file("src/main/AndroidManifest.xml")
                if (manifestFile.exists()) {
                    val text = manifestFile.readText()
                    val match = Regex("""package\s*=\s*"([^"]+)"""").find(text)
                    val pkg = match?.groupValues?.get(1)
                    if (!pkg.isNullOrBlank()) {
                        namespace = pkg
                        println("✅ Set namespace for project '${project.name}' -> $pkg")
                    } else {
                        println("⚠️  Cannot infer namespace for '${project.name}' (no package in manifest)")
                    }
                } else {
                    println("⚠️  Manifest not found for '${project.name}'")
                }
            }
        }
    }
}