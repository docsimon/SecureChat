import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

plugins {
    kotlin("jvm") version "2.3.21"
    id("io.ktor.plugin") version "3.5.2"
    application
}

group = "chat.securechat"
version = "0.1.0"

repositories {
    mavenCentral()
}

application {
    mainClass.set("chat.securechat.relay.ApplicationKt")
}

dependencies {
    implementation("io.ktor:ktor-server-core")
    implementation("io.ktor:ktor-server-netty")
    implementation("io.ktor:ktor-server-websockets")
    implementation("ch.qos.logback:logback-classic:1.5.16")

    // Session tokens are issued by the Auth Server into Redis; the relay
    // only reads them.
    implementation("redis.clients:jedis:5.2.0")

    testImplementation(kotlin("test"))
    testImplementation("io.ktor:ktor-server-test-host")
    testImplementation("io.ktor:ktor-client-websockets")
}

kotlin {
    jvmToolchain(21)
}

tasks.withType<KotlinCompile> {
    compilerOptions {
        freeCompilerArgs.add("-Xjsr305=strict")
    }
}

tasks.test {
    useJUnitPlatform()
}
