package com.example;

import org.apache.flink.api.common.functions.RichFlatMapFunction;
import org.apache.flink.api.common.state.ValueState;
import org.apache.flink.api.common.state.ValueStateDescriptor;
import org.apache.flink.api.common.typeinfo.TypeHint;
import org.apache.flink.api.common.typeinfo.TypeInformation;
import org.apache.flink.api.java.tuple.Tuple2;
import org.apache.flink.configuration.Configuration;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.streaming.api.functions.source.SourceFunction;
import org.apache.flink.util.Collector;
import org.apache.flink.streaming.api.functions.sink.SinkFunction;
import org.apache.flink.runtime.state.hashmap.HashMapStateBackend;
import org.apache.flink.streaming.api.CheckpointingMode;

import java.util.Random;

public class StatefulWordCount {
    
    public static class WordSource implements SourceFunction<String> {
        private volatile boolean running = true;
        private final String[] words = {"apache", "flink", "kafka", "streams", "state", "checkpoint"};
        private final Random random = new Random();
        
        @Override
        public void run(SourceContext<String> ctx) throws Exception {
            while (running) {
                ctx.collect(words[random.nextInt(words.length)]);
                Thread.sleep(100);
            }
        }
        
        @Override
        public void cancel() {
            running = false;
        }
    }
    
    public static class StatefulCounter extends RichFlatMapFunction<String, Tuple2<String, Long>> {
        private transient ValueState<Long> countState;
        private transient ValueState<Long> checkpointCount;
        
        @Override
        public void open(Configuration config) {
            ValueStateDescriptor<Long> descriptor = new ValueStateDescriptor<>(
                "word-count",
                TypeInformation.of(new TypeHint<Long>() {})
            );
            countState = getRuntimeContext().getState(descriptor);
            
            ValueStateDescriptor<Long> checkpointDescriptor = new ValueStateDescriptor<>(
                "checkpoint-count",
                TypeInformation.of(new TypeHint<Long>() {})
            );
            checkpointCount = getRuntimeContext().getState(checkpointDescriptor);
        }
        
        @Override
        public void flatMap(String word, Collector<Tuple2<String, Long>> out) throws Exception {
            Long current = countState.value();
            if (current == null) {
                current = 0L;
            }
            current++;
            countState.update(current);
            
            out.collect(new Tuple2<>(word, current));
        }
    }
    
    public static void main(String[] args) throws Exception {
        final StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
        
        // Configure checkpointing
        env.enableCheckpointing(5000); // checkpoint every 5 seconds
        env.getCheckpointConfig().setCheckpointingMode(CheckpointingMode.EXACTLY_ONCE);
        env.getCheckpointConfig().setMinPauseBetweenCheckpoints(1000);
        env.getCheckpointConfig().setCheckpointTimeout(60000);
        
        // Use HashMapStateBackend with file system checkpoint storage
        env.setStateBackend(new HashMapStateBackend());
        env.getCheckpointConfig().setCheckpointStorage("file:///tmp/checkpoints");
        
        env.addSource(new WordSource())
           .keyBy(word -> word)
           .flatMap(new StatefulCounter())
           .addSink(new SinkFunction<Tuple2<String, Long>>() {
               @Override
               public void invoke(Tuple2<String, Long> value, Context context) {
                   System.out.println("Flink: " + value.f0 + " -> " + value.f1);
               }
           });
        
        env.execute("Flink Stateful Word Count");
    }
}
