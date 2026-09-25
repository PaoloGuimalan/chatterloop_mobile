// CHATTERLOOP PATCH - not part of the published plugin. See the
// video_player_android entry under dependency_overrides in the app's
// pubspec.yaml for why this package is vendored.

package io.flutter.plugins.videoplayer.texture;

import android.graphics.SurfaceTexture;
import android.opengl.EGL14;
import android.opengl.EGLConfig;
import android.opengl.EGLContext;
import android.opengl.EGLDisplay;
import android.opengl.EGLSurface;
import android.opengl.GLES11Ext;
import android.opengl.GLES20;
import android.os.Build;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.Looper;
import android.util.Log;
import android.view.Surface;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.RequiresApi;
import io.flutter.view.TextureRegistry.SurfaceProducer;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.FloatBuffer;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

/**
 * Hands Flutter each video frame CROPPED and UPRIGHT.
 *
 * <p>On Android 10+ a {@link SurfaceProducer} is an ImageReader, and the engine draws the whole
 * buffer it receives: it ignores the buffer's crop rectangle and rotation (flutter/flutter#144407,
 * {@link SurfaceProducer#handlesCropAndRotation()}). A decoder's buffer is usually bigger than the
 * picture - a 1080-wide video is decoded into a buffer 1088 or more wide, and the crop rectangle
 * leaves the extra columns out. Drawn whole, those columns were the green strip down the right of
 * most videos in the app, and the picture was squeezed by the same amount.
 *
 * <p>So the decoder draws into a SurfaceTexture instead, whose transform matrix carries the crop
 * and the rotation, and one GL pass copies exactly the picture onto the producer's surface, at the
 * picture's size - the way a TextureView shows video. Frames reach Flutter upright, so no rotation
 * correction is sent to Dart for these players.
 *
 * <p>One GL thread and context serve every player. The constructor, {@link #setVideoSize}, {@link
 * #onSurfaceAvailable}, {@link #onSurfaceCleanup} and {@link #release} run on the main thread;
 * everything that touches GL runs on the GL thread.
 */
@RequiresApi(Build.VERSION_CODES.O)
final class CroppedVideoOutput implements SurfaceTexture.OnFrameAvailableListener {
  private static final String TAG = "CroppedVideoOutput";

  /**
   * The longest edge of a frame handed to Flutter. A bigger video is drawn scaled down: a phone
   * shows no more than this, and a 4K frame would be 33MB per buffer.
   */
  private static final int MAX_EDGE = 1920;

  private final SurfaceProducer producer;
  private final Gl gl;
  private final SurfaceTexture input;
  private final Surface inputSurface;
  private final Handler mainHandler = new Handler(Looper.getMainLooper());

  private volatile boolean released;

  // Main thread.
  private int width;
  private int height;
  private boolean surfaceCleanedUp;

  // GL thread.
  private int texture;
  private EGLSurface output = EGL14.EGL_NO_SURFACE;
  private int outputWidth;
  private int outputHeight;
  private boolean hasFrame;
  private boolean reattachAsked;
  private final float[] texMatrix = new float[16];

  /**
   * Whether frames can be drawn this way here. Once GL has failed to start it is not tried again,
   * and the players draw straight onto their producers, as the published plugin does.
   */
  static boolean isAvailable() {
    return Gl.shared() != null;
  }

  /** Only after {@link #isAvailable()} said yes. */
  CroppedVideoOutput(@NonNull SurfaceProducer producer) {
    this.producer = producer;
    this.gl = Gl.shared();
    if (gl == null) {
      throw new IllegalStateException("GL is not available");
    }
    // Detached: it is attached to the shared context on the GL thread, before its first frame -
    // the attach is posted to the same thread the frames are delivered on.
    input = new SurfaceTexture(false);
    inputSurface = new Surface(input);
    gl.handler.post(() -> safely("attach", this::attach));
    input.setOnFrameAvailableListener(this, gl.handler);
  }

  /** Where the player's decoder draws. */
  @NonNull
  Surface inputSurface() {
    return inputSurface;
  }

  /** The picture's size, already upright (the player's VideoSize). */
  void setVideoSize(int videoWidth, int videoHeight) {
    if (released || videoWidth <= 0 || videoHeight <= 0) {
      return;
    }
    double scale = Math.min(1.0, (double) MAX_EDGE / Math.max(videoWidth, videoHeight));
    int w = Math.max(1, (int) Math.round(videoWidth * scale));
    int h = Math.max(1, (int) Math.round(videoHeight * scale));
    if (w == width && h == height) {
      return;
    }
    width = w;
    height = h;
    producer.setSize(w, h);
    attachOutput();
  }

