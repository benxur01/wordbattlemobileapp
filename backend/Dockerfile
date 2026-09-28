# ---- build ----
FROM maven:3.9-eclipse-temurin-25 AS build
WORKDIR /build
# Dependencies first: they only change when the pom does.
COPY pom.xml .
RUN mvn -B -q dependency:go-offline
COPY src ./src
RUN mvn -B -q clean package -DskipTests

# ---- run ----
# The same Java major as the build stage and pom.xml's <java.version>: classes
# compiled for 25 do not load on an older runtime, and the image fails at
# startup with UnsupportedClassVersionError rather than at build time.
FROM eclipse-temurin:25-jre-alpine
WORKDIR /app
RUN addgroup -S app && adduser -S app -G app
COPY --from=build /build/target/wordbattle-backend-*.jar app.jar
USER app
EXPOSE 8080
ENV JAVA_OPTS="-XX:MaxRAMPercentage=75"
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s \
  CMD wget -qO- http://localhost:8080/actuator/health/readiness || exit 1
ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar"]
