FROM maven:3.9.6-eclipse-temurin-21 AS builder
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline -q
COPY src ./src
RUN mvn package -DskipTests -q

FROM eclipse-temurin:21-jre-jammy
WORKDIR /app
COPY --from=builder /app/target/*.jar app.jar

# GC_FLAGS is passed at runtime via environment variable
ENV GC_FLAGS="-XX:+UseG1GC -XX:MaxGCPauseMillis=200"
ENV HEAP_SIZE="-Xms256m -Xmx512m"
ENV GC_TYPE="G1GC"

EXPOSE 8080
ENTRYPOINT sh -c "java \
  $HEAP_SIZE \
  $GC_FLAGS \
  -Xlog:gc*:stdout:time,uptime,level,tags \
  -Dgc.type=$GC_TYPE \
  -jar app.jar"
