package site.miaokon.android;

import android.os.Handler;
import android.os.Looper;

import org.json.JSONObject;

import java.io.BufferedInputStream;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Android side of the existing four-byte length-prefixed JSON TCP protocol. */
final class UsbTcpServer {
    static final int PORT = 7311;
    private static final int MAX_FRAME_BYTES = 65_536;

    interface Listener {
        void onState(String state);
        void onAck(String id);
    }

    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService writer = Executors.newSingleThreadExecutor(task -> {
        Thread thread = new Thread(task, "miaokon-usb-writer");
        thread.setDaemon(true);
        return thread;
    });
    private final Listener listener;
    private volatile boolean running;
    private volatile ServerSocket serverSocket;
    private volatile Socket clientSocket;
    private volatile DataOutputStream output;
    private Thread acceptThread;

    UsbTcpServer(Listener listener) {
        this.listener = listener;
    }

    synchronized void start() {
        if (running) return;
        running = true;
        acceptThread = new Thread(this::acceptLoop, "miaokon-usb-listener");
        acceptThread.start();
    }

    synchronized void restart() {
        stop();
        main.postDelayed(this::start, 300);
    }

    synchronized void stop() {
        running = false;
        closeQuietly(clientSocket);
        closeQuietly(serverSocket);
        clientSocket = null;
        serverSocket = null;
        output = null;
    }

    synchronized boolean isConnected() {
        return clientSocket != null && clientSocket.isConnected() && !clientSocket.isClosed();
    }

    void send(String kind, Double dx, Double dy, Double value, String phase,
              String id, String debug) {
        JSONObject event = new JSONObject();
        try {
            event.put("t", "event");
            event.put("k", kind);
            if (dx != null) event.put("dx", dx);
            if (dy != null) event.put("dy", dy);
            if (value != null) event.put("v", value);
            if (phase != null) event.put("p", phase);
            if (id != null) event.put("id", id);
            if (debug != null) event.put("dbg", debug);
        } catch (Exception ignored) {
            return;
        }
        if (output == null) return;
        String frame = event.toString();
        writer.execute(() -> writeFrame(frame));
    }

    private synchronized void writeFrame(String json) {
        if (output == null) return;
        byte[] body = json.getBytes(StandardCharsets.UTF_8);
        if (body.length > MAX_FRAME_BYTES) return;
        try {
            output.writeInt(body.length); // DataOutputStream uses big-endian, matching iOS/Mac.
            output.write(body);
            output.flush();
        } catch (IOException e) {
            closeQuietly(clientSocket);
            clientSocket = null;
            output = null;
            postState("USB 连接断开，等待 Mac 重连");
        }
    }

    private void acceptLoop() {
        while (running) {
            try (ServerSocket server = new ServerSocket(PORT, 1, InetAddress.getLoopbackAddress())) {
                serverSocket = server;
                postState("USB 服务就绪，等待 Mac（ADB 转发）");
                while (running) {
                    Socket socket = server.accept();
                    socket.setTcpNoDelay(true);
                    closeQuietly(clientSocket);
                    clientSocket = socket;
                    output = new DataOutputStream(socket.getOutputStream());
                    postState("USB 已连接 Mac");
                    readFrames(socket);
                    synchronized (this) {
                        if (clientSocket == socket) {
                            clientSocket = null;
                            output = null;
                        }
                    }
                    closeQuietly(socket);
                    if (running) postState("USB 已断开，等待 Mac 重连");
                }
            } catch (IOException e) {
                if (running) {
                    postState("USB 服务暂不可用，正在重试");
                    try {
                        Thread.sleep(1_000);
                    } catch (InterruptedException interrupted) {
                        Thread.currentThread().interrupt();
                        return;
                    }
                }
            } finally {
                serverSocket = null;
            }
        }
    }

    private void readFrames(Socket socket) throws IOException {
        DataInputStream input = new DataInputStream(new BufferedInputStream(socket.getInputStream()));
        while (running && !socket.isClosed()) {
            int length;
            try {
                length = input.readInt();
            } catch (IOException eof) {
                return;
            }
            if (length < 0 || length > MAX_FRAME_BYTES) return;
            byte[] body = new byte[length];
            input.readFully(body);
            try {
                JSONObject frame = new JSONObject(new String(body, StandardCharsets.UTF_8));
                if ("ack".equals(frame.optString("t"))) {
                    String id = frame.optString("id", "");
                    main.post(() -> listener.onAck(id));
                }
            } catch (Exception ignored) {
                // Ignore malformed or unknown inbound frames and keep the stream alive.
            }
        }
    }

    private void postState(String value) {
        main.post(() -> listener.onState(value));
    }

    private static void closeQuietly(Socket socket) {
        if (socket == null) return;
        try { socket.close(); } catch (IOException ignored) { }
    }

    private static void closeQuietly(ServerSocket socket) {
        if (socket == null) return;
        try { socket.close(); } catch (IOException ignored) { }
    }
}
