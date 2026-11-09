# ---- build stage -------------------------------------------------------
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /src
COPY pom.xml .
RUN mvn -B -q -o dependency:resolve-plugins 2>/dev/null || mvn -B -q dependency:resolve-plugins
COPY src ./src
RUN mvn -B -q package

# ---- runtime stage -----------------------------------------------------
FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /src/target/kvnode.jar /app/kvnode.jar

# Documentation only. There is deliberately no host port published for these
# services in docker-compose.yml -- see the README.
EXPOSE 8080 9090

ENTRYPOINT ["java", "-jar", "/app/kvnode.jar"]
