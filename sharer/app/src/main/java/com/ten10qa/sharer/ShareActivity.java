package com.ten10qa.sharer;

import android.app.Activity;
import android.content.ClipData;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.util.Log;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;

/** Shares like a real app: text, or a file from its own provider with a read grant + ClipData. */
public class ShareActivity extends Activity {
    @Override protected void onCreate(Bundle b) {
        super.onCreate(b);
        String pkg = getIntent().getStringExtra("pkg");
        String mode = getIntent().getStringExtra("mode");
        Intent send = new Intent(Intent.ACTION_SEND);
        try {
            if ("file".equals(mode)) {
                File f = new File(getCacheDir(), "receipt.png");
                try (InputStream in = getResources().openRawResource(R.raw.receipt); FileOutputStream out = new FileOutputStream(f)) {
                    byte[] buf = new byte[8192]; int n; while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
                }
                Uri uri = Uri.parse("content://com.ten10qa.sharer.files/receipt.png");
                send.setType("image/png");
                send.putExtra(Intent.EXTRA_STREAM, uri);
                send.setClipData(ClipData.newRawUri("receipt", uri));
                send.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            } else {
                send.setType("text/plain");
                send.putExtra(Intent.EXTRA_TEXT, getIntent().getStringExtra("text"));
            }
            send.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            if (pkg != null && !pkg.isEmpty()) send.setPackage(pkg);
            if (getIntent().getBooleanExtra("chooser", false)) {
                Intent c = Intent.createChooser(send, "Share to");
                c.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                startActivity(c);
            } else {
                startActivity(send);
            }
            Log.i("Ten10QaSharer", "sent " + mode + " to " + pkg);
        } catch (Exception e) {
            Log.e("Ten10QaSharer", "share failed", e);
        }
        finish();
    }
}
