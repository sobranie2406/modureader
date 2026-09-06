package com.modu.reader;

import java.io.File;
import java.nio.FloatBuffer;
import java.util.Arrays;

/** Real ONNX CPU inference; synthetic valid token IDs, never user books.
 * Run with the official onnxruntime Java JAR and the bundled model directory.
 * Host JVM testing is not Android/iQOO device acceptance.
 */
public final class AndroidEmbeddingStress {
    private static long rssKB() throws Exception {
        Process p = new ProcessBuilder("ps", "-o", "rss=", "-p",
                Long.toString(ProcessHandle.current().pid())).start();
        String s = new String(p.getInputStream().readAllBytes()).trim();
        if (p.waitFor() != 0) throw new AssertionError("RSS measurement failed");
        return Long.parseLong(s);
    }

    private static void verify(double[] vector, int size) {
        if (vector.length != size) throw new AssertionError("Wrong dimension");
        double norm = 0;
        for (double v : vector) {
            if (!Double.isFinite(v)) throw new AssertionError("Nonfinite output");
            norm += v * v;
        }
        if (Math.abs(norm - 1) > 0.0001) throw new AssertionError("Not normalized");
    }

    public static void main(String[] args) throws Exception {
        // Pooling agrees with the Dart implementation for token and sentence outputs.
        float[] fixture = new float[768];
        fixture[0] = 3; fixture[384 + 1] = 4;
        double[] pooled = AndroidEmbeddingSession.pool(FloatBuffer.wrap(fixture), new long[]{1, 2, 384}, 2, 384);
        if (Math.abs(pooled[0] - .6) > 1e-9 || Math.abs(pooled[1] - .8) > 1e-9) throw new AssertionError("Pooling mismatch");
        try {
            AndroidEmbeddingSession.pool(FloatBuffer.wrap(new float[384]), new long[]{1, 384}, 1, 384);
            throw new AssertionError("Zero vector accepted");
        } catch (IllegalArgumentException expected) { }

        String[] models = {"all-MiniLM-L6-v2", "bge-small-en-v1.5", "bge-small-zh-v1.5", "multilingual-e5-small"};
        int[] lengths = {16, 64, 128, 256, 512, 96, 384, 32};
        for (String model : models) {
            int dim = model.contains("-zh-") ? 512 : 384;
            String path = new File(args[0], model + "/model_quantized.onnx").getPath();
            try (AndroidEmbeddingSession engine = new AndroidEmbeddingSession()) {
                engine.load(path);
                long baseline = 0;
                for (int i = 0; i < 80; i++) {
                    long[] ids = new long[lengths[i % lengths.length]];
                    Arrays.fill(ids, 1000 + i);
                    ids[0] = 101; ids[ids.length - 1] = 102;
                    verify(engine.embed(ids, dim), dim);
                    if (i == 15 || i == 79) {
                        System.gc(); Thread.sleep(100);
                        long rss = rssKB();
                        if (i == 15) baseline = rss;
                        System.out.println(model + " runs=" + (i + 1) + " RSS_KiB=" + rss);
                        if (i == 79 && rss - baseline > 128 * 1024) throw new AssertionError("Unbounded memory growth");
                    }
                }
                try { engine.embed(new long[513], dim); throw new AssertionError("Overlong input accepted"); }
                catch (IllegalArgumentException expected) { }
                for (int reload = 0; reload < 3; reload++) {
                    engine.close();
                    engine.load(path);
                    verify(engine.embed(new long[]{101, 1000, 102}, dim), dim);
                }
                System.out.println("HOST NATIVE STRESS PASS: " + model + " dimension=" + dim + " runs=83");
            }
        }
    }
}
