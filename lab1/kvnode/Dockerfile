# ---- build stage -------------------------------------------------------
# Official Maven image from Docker Hub, bundling Eclipse Temurin (open source).
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /src

# Copy the POM first so Maven's dependency resolution layer is cached
# independently of your source changes.
COPY pom.xml .
RUN mvn -B -q -o dependency:resolve-plugins 2>/dev/null || mvn -B -q dependency:resolve-plugins

COPY src ./src
RUN mvn -B -q package

# ---- runtime stage -----------------------------------------------------
# The JRE image is a lot smaller than the JDK image: nothing here needs a compiler.
FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /src/target/kvnode.jar /app/kvnode.jar

# Documentation only. Note there is deliberately no host port published for
# this service in docker-compose.yml -- see the README.
EXPOSE 8080 9090

ENTRYPOINT ["java", "-jar", "/app/kvnode.jar"]
