package com.cantoo.plugins.documentio;

import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.provider.OpenableColumns;
import android.util.Base64;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.HashMap;
import java.util.Map;

/**
 * Reads and writes a document the system opened, in place.
 * content:// URIs stay on the original document (truncate write, no copy).
 */
@CapacitorPlugin(name = "DocumentIo")
public class DocumentIoPlugin extends Plugin {

    private final Map<String, Integer> persistedFlags = new HashMap<>();

    @Override
    protected void handleOnNewIntent(Intent intent) {
        super.handleOnNewIntent(intent);
        persistFromIntent(intent);
    }

    @PluginMethod
    public void prepareOpenedDocument(PluginCall call) {
        String url = call.getString("url");
        if (url == null || url.isEmpty()) {
            call.reject("url is required");
            return;
        }

        Uri uri = Uri.parse(url);
        Intent intent = getActivity() != null ? getActivity().getIntent() : null;
        if (intent != null && uri.equals(intent.getData())) {
            persistFromIntent(intent);
        } else if ("content".equals(uri.getScheme())) {
            persist(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            );
        }

        JSObject result = new JSObject();
        result.put("uri", uri.toString());
        call.resolve(result);
    }

    @PluginMethod
    public void getInfo(PluginCall call) {
        String uriValue = call.getString("uri");
        if (uriValue == null || uriValue.isEmpty()) {
            call.reject("uri is required");
            return;
        }

        try {
            String name = resolveDisplayName(Uri.parse(uriValue));
            JSObject result = new JSObject();
            result.put("name", name != null ? name : "");
            call.resolve(result);
        } catch (Exception error) {
            call.reject("Failed to get document info: " + error.getMessage());
        }
    }

    @PluginMethod
    public void read(PluginCall call) {
        String uri = call.getString("uri");
        if (uri == null || uri.isEmpty()) {
            call.reject("uri is required");
            return;
        }

        try {
            byte[] data = readBytes(uri);
            JSObject result = new JSObject();
            result.put("data", Base64.encodeToString(data, Base64.NO_WRAP));
            call.resolve(result);
        } catch (Exception error) {
            call.reject("Failed to read document: " + error.getMessage());
        }
    }

    @PluginMethod
    public void write(PluginCall call) {
        String uri = call.getString("uri");
        String base64 = call.getString("data");
        if (uri == null || uri.isEmpty()) {
            call.reject("uri is required");
            return;
        }
        if (base64 == null) {
            call.reject("data is required");
            return;
        }

        try {
            writeBytes(uri, Base64.decode(base64, Base64.DEFAULT));
            call.resolve();
        } catch (Exception error) {
            call.reject("Failed to write document: " + error.getMessage());
        }
    }

    @PluginMethod
    public void release(PluginCall call) {
        String uriValue = call.getString("uri");
        if (uriValue == null || uriValue.isEmpty()) {
            call.reject("uri is required");
            return;
        }

        Integer flags = persistedFlags.remove(Uri.parse(uriValue).toString());
        if (flags != null && getContext() != null) {
            try {
                getContext()
                    .getContentResolver()
                    .releasePersistableUriPermission(Uri.parse(uriValue), flags);
            } catch (SecurityException ignored) {
                // The grant may already have been revoked by the provider.
            }
        }
        call.resolve();
    }

    private void persistFromIntent(Intent intent) {
        if (intent == null) return;
        Uri uri = intent.getData();
        if (uri == null || !"content".equals(uri.getScheme())) return;

        int flags =
            intent.getFlags() &
            (Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
        persist(uri, flags);
    }

    private void persist(Uri uri, int flags) {
        if (getContext() == null || uri == null || flags == 0) return;
        try {
            getContext().getContentResolver().takePersistableUriPermission(uri, flags);
            persistedFlags.put(uri.toString(), flags);
        } catch (SecurityException ignored) {
            // VIEW grants are often temporary. They still work for this activity session.
        }
    }

    /**
     * Prefer OpenableColumns.DISPLAY_NAME for content:// (path usually has no extension).
     * Fall back to the last path segment / file name for file:// and opaque providers.
     */
    private String resolveDisplayName(Uri uri) {
        if ("content".equals(uri.getScheme()) && getContext() != null) {
            try (
                Cursor cursor = getContext()
                    .getContentResolver()
                    .query(uri, new String[] { OpenableColumns.DISPLAY_NAME }, null, null, null)
            ) {
                if (cursor != null && cursor.moveToFirst()) {
                    int index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME);
                    if (index >= 0) {
                        String displayName = cursor.getString(index);
                        if (displayName != null && !displayName.isEmpty()) {
                            return displayName;
                        }
                    }
                }
            } catch (Exception ignored) {
                // Some providers reject the projection; fall through to path segment.
            }
            return uri.getLastPathSegment();
        }

        if ("file".equals(uri.getScheme()) && uri.getPath() != null) {
            return new File(uri.getPath()).getName();
        }

        String last = uri.getLastPathSegment();
        if (last != null && !last.isEmpty()) return last;
        if (uri.getPath() != null) return new File(uri.getPath()).getName();
        return null;
    }

    private byte[] readBytes(String path) throws Exception {
        Uri uri = Uri.parse(path);
        if ("content".equals(uri.getScheme())) {
            try (InputStream input = getContext().getContentResolver().openInputStream(uri)) {
                if (input == null) throw new Exception("Unable to open " + path);
                return readAll(input);
            }
        }

        try (InputStream input = new FileInputStream(fileFrom(uri, path))) {
            return readAll(input);
        }
    }

    private void writeBytes(String path, byte[] data) throws Exception {
        Uri uri = Uri.parse(path);
        if ("content".equals(uri.getScheme())) {
            // "wt" truncates the existing document. Creating a new file drops it from the folder.
            try (OutputStream output = getContext().getContentResolver().openOutputStream(uri, "wt")) {
                if (output == null) throw new Exception("Unable to open " + path + " for writing");
                output.write(data);
            }
            return;
        }

        try (OutputStream output = new FileOutputStream(fileFrom(uri, path), false)) {
            output.write(data);
        }
    }

    private static File fileFrom(Uri uri, String path) {
        if ("file".equals(uri.getScheme()) && uri.getPath() != null) {
            return new File(uri.getPath());
        }
        return new File(path);
    }

    private static byte[] readAll(InputStream input) throws Exception {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        byte[] buffer = new byte[8192];
        int read;
        while ((read = input.read(buffer)) != -1) {
            output.write(buffer, 0, read);
        }
        return output.toByteArray();
    }
}
