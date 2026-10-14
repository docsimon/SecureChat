# Same shape as AuthServer/Dockerfile: the build stage never ships.
FROM eclipse-temurin:21-jdk AS build
WORKDIR /workspace
COPY gradlew build.gradle.kts settings.gradle.kts ./
COPY gradle ./gradle
RUN ./gradlew --no-daemon dependencies || true
COPY src ./src
RUN ./gradlew --no-daemon shadowJar

FROM eclipse-temurin:21-jre
RUN groupadd --system relay \
    && useradd --system --gid relay relay
WORKDIR /app
COPY --from=build /workspace/build/libs/*-all.jar app.jar
USER relay
EXPOSE 8081
ENTRYPOINT ["java", "-jar", "app.jar"]
