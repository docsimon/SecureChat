import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

plugins {
    kotlin("jvm") version "2.3.21"
    kotlin("plugin.serialization") version "2.3.21"
    id("io.ktor.plugin") version "3.5.2"
    application
}

group = "chat.securechat"
version = "0.1.0"

repositories {
    mavenCentral()
}

application {
    mainClass.set("chat.securechat.auth.ApplicationKt")
}

dependencies {
    implementation("io.ktor:ktor-server-core")
    implementation("io.ktor:ktor-server-netty")
    implementation("io.ktor:ktor-server-content-negotiation")
    implementation("io.ktor:ktor-serialization-kotlinx-json")
    implementation("io.ktor:ktor-server-call-logging")
    implementation("io.ktor:ktor-server-status-pages")
    implementation("io.ktor:ktor-server-body-limit")
    implementation("ch.qos.logback:logback-classic:1.5.16")

    // App Attest verification — do not hand-roll ASN.1/CBOR parsing.
    // See AuthServer/README.md.
    implementation("ch.veehait.devicecheck:devicecheck-appattest:0.9.4")

    // Ephemeral state (challenges, session nonces, session tokens).
    implementation("redis.clients:jedis:5.2.0")

    // Durable state (accounts). Plain JDBC + a pool — the schema is one
    // table, an ORM would be pure overhead.
    implementation("org.postgresql:postgresql:42.7.4")
    implementation("com.zaxxer:HikariCP:6.2.1")

    testImplementation(kotlin("test"))
    testImplementation("io.ktor:ktor-server-test-host")
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
