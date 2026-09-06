package com.modu.reader;

import android.app.Activity;
import android.app.Instrumentation;
import android.os.Bundle;
import android.util.Log;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.util.Arrays;

/** Runs only in an isolated emulator against the minified release application.
 * No Flutter activity, user book, network request or production crash is needed.
 */
public final class EmbeddingReleaseInstrumentation extends Instrumentation {
    @Override public void onCreate(Bundle args) {
        super.onCreate(args);
        start();
    }

    @Override public void onStart() {
        Bundle result = new Bundle();
        String[] models = {"all-MiniLM-L6-v2", "bge-small-en-v1.5",
                "bge-small-zh-v1.5", "multilingual-e5-small"};
        int runs = 0;
        try {
            for (String model : models) {
                File copy = File.createTempFile("modu-release-inference-", ".onnx",
                        getTargetContext().getCacheDir());
                try {
                    try (InputStream in = getTargetContext().getAssets().open(
                            "flutter_assets/assets/models/embeddings/" + model + "/model_quantized.onnx");
                         FileOutputStream out = new FileOutputStream(copy)) {
                        byte[] buffer = new byte[65536];
                        int size;
                        while ((size = in.read(buffer)) != -1) out.write(buffer, 0, size);
                    }
                    try (AndroidEmbeddingSession engine = new AndroidEmbeddingSession()) {
                        engine.load(copy.getAbsolutePath());
                        for (int length : new int[]{16, 512, 64}) {
                            long[] tokens = new long[length];
                            Arrays.fill(tokens, 1000);
                            tokens[0] = 101;
                            tokens[length - 1] = 102;
                            int dim = model.contains("-zh-") ? 512 : 384;
                            double[] vector = engine.embed(tokens, dim);
                            if (vector.length != dim) throw new AssertionError("Wrong dimension");
                            double norm = 0;
                            for (double value : vector) {
                                if (!Double.isFinite(value)) throw new AssertionError("Nonfinite value");
                                norm += value * value;
                            }
                            if (Math.abs(norm - 1) > 0.0001) throw new AssertionError("Invalid normalization");
                            runs++;
                        }
                    }
                    Log.i("ModuReleaseTest", "PASS: " + model);
                } finally {
                    if (!copy.delete()) throw new AssertionError("Cannot remove synthetic test model");
                }
            }
            result.putString("stream", "MODU_RELEASE_INFERENCE_PASS models=4 runs=" + runs);
            finish(Activity.RESULT_OK, result);
        } catch (Throwable error) {
            Log.e("ModuReleaseTest", "Release JNI inference failed", error);
            result.putString("stream", "MODU_RELEASE_INFERENCE_FAILED " + error.getClass().getSimpleName());
            finish(Activity.RESULT_CANCELED, result);
        }
    }
}
