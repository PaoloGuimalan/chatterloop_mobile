// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.videoplayer.texture;

import android.content.Context;
import android.os.Build;
import android.view.Surface;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.RestrictTo;
import androidx.annotation.VisibleForTesting;
import androidx.media3.common.MediaItem;
import androidx.media3.common.Player;
import androidx.media3.common.VideoSize;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.exoplayer.ExoPlayer;
import io.flutter.plugins.videoplayer.ChatterloopPlayback;
import io.flutter.plugins.videoplayer.ExoPlayerEventListener;
import io.flutter.plugins.videoplayer.VideoAsset;
import io.flutter.plugins.videoplayer.VideoPlayer;
import io.flutter.plugins.videoplayer.VideoPlayerCallbacks;
import io.flutter.plugins.videoplayer.VideoPlayerOptions;
import io.flutter.view.TextureRegistry.SurfaceProducer;

/**
 * A subclass of {@link VideoPlayer} that adds functionality related to texture view as a way of
 * displaying the video in the app.
 *
 * <p>It manages the lifecycle of the texture and ensures that the video is properly displayed on
 * the texture.
 */
public final class TextureVideoPlayer extends VideoPlayer implements SurfaceProducer.Callback {
  // True when the ExoPlayer instance has a null surface.
  private boolean needsSurface = true;

  /**
   * Creates a texture video player.
   *
   * @param context application context.
   * @param events event callbacks.
   * @param surfaceProducer produces a texture to render to.
   * @param asset asset to play.
   * @param options options for playback.
   * @return a video player instance.
   */
  // TODO: Migrate to stable API, see https://github.com/flutter/flutter/issues/147039.
  @UnstableApi
  @NonNull
  public static TextureVideoPlayer create(
      @NonNull Context context,
      @NonNull VideoPlayerCallbacks events,
      @NonNull SurfaceProducer surfaceProducer,
      @NonNull VideoAsset asset,
      @NonNull VideoPlayerOptions options) {
    return new TextureVideoPlayer(
        events,
        surfaceProducer,
        asset.getMediaItem(),
        options,
        () -> {
          ExoPlayer.Builder builder = new ExoPlayer.Builder(context);
          if (options.backBufferDurationMs != null && options.backBufferDurationMs < 0) {
            throw new IllegalArgumentException("backBufferDurationMs must be at least 0");
          }
          // CHATTERLOOP PATCH: decoder fallback, a faster start, and the back buffer
          // above - see ChatterloopPlayback.
          ChatterloopPlayback.configure(context, builder, options.backBufferDurationMs);
          androidx.media3.exoplayer.trackselection.DefaultTrackSelector trackSelector =
              new androidx.media3.exoplayer.trackselection.DefaultTrackSelector(context);
          builder
              .setTrackSelector(trackSelector)
              .setMediaSourceFactory(asset.getMediaSourceFactory(context));
          return builder.build();
        });
  }

  // TODO: Migrate to stable API, see https://github.com/flutter/flutter/issues/147039.
  @UnstableApi
  @VisibleForTesting
  public TextureVideoPlayer(
      @NonNull VideoPlayerCallbacks events,
      @NonNull SurfaceProducer surfaceProducer,
      @NonNull MediaItem mediaItem,
      @NonNull VideoPlayerOptions options,
      @NonNull ExoPlayerProvider exoPlayerProvider) {
    super(events, mediaItem, options, surfaceProducer, exoPlayerProvider);

    surfaceProducer.setCallback(this);

    // CHATTERLOOP PATCH: where the producer would show the decoder's padding (the green strip),
    // frames go through CroppedVideoOutput, which hands them over cropped and upright.
    if (drawsThroughCrop) {
      croppedOutput = new CroppedVideoOutput(surfaceProducer);
      this.exoPlayer.addListener(
          new Player.Listener() {
            @Override
            public void onVideoSizeChanged(@NonNull VideoSize videoSize) {
              if (croppedOutput != null) {
                croppedOutput.setVideoSize(videoSize.width, videoSize.height);
              }
            }
          });
      this.exoPlayer.setVideoSurface(croppedOutput.inputSurface());
      needsSurface = false;
      return;
    }

    Surface surface = surfaceProducer.getSurface();
    this.exoPlayer.setVideoSurface(surface);
    needsSurface = surface == null;
  }

  // CHATTERLOOP PATCH: set when frames are drawn through CroppedVideoOutput.
  @Nullable private CroppedVideoOutput croppedOutput;

  // CHATTERLOOP PATCH: whether this player's frames go through CroppedVideoOutput - when the
  // producer itself would ignore crop and rotation, and GL can be used. Decided in
  // createExoPlayerEventListener, which the super constructor calls; it must have NO initializer,
  // or that would reset it once the super constructor returns.
  private boolean drawsThroughCrop;

  @NonNull
  @Override
  protected ExoPlayerEventListener createExoPlayerEventListener(
      @NonNull ExoPlayer exoPlayer, @Nullable SurfaceProducer surfaceProducer) {
    if (surfaceProducer == null) {
      throw new IllegalArgumentException(
          "surfaceProducer cannot be null to create an ExoPlayerEventListener for"
              + " TextureVideoPlayer.");
    }
    boolean surfaceProducerHandlesCropAndRotation = surfaceProducer.handlesCropAndRotation();
    // CHATTERLOOP PATCH: CroppedVideoOutput hands frames over upright, so Dart must not rotate
    // them again.
    drawsThroughCrop =
        !surfaceProducerHandlesCropAndRotation
            && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
            && CroppedVideoOutput.isAvailable();
    if (drawsThroughCrop) {
      surfaceProducerHandlesCropAndRotation = true;
    }
    return new TextureExoPlayerEventListener(
        exoPlayer, videoPlayerEvents, surfaceProducerHandlesCropAndRotation);
  }

  @RestrictTo(RestrictTo.Scope.LIBRARY)
  public void onSurfaceAvailable() {
    if (croppedOutput != null) {
      croppedOutput.onSurfaceAvailable();
      return;
    }
    if (needsSurface) {
      // TextureVideoPlayer must always set a surfaceProducer.
      assert surfaceProducer != null;
      exoPlayer.setVideoSurface(surfaceProducer.getSurface());
      needsSurface = false;
    }
  }

  @RestrictTo(RestrictTo.Scope.LIBRARY)
  public void onSurfaceCleanup() {
    if (croppedOutput != null) {
      // The decoder keeps its own surface; only the copy onto Flutter's stops.
      croppedOutput.onSurfaceCleanup();
      return;
    }
    exoPlayer.setVideoSurface(null);
    needsSurface = true;
  }

  public void dispose() {
    // Super must be called first to ensure the player is released before the surface.
    super.dispose();

    // CHATTERLOOP PATCH: and the GL pass stops drawing before the producer goes.
    if (croppedOutput != null) {
      croppedOutput.release();
      croppedOutput = null;
    }

    // TextureVideoPlayer must always set a surfaceProducer.
    assert surfaceProducer != null;
    surfaceProducer.release();
  }
}
