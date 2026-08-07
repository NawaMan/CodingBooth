package com.example.hello;

import android.app.Activity;
import android.os.Bundle;
import android.view.Gravity;
import android.widget.TextView;

/**
 * The whole app: one Activity showing one string.
 *
 * Deliberately built without a layout XML — the point of this example is the
 * toolchain (aapt2, javac, d8, apksigner), not the UI, and a programmatic view
 * keeps the resource table small enough to read in the aapt2 dump.
 */
public class MainActivity extends Activity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        TextView text = new TextView(this);
        text.setText(getString(R.string.greeting));
        text.setTextSize(22);
        text.setGravity(Gravity.CENTER);

        setContentView(text);
    }
}
