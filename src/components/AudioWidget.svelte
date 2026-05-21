<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { listen } from '@tauri-apps/api/event';

  let isPlaying = $state(false);
  let currentSong = $state('暂无播放');
  let currentArtist = $state('未知');
  let progress = $state(0); // 0-100 (模拟进度条)
  
  let unlisten: (() => void) | null = null;
  let progressInterval: ReturnType<typeof setInterval>;

  onMount(async () => {
    unlisten = await listen<{title: string, artist: string, is_playing: boolean}>('media-update', (event) => {
      const payload = event.payload;
      
      if (payload.title && payload.title !== currentSong) {
        currentSong = payload.title;
        progress = 0; // 重置进度
      }
      if (payload.artist) {
        currentArtist = payload.artist;
      }
      
      isPlaying = payload.is_playing;
    });

    // 模拟平滑进度条
    progressInterval = setInterval(() => {
      if (isPlaying) {
        progress += 0.2;
        if (progress > 100) progress = 0;
      }
    }, 1000);
  });

  onDestroy(() => {
    if (unlisten) unlisten();
    if (progressInterval) clearInterval(progressInterval);
  });
</script>

<div class="music-card">
  <div class="album-cover" class:playing={isPlaying}>
    <div class="vinyl-hole"></div>
  </div>
  
  <div class="track-info">
    <div class="song-title" title={currentSong}>{currentSong}</div>
    <div class="artist" title={currentArtist}>{currentArtist}</div>
    
    <div class="progress-bar">
      <div class="progress-fill" style="width: {progress}%"></div>
    </div>
  </div>

  <div class="controls">
    <button class="btn" aria-label="上一首">
      <span class="material-symbols-rounded">skip_previous</span>
    </button>
    <button class="btn play" aria-label={isPlaying ? '播放中' : '已暂停'}>
      <span class="material-symbols-rounded">{isPlaying ? 'pause' : 'play_arrow'}</span>
    </button>
    <button class="btn" aria-label="下一首">
      <span class="material-symbols-rounded">skip_next</span>
    </button>
  </div>
</div>

<style>
  .music-card {
    background-color: var(--bg-panel0, rgba(255, 255, 255, 0.8));
    backdrop-filter: blur(10px);
    border: 1px solid var(--border-subtle, rgba(0, 0, 0, 0.1));
    border-radius: var(--radius-xl, 20px);
    padding: 20px;
    display: flex;
    align-items: center;
    gap: 16px;
    box-shadow: var(--shadow-md, 0 4px 6px rgba(0,0,0,0.1));
  }

  :global([data-theme="dark"]) .music-card {
    background-color: var(--bg-panel0, rgba(30, 30, 30, 0.8));
    border-color: var(--border-subtle, rgba(255, 255, 255, 0.1));
  }

  .album-cover {
    width: 64px;
    height: 64px;
    border-radius: 50%; /* 圆形唱片风格 */
    background: conic-gradient(from 0deg, #ff9a9e, #fecfef, #ff9a9e);
    display: flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
    box-shadow: 0 4px 12px rgba(0,0,0,0.15);
    transition: transform 0.3s ease;
  }

  .vinyl-hole {
    width: 16px;
    height: 16px;
    background-color: var(--bg-panel0, #fff);
    border-radius: 50%;
    box-shadow: inset 0 2px 4px rgba(0,0,0,0.2);
  }

  :global([data-theme="dark"]) .vinyl-hole {
    background-color: var(--bg-panel0, #1a1a1a);
  }

  .album-cover.playing {
    animation: spin 4s linear infinite;
  }

  @keyframes spin {
    from { transform: rotate(0deg); }
    to { transform: rotate(360deg); }
  }

  .track-info {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .song-title {
    font-size: 15px;
    font-weight: 700;
    color: var(--text-primary, #333);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  :global([data-theme="dark"]) .song-title {
    color: var(--text-primary, #eee);
  }

  .artist {
    font-size: 13px;
    font-weight: 500;
    color: var(--text-secondary, #666);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  :global([data-theme="dark"]) .artist {
    color: var(--text-secondary, #aaa);
  }

  .progress-bar {
    width: 100%;
    height: 4px;
    background: var(--bg-element, rgba(0,0,0,0.1));
    border-radius: 2px;
    margin-top: 8px;
    overflow: hidden;
  }

  :global([data-theme="dark"]) .progress-bar {
    background: var(--bg-element, rgba(255,255,255,0.1));
  }

  .progress-fill {
    height: 100%;
    background: var(--accent-blue, #0A84FF);
    border-radius: 2px;
    transition: width 0.1s linear;
  }

  .controls {
    display: flex;
    gap: 8px;
  }

  .btn {
    background: transparent;
    border: none;
    color: var(--text-secondary, #666);
    cursor: pointer;
    width: 32px;
    height: 32px;
    border-radius: 50%;
    display: flex;
    align-items: center;
    justify-content: center;
    transition: all 0.2s;
  }

  :global([data-theme="dark"]) .btn {
    color: var(--text-secondary, #aaa);
  }

  .btn:hover {
    background: var(--bg-panel-hover, rgba(0,0,0,0.05));
    color: var(--text-primary, #333);
  }

  :global([data-theme="dark"]) .btn:hover {
    background: var(--bg-panel-hover, rgba(255,255,255,0.05));
    color: var(--text-primary, #eee);
  }

  .btn.play {
    background: var(--text-primary, #333);
    color: var(--bg-app, #fff);
  }

  :global([data-theme="dark"]) .btn.play {
    background: var(--text-primary, #eee);
    color: var(--bg-app, #222);
  }

  .btn.play:hover {
    transform: scale(1.05);
  }
</style>
