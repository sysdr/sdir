FROM maven:3.9-eclipse-temurin-11 AS builder
WORKDIR /app
COPY pom.xml .
COPY src ./src
RUN mvn clean package -DskipTests

FROM flink:1.18-java11
COPY --from=builder /app/target/flink-state-demo-1.0.jar /opt/flink/usrlib/job.jar
