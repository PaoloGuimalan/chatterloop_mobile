// CHATTERLOOP PATCH - not part of the published plugin. See the
// video_player_android entry under dependency_overrides in the app's
// pubspec.yaml for why this package is vendored.

package io.flutter.plugins.videoplayer;

import android.content.Context;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.OptIn;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.database.StandaloneDatabaseProvider;
import androidx.media3.datasource.DataSource;
import androidx.media3.datasource.cache.CacheDataSource;
import androidx.media3.datasource.cache.LeastRecentlyUsedCacheEvictor;
import androidx.media3.datasource.cache.SimpleCache;
import androidx.media3.exoplayer.DefaultLoadControl;
import androidx.media3.exoplayer.DefaultRenderersFactory;
import androidx.media3.exoplayer.ExoPlayer;
import java.io.File;

/**
 * How the app's players are built, so they behave like a browser's video elements - each one
 * plays, several at once if asked, and none of them fails because others exist.
 *
 * <p>Three changes to ExoPlayer's defaults:
 *
 * <ul>
 *   <li><b>Decoder fallback.</b> A phone has a handful of hardware video decoders. With the default
 *       (no fallback) the player that asks for one when they are all taken fails outright - the
 *       "video couldn't be played" that appeared whenever several videos were open, or when
 *       switching between them faster than the old ones were released. With fallback it moves on to
 *       the next decoder, a software one, the way a browser does.
 *   <li><b>Start sooner.</b> The default waits for 2.5s of media before it is ready (and
 *       initialize() in Dart waits for "ready"). 0.5s starts playback as soon as there is
 *       something to show; after a stall it waits for 1.5s so it doesn't stutter.
 *   <li><b>A disk cache.</b> One shared, size-capped cache for every network video, so a video
 *       seen before - scrolled past and back, a moment replayed - starts from disk instead of the
 *       network.
 * </ul>
 *
 * <p>A separate patch, {@link io.flutter.plugins.videoplayer.texture.TextureVideoPlayer}'s use of
 * CroppedVideoOutput, takes the decoder's padding (a green strip) off every frame.
 */
@OptIn(markerClass = UnstableApi.class)
public final class ChatterloopPlayback {
  private ChatterloopPlayback() {}

  /** Least-recently-used videos are dropped past this. */
  private static final long CACHE_BYTES = 256L * 1024 * 1024;

  private static final int MIN_BUFFER_MS = 10_000;
  private static final int MAX_BUFFER_MS = 30_000;
  private static final int START_BUFFER_MS = 500;
  private static final int REBUFFER_MS = 1_500;

  @Nullable private static SimpleCache cache;

  /** The renderers and buffering described above, applied to a player being built. */
  public static void configure(
      @NonNull Context context,
      @NonNull ExoPlayer.Builder builder,
      @Nullable Long backBufferDurationMs) {
    builder.setRenderersFactory(
        new DefaultRenderersFactory(context).setEnableDecoderFallback(true));
    DefaultLoadControl.Builder load =
        new DefaultLoadControl.Builder()
            .setBufferDurationsMs(MIN_BUFFER_MS, MAX_BUFFER_MS, START_BUFFER_MS, REBUFFER_MS);
    if (backBufferDurationMs != null && backBufferDurationMs > 0) {
      load.setBackBuffer(
          (int) Math.min(backBufferDurationMs, Integer.MAX_VALUE),
          /* retainBackBufferFromKeyframe= */ true);
    }
    builder.setLoadControl(load.build());
  }

  /** [upstream] read through the shared disk cache. */
  @NonNull
  public static DataSource.Factory cached(
      @NonNull Context context, @NonNull DataSource.Factory upstream) {
    return new CacheDataSource.Factory()
        .setCache(cache(context))
        .setUpstreamDataSourceFactory(upstream)
        // A broken cache file must never stop a video playing - read from the network instead.
        .setFlags(CacheDataSource.FLAG_IGNORE_CACHE_ON_ERROR);
  }

  /** One per process: SimpleCache refuses a second instance on the same folder. */
  @NonNull
  private static synchronized SimpleCache cache(@NonNull Context context) {
    if (cache == null) {
      Context app = context.getApplicationContext();
      cache =
          new SimpleCache(
              new File(app.getCacheDir(), "chatterloop_video_cache"),
              new LeastRecentlyUsedCacheEvictor(CACHE_BYTES),
              new StandaloneDatabaseProvider(app));
    }
    return cache;
  }
}