  /** Flutter has a surface again (after {@link #onSurfaceCleanup}): redraw onto it. */
  void onSurfaceAvailable() {
    surfaceCleanedUp = false;
    attachOutput();
  }

  /** Flutter is about to destroy the surface: stop drawing on it before this returns. */
  void onSurfaceCleanup() {
    surfaceCleanedUp = true;
    gl.runAndWait(() -> safely("cleanup", this::dropOutput));
  }

  /** After the player is released. */
  void release() {
    released = true;
    input.setOnFrameAvailableListener(null);
    gl.runAndWait(
        () ->
            safely(
                "release",
                () -> {
                  dropOutput();
                  input.release();
                  if (texture != 0) {
                    GLES20.glDeleteTextures(1, new int[] {texture}, 0);
                    texture = 0;
                  }
                }));
    inputSurface.release();
  }

  /** Main thread: point the GL pass at the producer's current surface. */
  private void attachOutput() {
    if (released || surfaceCleanedUp || width == 0) {
      return;
    }
    Surface target = producer.getSurface();
    int w = width;
    int h = height;
    gl.handler.post(() -> safely("output", () -> useOutput(target, w, h)));
  }

  // ---- GL thread.

  private void attach() {
    if (released) {
      return;
    }
    int[] names = new int[1];
    GLES20.glGenTextures(1, names, 0);
    input.attachToGLContext(names[0]);
    GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, names[0]);
    GLES20.glTexParameteri(
        GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR);
    GLES20.glTexParameteri(
        GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR);
    GLES20.glTexParameteri(
        GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE);
    GLES20.glTexParameteri(
        GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE);
    texture = names[0];
  }

  @Override
  public void onFrameAvailable(SurfaceTexture surfaceTexture) {
    safely(
        "frame",
        () -> {
          if (released || texture == 0) {
            return;
          }
          input.updateTexImage();
          input.getTransformMatrix(texMatrix);
          hasFrame = true;
          draw();
        });
  }

  private void useOutput(@NonNull Surface target, int w, int h) {
    if (released) {
      return;
    }
    dropOutput();
    EGLSurface surface = gl.createWindowSurface(target);
    if (surface == EGL14.EGL_NO_SURFACE) {
      return;
    }
    output = surface;
    outputWidth = w;
    outputHeight = h;
    // Right away, not at the next frame: a paused video's first frame, or the frame it was on
    // before the app went to the background.
    draw();
  }

  private void dropOutput() {
    if (output == EGL14.EGL_NO_SURFACE) {
      return;
    }
    gl.makeCurrent(gl.pbuffer);
    EGL14.eglDestroySurface(gl.display, output);
    output = EGL14.EGL_NO_SURFACE;
  }

  private void draw() {
    if (!hasFrame || output == EGL14.EGL_NO_SURFACE) {
      return;
    }
    boolean drawn =
        gl.makeCurrent(output)
            && gl.drawFrame(texture, texMatrix, outputWidth, outputHeight)
            && EGL14.eglSwapBuffers(gl.display, output);
    if (drawn) {
      reattachAsked = false;
      return;
    }
    Log.w(TAG, "Could not draw a frame: EGL error 0x" + Integer.toHexString(EGL14.eglGetError()));
    // Most likely Flutter replaced the surface; ask for its current one, once per failure run.
    dropOutput();
    if (!reattachAsked) {
      reattachAsked = true;
      mainHandler.post(this::attachOutput);
    }
  }

  /** A GL-thread task that must never take the app down with it. */
  private static void safely(@NonNull String what, @NonNull Runnable task) {
    try {
      task.run();
    } catch (RuntimeException e) {
      Log.e(TAG, "Video frame " + what + " failed", e);
    }
  }

  /** The one GL thread and context every player's frames are drawn on. */
  private static final class Gl {
    private static final long WAIT_MS = 1000;

    private static final String VERTEX_SHADER =
        "uniform mat4 uTexMatrix;\n"
            + "attribute vec4 aPosition;\n"
            + "attribute vec4 aTexCoord;\n"
            + "varying vec2 vTexCoord;\n"
            + "void main() {\n"
            + "  gl_Position = aPosition;\n"
            + "  vTexCoord = (uTexMatrix * aTexCoord).xy;\n"
            + "}\n";

    // highp where there is one: mediump can't address every row of a 1920-tall frame.
    private static final String FRAGMENT_SHADER =
        "#extension GL_OES_EGL_image_external : require\n"
            + "#ifdef GL_FRAGMENT_PRECISION_HIGH\n"
            + "precision highp float;\n"
            + "#else\n"
            + "precision mediump float;\n"
            + "#endif\n"
            + "varying vec2 vTexCoord;\n"
            + "uniform samplerExternalOES sTexture;\n"
            + "void main() {\n"
            + "  gl_FragColor = texture2D(sTexture, vTexCoord);\n"
            + "}\n";

    @Nullable private static Gl shared;
    private static boolean failed;

    @Nullable
    static synchronized Gl shared() {
      if (shared == null && !failed) {
        Gl gl = new Gl();
        if (gl.start()) {
          shared = gl;
        } else {
          failed = true;
          gl.thread.quitSafely();
        }
      }
      return shared;
    }

    final Handler handler;
    private final HandlerThread thread;
    EGLDisplay display = EGL14.EGL_NO_DISPLAY;
    private EGLContext context = EGL14.EGL_NO_CONTEXT;
    private EGLConfig config;
    EGLSurface pbuffer = EGL14.EGL_NO_SURFACE;
    private int program;
    private int positionAttribute;
    private int texCoordAttribute;
    private int texMatrixUniform;
    // A full-surface quad, and the texture corners the SurfaceTexture's matrix maps from.
    private final FloatBuffer positions = floats(-1, -1, 1, -1, -1, 1, 1, 1);
    private final FloatBuffer texCoords = floats(0, 0, 1, 0, 0, 1, 1, 1);

    private Gl() {
      thread = new HandlerThread("ChatterloopVideoGl");
      thread.start();
      handler = new Handler(thread.getLooper());
    }

    private boolean start() {
      boolean[] ok = {false};
      runAndWait(
          () ->
              safely(
                  "setup",
                  () -> {
                    ok[0] = setUp();
                  }));
      return ok[0];
    }

    private boolean setUp() {
      display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY);
      int[] version = new int[2];
      if (display == EGL14.EGL_NO_DISPLAY
          || !EGL14.eglInitialize(display, version, 0, version, 1)) {
        return failed("eglInitialize");
      }
      int[] attributes = {
        EGL14.EGL_RED_SIZE, 8,
        EGL14.EGL_GREEN_SIZE, 8,
        EGL14.EGL_BLUE_SIZE, 8,
        EGL14.EGL_ALPHA_SIZE, 8,
        EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
        EGL14.EGL_SURFACE_TYPE, EGL14.EGL_WINDOW_BIT | EGL14.EGL_PBUFFER_BIT,
        EGL14.EGL_NONE
      };
      EGLConfig[] configs = new EGLConfig[1];
      int[] count = new int[1];
      if (!EGL14.eglChooseConfig(display, attributes, 0, configs, 0, 1, count, 0)
          || count[0] == 0) {
        return failed("eglChooseConfig");
      }
      config = configs[0];
      context =
          EGL14.eglCreateContext(
              display,
              config,
              EGL14.EGL_NO_CONTEXT,
              new int[] {EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE},
              0);
      if (context == null || context == EGL14.EGL_NO_CONTEXT) {
        return failed("eglCreateContext");
      }
      // Kept current whenever no player's surface is: textures are made and frames latched with
      // the context current, whichever surface it is on.
      pbuffer =
          EGL14.eglCreatePbufferSurface(
              display, config, new int[] {EGL14.EGL_WIDTH, 1, EGL14.EGL_HEIGHT, 1, EGL14.EGL_NONE}, 0);
      if (pbuffer == null || pbuffer == EGL14.EGL_NO_SURFACE || !makeCurrent(pbuffer)) {
        return failed("pbuffer");
      }
      program = link();
      if (program == 0) {
        return false;
      }
      positionAttribute = GLES20.glGetAttribLocation(program, "aPosition");
      texCoordAttribute = GLES20.glGetAttribLocation(program, "aTexCoord");
      texMatrixUniform = GLES20.glGetUniformLocation(program, "uTexMatrix");
      return true;
    }

    boolean makeCurrent(@NonNull EGLSurface surface) {
      return EGL14.eglMakeCurrent(display, surface, surface, context);
    }

    @NonNull
    EGLSurface createWindowSurface(@NonNull Surface target) {
      if (!target.isValid()) {
        return EGL14.EGL_NO_SURFACE;
      }
      EGLSurface surface;
      try {
        surface =
            EGL14.eglCreateWindowSurface(display, config, target, new int[] {EGL14.EGL_NONE}, 0);
      } catch (IllegalArgumentException e) {
        // The surface went away between the check and here.
        return EGL14.EGL_NO_SURFACE;
      }
      if (surface == null || surface == EGL14.EGL_NO_SURFACE) {
        Log.w(TAG, "eglCreateWindowSurface: 0x" + Integer.toHexString(EGL14.eglGetError()));
        return EGL14.EGL_NO_SURFACE;
      }
      // Never wait on Flutter to take a frame - that would hold up every player on this thread.
      // A newer frame replaces one Flutter hasn't taken yet.
      if (makeCurrent(surface)) {
        EGL14.eglSwapInterval(display, 0);
      }
      return surface;
    }

    boolean drawFrame(int texture, @NonNull float[] texMatrix, int width, int height) {
      GLES20.glViewport(0, 0, width, height);
      GLES20.glUseProgram(program);
      GLES20.glActiveTexture(GLES20.GL_TEXTURE0);
      GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, texture);
      GLES20.glUniformMatrix4fv(texMatrixUniform, 1, false, texMatrix, 0);
      GLES20.glEnableVertexAttribArray(positionAttribute);
      GLES20.glVertexAttribPointer(positionAttribute, 2, GLES20.GL_FLOAT, false, 0, positions);
      GLES20.glEnableVertexAttribArray(texCoordAttribute);
      GLES20.glVertexAttribPointer(texCoordAttribute, 2, GLES20.GL_FLOAT, false, 0, texCoords);
      GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4);
      GLES20.glDisableVertexAttribArray(positionAttribute);
      GLES20.glDisableVertexAttribArray(texCoordAttribute);
      return GLES20.glGetError() == GLES20.GL_NO_ERROR;
    }

    /** Runs [task] on the GL thread and waits for it, up to a second. */
    void runAndWait(@NonNull Runnable task) {
      if (Looper.myLooper() == handler.getLooper()) {
        task.run();
        return;
      }
      CountDownLatch done = new CountDownLatch(1);
      handler.post(
          () -> {
            try {
              task.run();
            } finally {
              done.countDown();
            }
          });
      try {
        if (!done.await(WAIT_MS, TimeUnit.MILLISECONDS)) {
          Log.w(TAG, "The video GL thread took over " + WAIT_MS + "ms");
        }
      } catch (InterruptedException e) {
        Thread.currentThread().interrupt();
      }
    }

    private int link() {
      int vertex = compile(GLES20.GL_VERTEX_SHADER, VERTEX_SHADER);
      int fragment = compile(GLES20.GL_FRAGMENT_SHADER, FRAGMENT_SHADER);
      if (vertex == 0 || fragment == 0) {
        return 0;
      }
      int linked = GLES20.glCreateProgram();
      GLES20.glAttachShader(linked, vertex);
      GLES20.glAttachShader(linked, fragment);
      GLES20.glLinkProgram(linked);
      GLES20.glDeleteShader(vertex);
      GLES20.glDeleteShader(fragment);
      int[] status = new int[1];
      GLES20.glGetProgramiv(linked, GLES20.GL_LINK_STATUS, status, 0);
      if (status[0] == 0) {
        Log.e(TAG, "Program link failed: " + GLES20.glGetProgramInfoLog(linked));
        GLES20.glDeleteProgram(linked);
        return 0;
      }
      return linked;
    }

    private static int compile(int type, @NonNull String source) {
      int shader = GLES20.glCreateShader(type);
      GLES20.glShaderSource(shader, source);
      GLES20.glCompileShader(shader);
      int[] status = new int[1];
      GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, status, 0);
      if (status[0] == 0) {
        Log.e(TAG, "Shader compile failed: " + GLES20.glGetShaderInfoLog(shader));
        GLES20.glDeleteShader(shader);
        return 0;
      }
      return shader;
    }

    private static boolean failed(@NonNull String step) {
      Log.e(TAG, step + " failed: 0x" + Integer.toHexString(EGL14.eglGetError()));
      return false;
    }

    @NonNull
    private static FloatBuffer floats(float... values) {
      FloatBuffer buffer =
          ByteBuffer.allocateDirect(values.length * 4).order(ByteOrder.nativeOrder()).asFloatBuffer();
      buffer.put(values).position(0);
      return buffer;
    }
  }
}
