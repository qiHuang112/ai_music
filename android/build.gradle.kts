allprojects {
    repositories {
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/central") }
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

val pluginProjectNdkVersion = "27.0.11718014"

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
    // Some transitive Android libraries otherwise fall back to a stale
    // sdk/ndk-bundle. Keep every native plugin on the app's installed NDK.
    afterEvaluate {
        extensions
            .findByType(com.android.build.api.dsl.LibraryExtension::class.java)
            ?.ndkVersion = pluginProjectNdkVersion
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
