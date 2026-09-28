# Multi-stage: the build stage never ships. Same image locally and in any
# real deployment later — only env vars differ (see Config.kt).
FROM eclipse-temurin:21-jdk AS build
WORKDIR /workspace
COPY gradlew build.gradle.kts settings.gradle.kts ./
COPY gradle ./gradle
RUN ./gradlew --no-daemon dependencies || true
COPY src ./src
RUN ./gradlew --no-daemon shadowJar

FROM eclipse-temurin:21-jre
RUN groupadd --system authserver \
    && useradd --system --gid authserver authserver
WORKDIR /app
COPY --from=build /workspace/build/libs/*-all.jar app.jar
# Runs as an unprivileged user, not root — standard container hardening,
# confirmed as an actual gap (root) during this session's security review.
USER authserver
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
