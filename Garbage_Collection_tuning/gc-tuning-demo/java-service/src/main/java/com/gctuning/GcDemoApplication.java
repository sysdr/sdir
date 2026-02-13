package com.gctuning;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@EnableScheduling
public class GcDemoApplication {
    public static void main(String[] args) {
        SpringApplication.run(GcDemoApplication.class, args);
    }
}
