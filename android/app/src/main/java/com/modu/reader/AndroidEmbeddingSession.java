package com.modu.reader;

import ai.onnxruntime.OnnxTensor;
import ai.onnxruntime.OnnxJavaType;
import ai.onnxruntime.OrtEnvironment;
import ai.onnxruntime.OrtSession;
import java.nio.FloatBuffer;
import java.nio.LongBuffer;
import java.util.Arrays;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;

/** CPU-only embedding session. All calls are serialized by the channel owner.
 * No Android/Flutter dependency so the same resource lifecycle can be stress
 * tested on a desktop JVM with the official ONNX Runtime Java artifact.
 */
public final class AndroidEmbeddingSession implements AutoCloseable {
    private OrtSession session;
    private String outputName;

    public void load(String modelPath) throws Exception {
        close();
        try (OrtSession.SessionOptions options = new OrtSession.SessionOptions()) {
            options.setIntraOpNumThreads(1);
            options.setInterOpNumThreads(1);
            options.setExecutionMode(OrtSession.SessionOptions.ExecutionMode.SEQUENTIAL);
            options.setOptimizationLevel(OrtSession.SessionOptions.OptLevel.BASIC_OPT);
            // Long books have changing sequence lengths. Do not retain arena
            // high-water allocations or per-shape memory patterns on phones.
            options.setCPUArenaAllocator(false);
            options.setMemoryPatternOptimization(false);
            options.addCPU(false);
            session = OrtEnvironment.getEnvironment().createSession(modelPath, options);
        }
        try {
            outputName = session.getOutputNames().contains("sentence_embedding")
                    ? "sentence_embedding"
                    : session.getOutputNames().contains("last_hidden_state")
                        ? "last_hidden_state" : session.getOutputNames().iterator().next();
        } catch (Exception error) {
            close();
            throw error;
        }
    }

    public double[] embed(long[] ids, int dimensions) throws Exception {
        if (session == null) throw new IllegalStateException("Model is not loaded");
        if (ids.length == 0 || ids.length > 512 || (dimensions != 384 && dimensions != 512)) {
            throw new IllegalArgumentException("Invalid embedding shape");
        }
        for (long id : ids) if (id < 0) throw new IllegalArgumentException("Invalid token ID");
        long[] shape = {1, ids.length};
        Map<String, OnnxTensor> inputs = new LinkedHashMap<>();
        OrtEnvironment env = OrtEnvironment.getEnvironment();
        try {
            inputs.put("input_ids", OnnxTensor.createTensor(env, LongBuffer.wrap(ids), shape));
            if (session.getInputNames().contains("attention_mask")) {
                long[] mask = new long[ids.length];
                Arrays.fill(mask, 1L);
                inputs.put("attention_mask", OnnxTensor.createTensor(env, LongBuffer.wrap(mask), shape));
            }
            if (session.getInputNames().contains("token_type_ids")) {
                inputs.put("token_type_ids", OnnxTensor.createTensor(env, LongBuffer.wrap(new long[ids.length]), shape));
            }
            try (OrtSession.Result result = session.run(inputs, Collections.singleton(outputName))) {
                OnnxTensor output = (OnnxTensor) result.get(outputName).orElseThrow(
                        () -> new IllegalStateException("Missing embedding output"));
                if (output.getInfo().type != OnnxJavaType.FLOAT) {
                    throw new IllegalArgumentException("Expected float32 embedding output");
                }
                // Pool before crossing the method channel: return only 384/512
                // doubles instead of up to 512 x 512 hidden-state values.
                return pool(output.getFloatBuffer(), output.getInfo().getShape(), ids.length, dimensions);
            }
        } finally {
            for (OnnxTensor tensor : inputs.values()) tensor.close();
        }
    }

    static double[] pool(FloatBuffer values, long[] shape, int tokens, int dimensions) {
        int rows;
        if (shape.length == 3 && shape[0] == 1 && shape[1] == tokens && shape[2] == dimensions) {
            rows = tokens;
        } else if ((shape.length == 2 && shape[0] == 1 && shape[1] == dimensions)
                || (shape.length == 1 && shape[0] == dimensions)) {
            rows = 1;
        } else {
            throw new IllegalArgumentException("Invalid embedding output shape");
        }
        if (values.remaining() != rows * dimensions) throw new IllegalArgumentException("Invalid output size");
        double[] vector = new double[dimensions];
        for (int row = 0; row < rows; row++) {
            for (int i = 0; i < dimensions; i++) vector[i] += values.get();
        }
        double squaredNorm = 0;
        for (int i = 0; i < dimensions; i++) {
            vector[i] /= rows;
            squaredNorm += vector[i] * vector[i];
        }
        double norm = Math.sqrt(squaredNorm);
        if (!Double.isFinite(norm) || norm == 0) throw new IllegalArgumentException("Invalid embedding values");
        for (int i = 0; i < dimensions; i++) vector[i] /= norm;
        return vector;
    }

    @Override
    public void close() throws Exception {
        OrtSession previous = session;
        session = null;
        outputName = null;
        if (previous != null) previous.close();
    }
}
