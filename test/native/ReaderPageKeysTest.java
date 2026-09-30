package com.modu.reader;

public final class ReaderPageKeysTest {
    private static void equal(int expected, int actual) {
        if (expected != actual) throw new AssertionError(expected + " != " + actual);
    }
    public static void main(String[] args) {
        ReaderPageKeys keys = new ReaderPageKeys();
        for (int key : new int[]{19, 20, 21, 22, 92, 93}) {
            int direction = key == 19 || key == 21 || key == 92 ? -1 : 1;
            equal(direction, keys.handle(key, 0, 0, 7, true, false, false));
            equal(2, keys.handle(key, 0, 1, 7, true, false, false));
            equal(2, keys.handle(key, 1, 0, 7, false, false, false));
            equal(0, keys.handle(key, 1, 0, 7, true, false, false));
            equal(0, keys.handle(key, 0, 0, 7, false, true, false));
            equal(0, keys.handle(key, 0, 0, 7, true, true, true));
        }
        for (int key : new int[]{24, 25}) {
            equal(0, keys.handle(key, 0, 0, 7, true, false, false));
            equal(key == 24 ? -1 : 1, keys.handle(key, 0, 0, 7, true, true, false));
            equal(2, keys.handle(key, 1, 0, 7, true, false, false));
        }
        for (int key : new int[]{26, 85, 87, 88, 66, 4, 3, 29}) {
            equal(0, keys.handle(key, 0, 0, 7, true, true, false));
        }
        equal(1, keys.handle(20, 0, 0, 7, true, false, false));
        equal(1, keys.handle(20, 0, 0, 8, true, false, false));
        equal(2, keys.handle(20, 1, 0, 7, true, false, false));
        equal(2, keys.handle(20, 0, 1, 8, true, false, false));
        keys.reset();
        equal(0, keys.handle(20, 0, 2, 8, true, false, false));
        equal(1, keys.handle(20, 0, 0, 8, true, false, false));
        System.out.println("ReaderPageKeys: direction, volume opt-in, repeat, key-up, lifecycle and device tests passed");
    }
}
